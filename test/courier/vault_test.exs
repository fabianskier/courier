defmodule Courier.VaultTest do
  use ExUnit.Case, async: true

  alias Courier.Encrypted.Binary
  alias Courier.Vault

  @plaintext "whsec_c2VjcmV0LXZhbHVlLWZvci10ZXN0aW5n"

  describe "Courier.Vault" do
    test "encrypts a value to different ciphertext and decrypts it back" do
      assert {:ok, ciphertext} = Vault.encrypt(@plaintext)
      assert ciphertext != @plaintext
      refute String.contains?(ciphertext, @plaintext)

      assert {:ok, other_ciphertext} = Vault.encrypt(@plaintext)
      assert other_ciphertext != ciphertext

      assert {:ok, @plaintext} = Vault.decrypt(ciphertext)
      assert {:ok, @plaintext} = Vault.decrypt(other_ciphertext)
    end
  end

  describe "Courier.Encrypted.Binary" do
    test "dumps to ciphertext and loads back the plaintext" do
      assert {:ok, dumped} = Binary.dump(@plaintext)
      assert dumped != @plaintext
      assert {:ok, @plaintext} = Binary.load(dumped)
    end
  end
end
