defmodule Courier.AccessTest do
  use Courier.DataCase, async: true

  import Courier.AccessFixtures

  alias Courier.Access
  alias Courier.Access.ApiKey

  describe "Requirement: Create API keys" do
    test "Scenario: Key created with scopes" do
      assert {:ok, %{key: %ApiKey{} = key, token: token}} =
               Access.create_key(%{name: "dashboard", scopes: ["read", "write"]})

      assert token != ""
      assert key.name == "dashboard"
      assert Enum.sort(key.scopes) == ["read", "write"]
      assert key.revoked_at == nil

      stored = Repo.get!(ApiKey, key.id)
      assert stored.name == "dashboard"
      assert Enum.sort(stored.scopes) == ["read", "write"]
    end

    test "Scenario: Token is not stored in plaintext" do
      %{key: key, token: token} = api_key_fixture()

      stored = Repo.get!(ApiKey, key.id)
      assert stored.token_hash == :crypto.hash(:sha256, token)
      refute stored.token_hash == token

      {:ok, %{rows: [row]}} =
        Repo.query("SELECT * FROM api_keys WHERE id = $1", [Ecto.UUID.dump!(key.id)])

      refute Enum.any?(row, fn value -> is_binary(value) and String.contains?(value, token) end)
      refute Enum.any?(row, &(&1 == [token]))
    end

    test "Scenario: Duplicate name rejected" do
      api_key_fixture(%{name: "dashboard"})

      assert {:error, changeset} = Access.create_key(%{name: "dashboard", scopes: ["write"]})
      assert %{name: [_ | _]} = errors_on(changeset)
      assert length(Access.list_keys()) == 1
    end

    test "Scenario: Invalid scopes rejected" do
      assert {:error, changeset} = Access.create_key(%{name: "none", scopes: []})
      assert %{scopes: [_ | _]} = errors_on(changeset)

      assert {:error, changeset} = Access.create_key(%{name: "missing"})
      assert %{scopes: [_ | _]} = errors_on(changeset)

      assert {:error, changeset} = Access.create_key(%{name: "admin", scopes: ["read", "admin"]})
      assert %{scopes: [_ | _]} = errors_on(changeset)

      assert Access.list_keys() == []
    end
  end

  describe "Requirement: Tokens are unguessable and distinct" do
    test "Scenario: Token format" do
      %{token: token} = api_key_fixture()

      assert "ck_" <> encoded = token
      assert {:ok, random} = Base.url_decode64(encoded, padding: false)
      assert byte_size(random) >= 32
    end

    test "Scenario: Tokens differ" do
      %{token: token_a} = api_key_fixture()
      %{token: token_b} = api_key_fixture()

      refute token_a == token_b
    end
  end

  describe "Requirement: List API keys" do
    test "Scenario: Listing shows keys without secrets" do
      %{key: active, token: active_token} = api_key_fixture(%{name: "active"})
      %{token: revoked_token} = api_key_fixture(%{name: "revoked", scopes: ["write"]})
      {:ok, _} = Access.revoke_key("revoked")

      keys = Access.list_keys()
      assert Enum.map(keys, & &1.name) == ["active", "revoked"]

      [listed_active, listed_revoked] = keys
      assert listed_active.id == active.id
      assert listed_active.scopes == ["read"]
      assert listed_active.revoked_at == nil
      assert listed_revoked.scopes == ["write"]
      assert %DateTime{} = listed_revoked.revoked_at

      shown = inspect(keys)
      refute shown =~ active_token
      refute shown =~ revoked_token
      refute shown =~ "token_hash"
    end
  end

  describe "Requirement: Revoke API keys" do
    test "Scenario: Revoked key no longer authenticates" do
      %{key: key, token: token} = api_key_fixture(%{name: "to-revoke"})
      assert {:ok, %ApiKey{id: id}} = Access.authenticate(token)
      assert id == key.id

      assert {:ok, %ApiKey{revoked_at: %DateTime{}}} = Access.revoke_key("to-revoke")
      assert Access.authenticate(token) == {:error, :unauthorized}
      assert [%ApiKey{name: "to-revoke"}] = Access.list_keys()
    end

    test "Scenario: Unknown key" do
      assert Access.revoke_key("does-not-exist") == {:error, :not_found}
    end

    test "revoking twice keeps the original revocation time" do
      api_key_fixture(%{name: "twice"})

      {:ok, %ApiKey{revoked_at: first}} = Access.revoke_key("twice")
      {:ok, %ApiKey{revoked_at: second}} = Access.revoke_key("twice")

      assert first == second
    end
  end

  describe "authenticate/1" do
    test "returns the key for its token" do
      %{key: key, token: token} = api_key_fixture()
      assert {:ok, %ApiKey{id: id}} = Access.authenticate(token)
      assert id == key.id
    end

    test "rejects unknown and malformed tokens" do
      api_key_fixture()

      unknown = "ck_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert Access.authenticate(unknown) == {:error, :unauthorized}
      assert Access.authenticate("") == {:error, :unauthorized}
      assert Access.authenticate("not-a-token") == {:error, :unauthorized}
      assert Access.authenticate(nil) == {:error, :unauthorized}
    end
  end

  describe "has_scope?/2" do
    test "checks scopes independently, as atoms or strings" do
      %{key: key} = api_key_fixture(%{scopes: ["write"]})

      assert Access.has_scope?(key, :write)
      assert Access.has_scope?(key, "write")
      refute Access.has_scope?(key, :read)
      refute Access.has_scope?(key, "read")
      refute Access.has_scope?(key, :ingest)
    end
  end

  describe "inspect/1" do
    test "does not show the token hash" do
      %{key: key} = api_key_fixture()

      shown = inspect(key)
      refute shown =~ "token_hash"
      refute shown =~ inspect(key.token_hash)
      assert shown =~ key.name
    end
  end
end
