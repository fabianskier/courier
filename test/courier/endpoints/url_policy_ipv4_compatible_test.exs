defmodule Courier.Endpoints.URLPolicyIPv4CompatibleTest do
  use ExUnit.Case, async: true

  alias Courier.Endpoints.URLPolicy

  describe "Requirement: Endpoint URLs are safe" do
    test "Scenario: Private address rejected" do
      for url <- [
            "https://[::127.0.0.1]/",
            "https://[::10.0.0.5]/",
            "https://[::93.184.216.34]/",
            "https://[::]/",
            "https://[::1]/"
          ] do
        assert {:error, :non_public_address} = URLPolicy.check(url), "expected #{url} rejected"
      end

      refute URLPolicy.public_address?({0, 0, 0, 0, 0, 0, 0x7F00, 1})
      refute URLPolicy.public_address?({0, 0, 0, 0, 0, 0, 0xFFFF, 0xFFFF})

      assert :ok = URLPolicy.check("https://[2606:4700::1111]/")
      assert :ok = URLPolicy.check("https://[::1:0:0:1]/")
    end
  end
end
