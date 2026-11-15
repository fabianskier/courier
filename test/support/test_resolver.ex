defmodule Courier.Endpoints.TestResolver do
  @moduledoc """
  Resolver used by `Courier.Endpoints.URLPolicy` in tests. It never touches the
  network and resolves by convention, so async tests need no shared state:

    * `*.public.test`    → `93.184.216.34`
    * `*.private.test`   → `10.0.0.5`
    * `*.v6private.test` → `fd00::1`
    * anything else      → `{:error, :nxdomain}`
  """

  @spec resolve(String.t()) :: {:ok, [:inet.ip_address()]} | {:error, :nxdomain}
  def resolve(host) when is_binary(host) do
    host = String.downcase(host)

    cond do
      String.ends_with?(host, ".public.test") -> {:ok, [{93, 184, 216, 34}]}
      String.ends_with?(host, ".private.test") -> {:ok, [{10, 0, 0, 5}]}
      String.ends_with?(host, ".v6private.test") -> {:ok, [{0xFD00, 0, 0, 0, 0, 0, 0, 1}]}
      true -> {:error, :nxdomain}
    end
  end
end
