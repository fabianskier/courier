defmodule CourierDemo.SeedExamplesTest do
  use Courier.DataCase, async: true

  alias CourierDemo.Seeds

  @receiver_url "https://receiver.public.test"

  defp seed do
    Req.Test.stub(Seeds, &Plug.Conn.send_resp(&1, 204, ""))
    {:ok, summary} = Seeds.run(receiver_url: @receiver_url)
    summary
  end

  defp fast_merchant_id(summary) do
    Enum.find(summary.merchants, &(&1.name == "Sunrise Bakery")).id
  end

  # The lines of the "Try it" block, which ends the output.
  defp examples(output) do
    assert [_, block] = String.split(output, "\nTry it:\n")
    String.split(block, "\n", trim: true)
  end

  describe "Requirement: Ready-to-run demo examples" do
    test "Scenario: Examples after seeding" do
      summary = seed()
      token = summary.token
      fast = fast_merchant_id(summary)

      for commands <- [:mix, :release] do
        output = Seeds.report({:ok, summary}, commands)
        examples = examples(output)

        assert "  http://localhost:4000" in examples

        assert Enum.any?(
                 examples,
                 &(&1 =~ ~r/(mix courier\.load|bin\/load) / and
                     &1 =~ "--token #{token}" and &1 =~ "--merchant #{fast}")
               )

        assert Enum.any?(
                 examples,
                 &(String.starts_with?(&1, "  curl ") and
                     &1 =~ ~s("Authorization: Bearer #{token}") and
                     &1 =~ "http://localhost:4000/api/v1/deliveries?status=failed")
               )

        assert List.last(examples) ==
                 ~s(  claude mcp add --transport http courier http://localhost:4000/mcp --header "Authorization: Bearer #{token}")

        refute output =~ "whsec_"
      end
    end

    test "Scenario: Release examples" do
      summary = seed()
      output = Seeds.report({:ok, summary}, :release)
      examples = examples(output)

      assert Enum.any?(
               examples,
               &String.starts_with?(&1, "  docker compose exec courier bin/load --token ")
             )

      assert "  docker compose logs -f demo-receiver" in examples
      refute output =~ "mix "
      refute output =~ "whsec_"
    end

    test "Scenario: Mix examples" do
      summary = seed()
      output = Seeds.report({:ok, summary}, :mix)
      examples = examples(output)

      assert Enum.any?(examples, &String.starts_with?(&1, "  mix courier.load --token "))
      refute output =~ "docker"
      refute output =~ "whsec_"
    end
  end
end
