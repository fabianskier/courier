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
