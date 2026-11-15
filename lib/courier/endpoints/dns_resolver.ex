defmodule Courier.Endpoints.DNSResolver do
  @moduledoc """
  Default resolver for `Courier.Endpoints.URLPolicy`: merges the IPv4 and IPv6
  addresses of a host using `:inet.getaddrs/2`.
  """

  @doc """
  Resolves `host` to all its IPv4 and IPv6 addresses.
  Returns `{:error, reason}` when neither family resolves.
  """
  @spec resolve(String.t()) :: {:ok, [:inet.ip_address()]} | {:error, term()}
  def resolve(host) when is_binary(host) do
    name = String.to_charlist(host)
    results = Enum.map([:inet, :inet6], &:inet.getaddrs(name, &1))

    case Enum.flat_map(results, fn
           {:ok, ips} -> ips
           {:error, _} -> []
         end) do
      [] ->
        Enum.find(results, {:error, :nxdomain}, &match?({:error, _}, &1))

      ips ->
        {:ok, Enum.uniq(ips)}
    end
  end
end
