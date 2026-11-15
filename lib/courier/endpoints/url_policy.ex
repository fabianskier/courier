defmodule Courier.Endpoints.URLPolicy do
  @moduledoc """
  Decides whether a URL is a safe webhook destination (SSRF protection).

  A URL passes when it uses an allowed scheme (`https`, or `http` when
  `require_https: false`), has a host and no user info, and its host is either
  on the allowlist or resolves only to public addresses.

  Options default to the application config:

      config :courier, Courier.Endpoints.URLPolicy,
        require_https: true,
        allowed_hosts: [],
        resolver: Courier.Endpoints.DNSResolver

  `resolver` is a module with `resolve/1` or a 1-arity function, both returning
  `{:ok, [:inet.ip_address()]} | {:error, term}`.

  The function is pure apart from the resolver, so delivery can re-check URLs
  right before each request.
  """

  import Bitwise

  @type reason ::
          :invalid_url
          | :scheme_not_allowed
          | :missing_host
          | :userinfo_not_allowed
          | :unresolvable_host
          | :non_public_address

  @defaults [
    require_https: true,
    allowed_hosts: [],
    resolver: Courier.Endpoints.DNSResolver
  ]

  # {first address, prefix length}
  @blocked_ipv4 [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @blocked_ipv6 [
    {{0, 0, 0, 0, 0, 0, 0, 0}, 128},
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @doc """
  Checks `url` against the policy. Returns `:ok` or `{:error, reason}`.
  """
  @spec check(String.t(), keyword()) :: :ok | {:error, reason()}
  def check(url, opts \\ [])

  def check(url, opts) when is_binary(url) do
    opts = options(opts)

    with {:ok, uri} <- parse(url),
         :ok <- check_scheme(uri, opts[:require_https]),
         {:ok, host} <- check_host(uri),
         :ok <- check_userinfo(uri) do
      if allowed_host?(host, opts[:allowed_hosts]) do
        :ok
      else
        check_addresses(host, opts[:resolver])
      end
    end
  end

  def check(_url, _opts), do: {:error, :invalid_url}

  @doc """
  Returns true when `ip` is a public address under this policy.
  IPv4-mapped and NAT64 IPv6 addresses are judged by their embedded IPv4.
  """
  @spec public_address?(:inet.ip_address()) :: boolean()
  def public_address?({a, b, c, d} = ip)
      when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255 do
    not Enum.any?(@blocked_ipv4, &in_range?(ip, &1, 32))
  end

  # IPv4-mapped (::ffff:0:0/96)
  def public_address?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: public_address?(embedded(hi, lo))

  # NAT64 well-known prefix (64:ff9b::/96)
  def public_address?({0x64, 0xFF9B, 0, 0, 0, 0, hi, lo}), do: public_address?(embedded(hi, lo))

  def public_address?({_, _, _, _, _, _, _, _} = ip) do
    not Enum.any?(@blocked_ipv6, &in_range?(ip, &1, 128))
  end

  def public_address?(_), do: false

  defp options(opts) do
    @defaults
    |> Keyword.merge(Application.get_env(:courier, __MODULE__, []))
    |> Keyword.merge(opts)
  end

  defp parse(url) do
    case URI.new(url) do
      {:ok, uri} -> {:ok, uri}
      {:error, _} -> {:error, :invalid_url}
    end
  end

  defp check_scheme(%URI{scheme: scheme}, require_https) when is_binary(scheme) do
    case String.downcase(scheme) do
      "https" -> :ok
      "http" when require_https == false -> :ok
      _ -> {:error, :scheme_not_allowed}
    end
  end

  defp check_scheme(_uri, _require_https), do: {:error, :scheme_not_allowed}

  defp check_host(%URI{host: host}) when is_binary(host) do
    case host |> String.trim_leading("[") |> String.trim_trailing("]") |> String.downcase() do
      "" -> {:error, :missing_host}
      host -> {:ok, host}
    end
  end

  defp check_host(_uri), do: {:error, :missing_host}

  defp check_userinfo(%URI{userinfo: nil}), do: :ok
  defp check_userinfo(_uri), do: {:error, :userinfo_not_allowed}

  defp allowed_host?(host, allowed_hosts) do
    Enum.any?(allowed_hosts, &(String.downcase(&1) == host))
  end

  defp check_addresses(host, resolver) do
    case addresses(host, resolver) do
      {:ok, [_ | _] = ips} ->
        if Enum.all?(ips, &public_address?/1), do: :ok, else: {:error, :non_public_address}

      _ ->
        {:error, :unresolvable_host}
    end
  end

  defp addresses(host, resolver) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> {:ok, [ip]}
      {:error, _} -> resolve(resolver, host)
    end
  end

  defp resolve(resolver, host) when is_function(resolver, 1), do: resolver.(host)
  defp resolve(resolver, host) when is_atom(resolver), do: resolver.resolve(host)

  defp embedded(hi, lo), do: {hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF}

  defp in_range?(ip, {base, prefix}, bits) do
    shift = bits - prefix
    to_integer(ip) >>> shift == to_integer(base) >>> shift
  end

  defp to_integer({_, _, _, _} = ip), do: fold(ip, 8)
  defp to_integer(ip), do: fold(ip, 16)

  defp fold(ip, width) do
    ip |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> acc <<< width ||| part end)
  end
end
