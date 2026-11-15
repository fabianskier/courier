defmodule Courier.Encrypted.Binary do
  @moduledoc "Ecto type for binary fields encrypted at rest with `Courier.Vault`."

  use Cloak.Ecto.Binary, vault: Courier.Vault
end
