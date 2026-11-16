defmodule Courier.Delivery.RetryPolicyTest do
  use ExUnit.Case, async: true

  alias Courier.Delivery.RetryPolicy

  @now ~U[2026-01-01 12:00:00Z]

  defp largest(k), do: k
  defp smallest(_k), do: 1

  describe "Requirement: Successful delivery" do
    test "2xx is a success" do
      assert RetryPolicy.classify({:ok, %{status: 200}}, false) == :success
      assert RetryPolicy.classify({:ok, %{status: 204}}, false) == :success
      assert RetryPolicy.classify({:ok, %{status: 204}}, true) == :success
    end
  end

  describe "Requirement: Retryable failures are retried" do
    test "network errors, 408, 429 and 5xx are retried" do
      for retry_on_4xx <- [false, true] do
        assert RetryPolicy.classify({:error, "timeout"}, retry_on_4xx) == :retry
        assert RetryPolicy.classify({:ok, %{status: 408}}, retry_on_4xx) == :retry
        assert RetryPolicy.classify({:ok, %{status: 429}}, retry_on_4xx) == :retry
        assert RetryPolicy.classify({:ok, %{status: 500}}, retry_on_4xx) == :retry
        assert RetryPolicy.classify({:ok, %{status: 503}}, retry_on_4xx) == :retry
      end
    end

    test "other 4xx are retried when retry_on_4xx is set" do
      assert RetryPolicy.classify({:ok, %{status: 400}}, true) == :retry
      assert RetryPolicy.classify({:ok, %{status: 404}}, true) == :retry
    end
  end

  describe "Requirement: Non-retryable failures end the delivery" do
    test "3xx gives up" do
      assert RetryPolicy.classify({:ok, %{status: 302}}, false) == :give_up
      assert RetryPolicy.classify({:ok, %{status: 302}}, true) == :give_up
    end

    test "other 4xx give up without retry_on_4xx" do
      assert RetryPolicy.classify({:ok, %{status: 400}}, false) == :give_up
      assert RetryPolicy.classify({:ok, %{status: 404}}, false) == :give_up
    end
  end

  describe "Requirement: Backoff with jitter and Retry-After" do
    test "Scenario: Delay grows and is capped" do
      assert RetryPolicy.delay(1, nil, &largest/1) == 11
      assert RetryPolicy.delay(2, nil, &largest/1) == 21
      assert RetryPolicy.delay(20, nil, &largest/1) == 3601
    end

    test "the smallest delay is 1 second" do
      assert RetryPolicy.delay(1, nil, &smallest/1) == 1
      assert RetryPolicy.delay(20, nil, &smallest/1) == 1
    end

    test "the random range covers 0 to the capped backoff" do
      parent = self()

      RetryPolicy.delay(3, nil, fn k ->
        send(parent, {:k, k})
        1
      end)

      assert_received {:k, 41}
    end

    test "the default random function stays within bounds" do
      for _ <- 1..50 do
        assert RetryPolicy.delay(2, nil) in 1..21
      end
    end

    test "Retry-After is honoured when it asks for longer" do
      assert RetryPolicy.delay(1, 120, &largest/1) == 120
      assert RetryPolicy.delay(2, 5, &largest/1) == 21
    end

    test "Retry-After is capped at 3600 seconds" do
      assert RetryPolicy.delay(1, 86_400, &largest/1) == 3600
    end

    test "Retry-After as seconds" do
      assert RetryPolicy.parse_retry_after("120", @now) == 120
      assert RetryPolicy.parse_retry_after(" 0 ", @now) == 0
    end

    test "Retry-After as an HTTP date" do
      assert RetryPolicy.parse_retry_after("Thu, 01 Jan 2026 12:02:00 GMT", @now) == 120
      assert RetryPolicy.parse_retry_after("Wed, 31 Dec 2025 12:00:00 GMT", @now) == 0
    end

    test "invalid Retry-After is ignored" do
      for value <- [nil, "", "soon", "-5", "1.5", "120s", "Thu, 32 Jan 2026 12:00:00 GMT"] do
        assert RetryPolicy.parse_retry_after(value, @now) == nil
      end
    end

    test "Retry-After parsed then capped" do
      seconds = RetryPolicy.parse_retry_after("86400", @now)
      assert RetryPolicy.delay(1, seconds, &largest/1) == 3600
    end
  end

  describe "Requirement: Retry window ends retries" do
    test "next/3 before the window end schedules a retry" do
      window_ends_at = DateTime.add(@now, 60, :second)

      assert RetryPolicy.next(@now, 59, window_ends_at) ==
               {:retry_at, DateTime.add(@now, 59, :second)}
    end

    test "next/3 at or after the window end reports the window ended" do
      window_ends_at = DateTime.add(@now, 60, :second)

      assert RetryPolicy.next(@now, 60, window_ends_at) == :window_ended
      assert RetryPolicy.next(@now, 61, window_ends_at) == :window_ended
    end
  end
end
