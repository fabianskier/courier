defmodule Courier.Delivery.Signer do
  @moduledoc """
  Builds the Standard Webhooks headers for a request.

  Each signature is `v1,` followed by the base64 HMAC-SHA256 of
  `"<id>.<timestamp>.<body>"`, keyed with the base64-decoded part of a
  `whsec_` secret. One signature is produced per secret, in the given order
  (current secret first), separated by spaces.
  """

  @prefix "whsec_"

  @doc """
  Returns the `webhook-id`, `webhook-timestamp` and `webhook-signature`
  headers for `event_id`, `timestamp` (Unix seconds) and the exact `body`
  bytes, signed with every secret in `secrets`.
  """
  @spec headers(String.t(), integer(), iodata(), [String.t(), ...]) :: [
          {String.t(), String.t()}
        ]
  def headers(event_id, timestamp, body, [_ | _] = secrets)
      when is_binary(event_id) and is_integer(timestamp) do
    signature =
      Enum.map_join(secrets, " ", &("v1," <> sign(&1, event_id, timestamp, body)))

    [
      {"webhook-id", event_id},
      {"webhook-timestamp", Integer.to_string(timestamp)},
      {"webhook-signature", signature}
    ]
  end

  @doc """
  Returns the base64 HMAC-SHA256 signature (without the `v1,` prefix) of
  `"<id>.<timestamp>.<body>"` with the given `whsec_` secret.
  """
  @spec sign(String.t(), String.t(), integer(), iodata()) :: String.t()
  def sign(secret, event_id, timestamp, body) do
    :hmac
    |> :crypto.mac(:sha256, key(secret), [event_id, ?., Integer.to_string(timestamp), ?., body])
    |> Base.encode64()
  end

  defp key(@prefix <> encoded), do: Base.decode64!(encoded)
end
