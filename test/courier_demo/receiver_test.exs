defmodule CourierDemo.ReceiverTest do
  # capture_debug_log/1 changes the global log level.
  use ExUnit.Case, async: false

  import CourierWeb.LogCapture

  @secret "whsec_" <> Base.encode64("demo-receiver-test-key-000000001")
  @other_secret "whsec_" <> Base.encode64("demo-receiver-test-key-000000002")
  @body ~s({"type":"payment.succeeded","payload":{"amount":1250}})

  setup context do
    opts =
      [
        port: 0,
        secrets: Module.concat(__MODULE__, "Secrets#{System.unique_integer([:positive])}")
      ] ++
        Map.get(context, :receiver, [])

    supervisor = start_supervised!({CourierDemo.Receiver, opts})

    {:server, server, _type, _modules} =
      supervisor |> Supervisor.which_children() |> List.keyfind(:server, 0)

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    %{req: Req.new(base_url: "http://127.0.0.1:#{port}", retry: false)}
  end

  # Standard Webhooks signature, computed here and not with courier's signer.
  defp sign(secret, id, timestamp, body) do
    "whsec_" <> encoded = secret
    key = Base.decode64!(encoded)
    "v1," <> Base.encode64(:crypto.mac(:hmac, :sha256, key, "#{id}.#{timestamp}.#{body}"))
  end

  defp now, do: System.system_time(:second)

  defp register(req, name, secret) do
    Req.put!(req, url: "/_secrets/#{name}", json: %{secret: secret})
  end

  defp post_hook(req, path, headers, body \\ @body) do
    Req.post!(req, url: path, headers: headers, body: body)
  end

  defp signed_headers(secret, opts \\ []) do
    id = Keyword.get(opts, :id, "msg_test")
    timestamp = Keyword.get(opts, :timestamp, now())

    [
      {"webhook-id", id},
      {"webhook-timestamp", to_string(timestamp)},
      {"webhook-signature", sign(secret, id, timestamp, @body)},
      {"courier-delivery-id", "dlv_test"}
    ]
  end

  describe "Requirement: Behaviour by path" do
    test "Scenario: Each behaviour answers as named", %{req: req} do
      register(req, "shop", @secret)
      headers = signed_headers(@secret)

      assert post_hook(req, "/hooks/shop/ok", headers).status == 200
      assert post_hook(req, "/hooks/shop/fail", headers).status == 500

      rate_limited = post_hook(req, "/hooks/shop/rate-limit", headers)
      assert rate_limited.status == 429
      assert Req.Response.get_header(rate_limited, "retry-after") == ["30"]

      assert post_hook(req, "/hooks/shop/bad-request", headers).status == 400
    end

    @tag receiver: [timeout_delay_ms: 200]
    test "Scenario: Timeout answers late", %{req: req} do
      started = System.monotonic_time(:millisecond)
      response = post_hook(req, "/hooks/shop/timeout", [])
      elapsed = System.monotonic_time(:millisecond) - started

      assert response.status == 200
      assert elapsed >= 200
    end

    test "Scenario: Unknown behaviour", %{req: req} do
      assert post_hook(req, "/hooks/shop/explode", []).status == 404
      assert Req.get!(req, url: "/hooks/shop/ok").status == 404
      assert Req.post!(req, url: "/elsewhere", body: @body).status == 404
    end
  end

  describe "Requirement: Secret registration" do
    test "Scenario: Secret registered", %{req: req} do
      assert register(req, "shop", @secret).status == 204

      assert post_hook(req, "/hooks/shop/ok", signed_headers(@secret)).status == 200
      assert post_hook(req, "/hooks/shop/ok", signed_headers(@other_secret)).status == 401
      assert post_hook(req, "/hooks/shop/ok", []).status == 401
    end

    test "Scenario: Invalid secret rejected", %{req: req} do
      register(req, "shop", @secret)

      assert register(req, "shop", "not-a-secret").status == 422
      assert register(req, "shop", "whsec_not base64!").status == 422
      assert Req.put!(req, url: "/_secrets/shop", body: "not json").status == 422

      assert post_hook(req, "/hooks/shop/ok", signed_headers(@secret)).status == 200
      assert post_hook(req, "/hooks/shop/ok", signed_headers(@other_secret)).status == 401
    end
  end

  describe "Requirement: Signature verification" do
    test "Scenario: Wrong signature rejected", %{req: req} do
      register(req, "shop", @secret)

      assert post_hook(req, "/hooks/shop/fail", signed_headers(@other_secret)).status == 401
    end

    test "Scenario: Stale timestamp rejected", %{req: req} do
      register(req, "shop", @secret)
      headers = signed_headers(@secret, timestamp: now() - 600)

      assert post_hook(req, "/hooks/shop/ok", headers).status == 401
    end

    test "Scenario: Rotation overlap accepted", %{req: req} do
      register(req, "shop", @secret)
      timestamp = now()

      signatures =
        sign(@other_secret, "msg_test", timestamp, @body) <>
          " " <> sign(@secret, "msg_test", timestamp, @body)

      headers = [
        {"webhook-id", "msg_test"},
        {"webhook-timestamp", to_string(timestamp)},
        {"webhook-signature", signatures}
      ]

      assert post_hook(req, "/hooks/shop/ok", headers).status == 200
    end
  end

  describe "Requirement: Unregistered names answered unchecked" do
    test "Scenario: Unchecked request", %{req: req} do
      register(req, "shop", @secret)

      {response, log} = capture_debug_log(fn -> post_hook(req, "/hooks/other/ok", []) end)

      assert response.status == 200
      assert log =~ "demo-receiver name=other behaviour=ok signature=unchecked"
    end
  end

  describe "Requirement: Receiver logging" do
    test "Scenario: Log without secrets", %{req: req} do
      headers = signed_headers(@secret, id: "msg_logged")
      {_name, "v1," <> signature} = List.keyfind(headers, "webhook-signature", 0)
      "whsec_" <> encoded_key = @secret

      {response, log} =
        capture_debug_log(fn ->
          register(req, "shop", @secret)
          post_hook(req, "/hooks/shop/ok", headers)
        end)

      assert response.status == 200

      assert log =~
               "demo-receiver name=shop behaviour=ok signature=valid " <>
                 "webhook-id=msg_logged courier-delivery-id=dlv_test"

      refute log =~ encoded_key
      refute log =~ signature
      refute log =~ @body
      refute log =~ "payment.succeeded"
    end
  end
end
