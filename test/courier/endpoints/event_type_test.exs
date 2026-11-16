defmodule Courier.Endpoints.EventTypeTest do
  use ExUnit.Case, async: true

  alias Courier.Endpoints.EventFilter

  describe "Requirement: Validate events" do
    test "valid event types are dot-separated lowercase segments" do
      for type <- ["payment.succeeded", "payment.card.declined", "refund_v2.failed", "ping", "a1"] do
        assert EventFilter.valid_type?(type), "expected #{inspect(type)} to be valid"
      end
    end

    test "invalid event types are rejected" do
      invalid = [
        "Payment Succeeded",
        "Payment.Succeeded",
        "payment.*",
        "*",
        "payment..succeeded",
        ".payment",
        "payment.",
        "payment-succeeded",
        "payment succeeded",
        "",
        nil,
        42,
        ["payment.succeeded"]
      ]

      for type <- invalid do
        refute EventFilter.valid_type?(type), "expected #{inspect(type)} to be invalid"
      end
    end
  end
end
