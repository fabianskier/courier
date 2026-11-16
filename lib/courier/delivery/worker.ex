defmodule Courier.Delivery.Worker do
  @moduledoc """
  Sends one pending delivery to its endpoint and records the outcome.

  The worker only wires the pure pieces together: `URLPolicy` checks the URL
  again, `Signer` signs the exact body bytes, `Client` sends the request,
  `RetryPolicy` classifies the result and schedules the next attempt, and
  `Courier.Delivery.record_attempt/3` stores the attempt and moves the
  delivery forward. A retry is an Oban snooze; the delivery's retry window,
  not `max_attempts`, is what stops retries.
  """

  use Oban.Worker, max_attempts: 10

  import Ecto.Query, warn: false

  alias Courier.Delivery
  alias Courier.Delivery.Client
  alias Courier.Delivery.Delivery, as: DeliveryRecord
  alias Courier.Delivery.RetryPolicy
  alias Courier.Delivery.Signer
  alias Courier.Endpoints
  alias Courier.Endpoints.URLPolicy
  alias Courier.Repo

  @disabled_snooze_seconds 60
  @redacted "[redacted]"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}}) do
    now = DateTime.utc_now()

    case load(delivery_id) do
      %DeliveryRecord{status: "pending"} = delivery -> deliver(delivery, now)
      _missing_or_finished -> :ok
    end
  end

  defp load(delivery_id) do
    case Ecto.UUID.cast(delivery_id) do
      {:ok, id} -> DeliveryRecord |> Repo.get(id) |> Repo.preload([:endpoint, :event])
      :error -> nil
    end
  end

  defp deliver(%DeliveryRecord{} = delivery, now) do
    cond do
      DateTime.compare(now, delivery.window_ends_at) != :lt ->
        with {:ok, _} <- Delivery.fail_without_attempt(delivery.id, now), do: :ok

      not delivery.endpoint.enabled ->
        # The endpoint's queue is normally stopped; this covers the race.
        {:snooze, @disabled_snooze_seconds}

      true ->
        check_and_send(delivery, now)
    end
  end

  defp check_and_send(%DeliveryRecord{endpoint: endpoint} = delivery, now) do
    case URLPolicy.check(endpoint.url) do
      :ok ->
        send_request(delivery, now)

      {:error, :unresolvable_host = reason} ->
        record(delivery, rejected_attempt(endpoint.url, now, "dns: #{reason}"), :retry, nil, now)

      {:error, reason} ->
        attrs = rejected_attempt(endpoint.url, now, "url_rejected: #{reason}")
        record(delivery, attrs, :give_up, nil, now)
    end
  end

  defp rejected_attempt(url, now, error) do
    %{started_at: now, duration_ms: 0, url: url, request_headers: %{}, error: error}
  end

  defp send_request(%DeliveryRecord{endpoint: endpoint, event: event} = delivery, now) do
    body = request_body(event)

    headers =
      [
        {"content-type", "application/json"},
        {"user-agent", user_agent()},
        {"courier-delivery-id", delivery.id}
      ] ++
        Signer.headers(
          event.id,
          DateTime.to_unix(now),
          body,
          Endpoints.signing_secrets(endpoint, now)
        )

    started = System.monotonic_time()

    {result, outcome} =
      Courier.Telemetry.span_attempt(delivery, now, fn ->
        result = Client.post(endpoint.url, body, headers)
        {result, RetryPolicy.classify(result, endpoint.retry_on_4xx)}
      end)

    duration_ms =
      System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)

    finished_at = DateTime.utc_now()

    attrs =
      Map.merge(
        %{
          started_at: now,
          duration_ms: duration_ms,
          url: endpoint.url,
          request_headers: stored_headers(headers)
        },
        result_attrs(result)
      )

    record(delivery, attrs, outcome, retry_after(result, finished_at), finished_at)
  end

  @doc """
  Encodes the request body of `event`: `id`, `type`, `timestamp` (ISO 8601
  `occurred_at`), `merchant_id` and `data` (the payload).
  """
  @spec request_body(Courier.Ingestion.Event.t()) :: String.t()
  def request_body(event) do
    Jason.encode!(%{
      id: event.id,
      type: event.type,
      timestamp: DateTime.to_iso8601(event.occurred_at),
      merchant_id: event.merchant_id,
      data: event.payload
    })
  end

  @doc """
  Returns the headers as stored on an attempt: every header sent, with
  `webhook-signature` replaced by `"#{@redacted}"`.
  """
  @spec stored_headers([{String.t(), String.t()}]) :: %{String.t() => String.t()}
  def stored_headers(headers) do
    Map.new(headers, fn
      {"webhook-signature", _signature} -> {"webhook-signature", @redacted}
      {name, value} -> {name, value}
    end)
  end

  defp result_attrs({:ok, %{status: status, body: body}}),
    do: %{response_status: status, response_body: body}

  defp result_attrs({:error, reason}), do: %{error: reason}

  # Retry-After is only honoured on 429 and 503.
  defp retry_after({:ok, %{status: status, retry_after: value}}, now) when status in [429, 503],
    do: RetryPolicy.parse_retry_after(value, now)

  defp retry_after(_result, _now), do: nil

  defp record(%DeliveryRecord{} = delivery, attrs, outcome, retry_after, now) do
    {transition, snooze} = transition(delivery, outcome, retry_after, now)

    case Delivery.record_attempt(delivery.id, attrs, transition) do
      {:ok, :stale} -> :ok
      {:ok, _recorded} when is_integer(snooze) -> {:snooze, snooze}
      {:ok, _recorded} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp transition(_delivery, :success, _retry_after, now), do: {{:succeeded, now}, nil}
  defp transition(_delivery, :give_up, _retry_after, now), do: {{:failed, now}, nil}

  defp transition(%DeliveryRecord{} = delivery, :retry, retry_after, now) do
    delay = RetryPolicy.delay(delivery.attempt_count + 1, retry_after)

    case RetryPolicy.next(now, delay, delivery.window_ends_at) do
      {:retry_at, at} -> {{:retry_at, at}, delay}
      :window_ended -> {{:failed, now, :window_ended}, nil}
    end
  end

  defp user_agent do
    "courier/#{Application.spec(:courier, :vsn)}"
  end
end
