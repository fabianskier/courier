defmodule CourierWeb.FallbackController do
  @moduledoc """
  Turns `{:error, reason}` results from API controllers into error responses
  rendered by `CourierWeb.APIErrorJSON`.
  """

  use CourierWeb, :controller

  alias CourierWeb.APIErrorJSON

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> respond(:unauthorized, %{code: "unauthorized", message: "A valid API key is required."})
  end

  def call(conn, {:error, :forbidden}) do
    respond(conn, :forbidden, %{
      code: "forbidden",
      message: "This API key lacks the required scope."
    })
  end

  def call(conn, {:error, :not_found}) do
    respond(conn, :not_found, %{code: "not_found", message: "Resource not found."})
  end

  def call(conn, {:error, :invalid_cursor}) do
    respond(conn, :unprocessable_entity, %{
      code: "invalid",
      message: "The cursor is invalid."
    })
  end

  def call(conn, {:error, :invalid_pagination}) do
    respond(conn, :unprocessable_entity, %{
      code: "invalid",
      message: "limit must be an integer from 1 to 100 and cursor a non-empty string."
    })
  end

  def call(conn, {:error, :merchant_disabled}) do
    respond(conn, :unprocessable_entity, %{
      code: "merchant_disabled",
      message: "The merchant is disabled."
    })
  end

  def call(conn, {:error, :delivery_in_progress}) do
    respond(conn, :conflict, %{
      code: "delivery_in_progress",
      message: "The delivery is still pending."
    })
  end

  def call(conn, {:error, :resend_in_progress}) do
    respond(conn, :conflict, %{
      code: "resend_in_progress",
      message: "The delivery already has a pending resend."
    })
  end

  def call(conn, {:error, :endpoint_disabled}) do
    respond(conn, :unprocessable_entity, %{
      code: "endpoint_disabled",
      message: "The delivery's endpoint is disabled."
    })
  end

  def call(conn, {:error, :idempotency_key_reused}) do
    respond(conn, :unprocessable_entity, %{
      code: "idempotency_key_reused",
      message: "This idempotency key was already used with a different request."
    })
  end

  def call(conn, {:error, :payload_too_large}) do
    respond(conn, :request_entity_too_large, %{
      code: "payload_too_large",
      message: "The payload must be at most 256 KB when encoded as JSON."
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    respond(conn, :unprocessable_entity, %{
      code: "invalid",
      message: "The request is invalid.",
      details: changeset_errors(changeset)
    })
  end

  defp respond(conn, status, error) do
    conn
    |> put_status(status)
    |> json(APIErrorJSON.error(error))
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", fn _ -> to_string_safe(value) end)
      end)
    end)
  end

  defp to_string_safe(value) when is_list(value), do: Enum.map_join(value, ", ", &to_string/1)
  defp to_string_safe(value), do: to_string(value)
end
