defmodule Courier.Endpoints.URLPolicyTest do
  use ExUnit.Case, async: true

  alias Courier.Endpoints.URLPolicy

  describe "Requirement: Endpoint URLs are safe" do
    test "Scenario: Public https URL accepted" do
      assert :ok = URLPolicy.check("https://hooks.public.test/courier")
      assert :ok = URLPolicy.check("HTTPS://Hooks.Public.Test:8443/courier?x=1")
      assert :ok = URLPolicy.check("https://93.184.216.34/hooks")
      assert :ok = URLPolicy.check("https://[2606:2800:220:1:248:1893:25c8:1946]/hooks")
      # Just outside the blocked ranges.
      assert :ok = URLPolicy.check("https://100.128.0.1/")
      assert :ok = URLPolicy.check("https://172.32.0.1/")
      assert :ok = URLPolicy.check("https://198.20.0.1/")
      assert :ok = URLPolicy.check("https://223.255.255.255/")
      assert :ok = URLPolicy.check("https://[::ffff:93.184.216.34]/")
    end

    test "Scenario: Plain http rejected" do
      assert {:error, :scheme_not_allowed} = URLPolicy.check("http://hooks.public.test/courier")
      assert {:error, :scheme_not_allowed} = URLPolicy.check("ftp://hooks.public.test/courier")
      assert {:error, :scheme_not_allowed} = URLPolicy.check("hooks.public.test/courier")

      assert :ok = URLPolicy.check("http://hooks.public.test/courier", require_https: false)
    end

    test "Scenario: Private address rejected" do
      blocked_ipv4 = [
        "0.0.0.0",
        "0.255.255.255",
        "10.0.0.5",
        "10.255.255.255",
        "100.64.0.1",
        "100.127.255.255",
        "127.0.0.1",
        "127.255.255.254",
        "169.254.169.254",
        "172.16.0.1",
        "172.31.255.255",
        "192.0.0.1",
        "192.168.1.1",
        "198.18.0.1",
        "198.19.255.255",
        "224.0.0.1",
        "239.255.255.255",
        "240.0.0.1",
        "255.255.255.255"
      ]

      for ip <- blocked_ipv4 do
        assert {:error, :non_public_address} = URLPolicy.check("https://#{ip}/"), ip
      end

      blocked_ipv6 = [
        "::",
        "::1",
        "fc00::1",
        "fd00::1",
        "fdff:ffff::1",
        "fe80::1",
        "febf::1",
        "ff02::1",
        # IPv4-mapped
        "::ffff:127.0.0.1",
        "::ffff:10.0.0.5",
        "::ffff:169.254.169.254",
        "::ffff:7f00:1",
        # NAT64
        "64:ff9b::127.0.0.1",
        "64:ff9b::a00:5"
      ]

      for ip <- blocked_ipv6 do
        assert {:error, :non_public_address} = URLPolicy.check("https://[#{ip}]/"), ip
      end

      # Names that resolve to private addresses.
      assert {:error, :non_public_address} = URLPolicy.check("https://hooks.private.test/")
      assert {:error, :non_public_address} = URLPolicy.check("https://hooks.v6private.test/")

      # A single non-public address among public ones is enough to reject.
      resolver = fn _host -> {:ok, [{93, 184, 216, 34}, {127, 0, 0, 1}]} end

      assert {:error, :non_public_address} =
               URLPolicy.check("https://x.test/", resolver: resolver)
    end

    test "Scenario: Credentials in URL rejected" do
      assert {:error, :userinfo_not_allowed} =
               URLPolicy.check("https://user:pass@hooks.public.test/")

      assert {:error, :userinfo_not_allowed} = URLPolicy.check("https://user@hooks.public.test/")
    end

    test "Scenario: Unresolvable host rejected" do
      assert {:error, :unresolvable_host} = URLPolicy.check("https://nowhere.example.com/")

      empty = fn _host -> {:ok, []} end
      assert {:error, :unresolvable_host} = URLPolicy.check("https://x.test/", resolver: empty)

      assert {:error, :missing_host} = URLPolicy.check("https:///path")
      assert {:error, :invalid_url} = URLPolicy.check("https://exa mple.com/")
      assert {:error, :invalid_url} = URLPolicy.check(nil)
    end

    test "Scenario: Allowlisted host accepted" do
      opts = [require_https: false, allowed_hosts: ["demo-receiver", "Hooks.Private.Test"]]

      assert :ok = URLPolicy.check("http://demo-receiver:4001/hooks", opts)
      assert :ok = URLPolicy.check("https://hooks.private.test/", opts)

      # The allowlist does not bypass scheme or credential checks.
      assert {:error, :scheme_not_allowed} =
               URLPolicy.check("http://demo-receiver:4001/hooks",
                 allowed_hosts: ["demo-receiver"]
               )

      assert {:error, :userinfo_not_allowed} =
               URLPolicy.check("http://u:p@demo-receiver:4001/hooks", opts)

      # Without the allowlist the same host is rejected.
      assert {:error, :unresolvable_host} =
               URLPolicy.check("http://demo-receiver:4001/hooks", require_https: false)
    end
  end
end
