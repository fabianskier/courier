defmodule Courier.AuditFixtures do
  @moduledoc """
  Test helpers for storing deliveries and attempts directly, without the
  delivery worker.
  """

  alias Courier.Audit.Attempt
  alias Courier.Delivery.Delivery
  alias Courier.Repo

  @doc """
  Inserts a `pending` delivery and returns it. Creates an endpoint and an event
  of the same merchant unless `endpoint_id` and `event_id` are given.
  """
  def delivery_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    {endpoint_id, merchant_id} =
      case attrs do
        %{endpoint_id: id} ->
          {id, nil}

        _ ->
          {endpoint, _secret} = Courier.EndpointsFixtures.endpoint_fixture()
          {endpoint.id, endpoint.merchant_id}
      end

    attrs =
      attrs
      |> Map.put(:endpoint_id, endpoint_id)
      |> Map.put_new_lazy(:event_id, fn ->
        event_attrs = if merchant_id, do: %{merchant_id: merchant_id}, else: %{}
        Courier.EventsFixtures.event_fixture(event_attrs).id
      end)
      |> Map.put_new(:status, "pending")
      |> Map.put_new_lazy(:window_ends_at, fn -> DateTime.add(DateTime.utc_now(), 3, :day) end)

    %Delivery{}
    |> Delivery.create_changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Inserts an attempt and returns it. Creates a delivery unless `delivery_id`
  is given; defaults to number 1 and a `200` response.
  """
  def attempt_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new_lazy(:delivery_id, fn -> delivery_fixture().id end)
      |> Map.put_new(:number, 1)
      |> Map.put_new_lazy(:started_at, &DateTime.utc_now/0)
      |> Map.put_new(:duration_ms, 42)
      |> Map.put_new(:url, "https://hooks.public.test/courier")
      |> Map.put_new(:request_headers, %{
        "content-type" => "application/json",
        "webhook-signature" => "[redacted]"
      })
      |> Map.put_new(:response_status, 200)
      |> Map.put_new(:response_body, "ok")

    %Attempt{}
    |> Attempt.create_changeset(attrs)
    |> Repo.insert!()
  end
end
