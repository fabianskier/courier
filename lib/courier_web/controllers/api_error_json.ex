defmodule CourierWeb.APIErrorJSON do
  @moduledoc """
  Renders API errors as `{"error": {"code": ..., "message": ...}}`.

  Used by `CourierWeb.FallbackController` and the authentication plugs, so
  every error from `/api/v1` has the same shape. Messages are fixed strings
  and never include values sent by the caller.
  """

  @doc "Renders an error with `code`, `message` and optional `details`."
  @spec error(map()) :: %{error: map()}
  def error(%{code: code, message: message} = assigns) do
    error =
      case Map.get(assigns, :details) do
        nil -> %{code: code, message: message}
        details -> %{code: code, message: message, details: details}
      end

    %{error: error}
  end
end
