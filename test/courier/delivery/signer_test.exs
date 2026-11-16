defmodule Courier.Delivery.SignerTest do
  use ExUnit.Case, async: true

  alias Courier.Delivery.Signer

  defp header(headers, name) do
    {^name, value} = List.keyfind(headers, name, 0)
    value
  end

  defp expected_signature("whsec_" <> encoded, id, timestamp, body) do
    :hmac
    |> :crypto.mac(:sha256, Base.decode64!(encoded), "#{id}.#{timestamp}.#{body}")
    |> Base.encode64()
  end

  defp new_secret, do: "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32))

  describe "Requirement: Signed webhook requests" do
    test "Scenario: Standard Webhooks test vector" do
      headers =
        Signer.headers(
          "msg_p5jXN8AQM9LWM0D4loKWxJek",
          1_614_265_330,
          ~s({"test": 2432232314}),
          ["whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"]
        )

      assert headers == [
               {"webhook-id", "msg_p5jXN8AQM9LWM0D4loKWxJek"},
               {"webhook-timestamp", "1614265330"},
               {"webhook-signature", "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE="}
             ]
    end

    test "during a rotation the header holds two signatures, each verifiable with its own secret" do
      current = new_secret()
      previous = new_secret()
      id = Ecto.UUID.generate()
      timestamp = 1_700_000_000
      body = ~s({"id":"#{id}","data":{"amount":42}})

      headers = Signer.headers(id, timestamp, body, [current, previous])

      assert ["v1," <> first, "v1," <> second] =
               headers |> header("webhook-signature") |> String.split(" ")

      assert first == expected_signature(current, id, timestamp, body)
      assert second == expected_signature(previous, id, timestamp, body)
      refute first == expected_signature(previous, id, timestamp, body)
      refute second == expected_signature(current, id, timestamp, body)
    end
  end
end
