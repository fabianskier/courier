defmodule Courier.Endpoints.RotationTest do
  use Courier.DataCase, async: true

  import Courier.EndpointsFixtures

  alias Courier.Endpoints

  @now ~U[2026-11-15 12:00:00.000000Z]
  @overlap_seconds 24 * 60 * 60

  describe "Requirement: Rotate signing secrets" do
    test "Scenario: Rotation with overlap" do
      {endpoint, old_secret} = endpoint_fixture()
      assert Endpoints.signing_secrets(endpoint, @now) == [old_secret]

      assert {:ok, rotated, new_secret} = Endpoints.rotate_secret(endpoint, @now)
      assert "whsec_" <> encoded = new_secret
      assert {:ok, <<_::binary-size(32)>>} = Base.decode64(encoded)
      refute new_secret == old_secret

      assert rotated.previous_secret_expires_at == DateTime.add(@now, @overlap_seconds, :second)
      assert Endpoints.signing_secrets(rotated, @now) == [new_secret, old_secret]

      assert {:ok, reloaded} = Endpoints.get_endpoint(endpoint.id)
      just_before_end = DateTime.add(@now, @overlap_seconds - 1, :second)
      assert Endpoints.signing_secrets(reloaded, just_before_end) == [new_secret, old_secret]
    end

    test "Scenario: Overlap ends" do
      {endpoint, _old_secret} = endpoint_fixture()
      {:ok, _rotated, new_secret} = Endpoints.rotate_secret(endpoint, @now)
      {:ok, reloaded} = Endpoints.get_endpoint(endpoint.id)

      for seconds <- [@overlap_seconds, @overlap_seconds + 1, 2 * @overlap_seconds] do
        later = DateTime.add(@now, seconds, :second)
        assert Endpoints.signing_secrets(reloaded, later) == [new_secret]
      end
    end

    test "a second rotation during the overlap replaces the previous secret" do
      {endpoint, first_secret} = endpoint_fixture()
      {:ok, _rotated, second_secret} = Endpoints.rotate_secret(endpoint, @now)

      later = DateTime.add(@now, 3600, :second)
      # Pass the stale struct: rotation must still keep the current secret.
      assert {:ok, _rotated, third_secret} = Endpoints.rotate_secret(endpoint, later)

      {:ok, reloaded} = Endpoints.get_endpoint(endpoint.id)
      assert Endpoints.signing_secrets(reloaded, later) == [third_secret, second_secret]
      refute first_secret in Endpoints.signing_secrets(reloaded, later)

      assert reloaded.previous_secret_expires_at ==
               DateTime.add(later, @overlap_seconds, :second)
    end

    test "rotating an endpoint that does not exist returns not found" do
      {endpoint, _secret} = endpoint_fixture()
      missing = %{endpoint | id: Ecto.UUID.generate()}

      assert Endpoints.rotate_secret(missing, @now) == {:error, :not_found}
    end
  end
end
