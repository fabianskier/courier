defmodule Courier.Endpoints.EventFilterTest do
  use ExUnit.Case, async: true

  alias Courier.Endpoints.EventFilter

  describe "Requirement: Event-type filters" do
    test "Scenario: Exact and wildcard matching" do
      patterns = ["payment.*", "refund.failed"]

      assert EventFilter.matches?(patterns, "payment.succeeded")
      assert EventFilter.matches?(patterns, "payment.card.declined")
      assert EventFilter.matches?(patterns, "refund.failed")

      refute EventFilter.matches?(patterns, "refund.succeeded")
      refute EventFilter.matches?(patterns, "payments.created")
      # A wildcard needs at least one segment after its prefix.
      refute EventFilter.matches?(patterns, "payment")
      refute EventFilter.matches?(patterns, "refund.failed.late")
    end

    test "Scenario: Empty list matches everything" do
      assert EventFilter.matches?([], "payment.succeeded")
      assert EventFilter.matches?([], "refund.failed")
      assert EventFilter.matches?([], "anything_at_all")
    end

    test "Scenario: Invalid pattern rejected" do
      for pattern <- ["*", "Payment.Succeeded", "payment.*.failed", ""] do
        refute EventFilter.valid_pattern?(pattern), "expected #{inspect(pattern)} to be invalid"
      end

      for pattern <- [
            "payment*",
            ".payment",
            "payment.",
            "payment..failed",
            "pay-ment",
            " payment"
          ] do
        refute EventFilter.valid_pattern?(pattern), "expected #{inspect(pattern)} to be invalid"
      end

      refute EventFilter.valid_pattern?(nil)
      refute EventFilter.valid_pattern?(:payment)

      for pattern <- [
            "payment",
            "payment.succeeded",
            "payment.*",
            "payment.card.*",
            "v2_api.event_1"
          ] do
        assert EventFilter.valid_pattern?(pattern), "expected #{inspect(pattern)} to be valid"
      end
    end
  end
end
