defmodule Courier.Vault do
  @moduledoc """
  Application-level encryption for secrets stored at rest (Cloak, AES-256-GCM).

  The key comes from `config :courier, Courier.Vault, key: <32 bytes>`: a fixed,
  non-secret key in dev and test, and `COURIER_ENCRYPTION_KEY` in production.
  """

  use Cloak.Vault, otp_app: :courier

  @impl GenServer
  def init(config) do
    {key, config} = Keyword.pop!(config, :key)

    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key, iv_length: 12}
      )

    {:ok, config}
  end
end
