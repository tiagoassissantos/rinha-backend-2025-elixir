defmodule TasRinhaback3ed.Services.PaymentGatewayTest do
  use ExUnit.Case, async: true

  alias TasRinhaback3ed.Services.{PaymentGateway, PaymentGatewayHealth}

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    original_base = Application.get_env(:tas_rinhaback_3ed, :payments_base_url)

    Application.put_env(:tas_rinhaback_3ed, :payments_base_url, base_url)

    original_status = PaymentGatewayHealth.current_status()
    PaymentGatewayHealth.put_status(default_status())

    on_exit(fn ->
      if original_base do
        Application.put_env(:tas_rinhaback_3ed, :payments_base_url, original_base)
      else
        Application.delete_env(:tas_rinhaback_3ed, :payments_base_url)
      end

      PaymentGatewayHealth.put_status(original_status)
    end)

    if Process.whereis(TasRinhaback3ed.Finch) == nil do
      start_supervised!({Finch, name: TasRinhaback3ed.Finch})
    end

    {:ok, bypass: bypass}
  end

  test "returns error when fallback request fails", %{bypass: bypass} do
    test_pid = self()

    PaymentGatewayHealth.put_status(default_status())

    Bypass.stub(bypass, "POST", "/payments", fn conn ->
      send(test_pid, :gateway_called)
      Plug.Conn.resp(conn, 500, ~s({"error":"boom"}))
    end)

    payload = %{"correlationId" => "7a3d34e5-6e6d-4da8-9496-3f818d3f41ab", "amount" => 42.0}

    assert {:error, {:fallback_failed, %{default: default_failure, fallback: fallback_failure}}} =
             PaymentGateway.send_payment(payload)

    assert_receive :gateway_called, 1_000
    assert_receive :gateway_called, 1_000

    assert default_failure[:route] == "default"
    assert default_failure[:kind] in [:request_error, :unexpected_status]
    assert fallback_failure[:route] == "fallback"
    assert fallback_failure[:kind] in [:request_error, :unexpected_status]
  end

  test "skips default route when health indicates it is failing", %{bypass: bypass} do
    PaymentGatewayHealth.put_status(%{
      default: unhealthy_status(),
      fallback: healthy_status()
    })

    test_pid = self()

    Bypass.expect_once(bypass, "POST", "/payments", fn conn ->
      send(test_pid, :fallback_called)
      Plug.Conn.resp(conn, 204, "")
    end)

    payload = %{"correlationId" => "f522d3b9-6d4a-4f58-8b5d-150a029b4e29", "amount" => 10.0}

    assert :ok =
             PaymentGateway.send_payment(payload,
               fallback_base_url: "http://localhost:#{bypass.port}"
             )

    assert_received :fallback_called
  end

  test "returns gateways_unavailable when neither route is healthy" do
    PaymentGatewayHealth.put_status(%{
      default: unhealthy_status(),
      fallback: unhealthy_status()
    })

    payload = %{"correlationId" => "c5a9c493-05f3-4953-a4fa-8a2c94c74403", "amount" => 25.0}

    assert {:error, :gateways_unavailable} = PaymentGateway.send_payment(payload)
  end

  defp default_status do
    %{
      default: healthy_status(),
      fallback: healthy_status()
    }
  end

  defp healthy_status do
    %{
      failing: false,
      min_response_time: 10,
      checked_at: DateTime.utc_now(),
      source: :ok
    }
  end

  defp unhealthy_status do
    %{
      failing: true,
      min_response_time: :infinity,
      checked_at: DateTime.utc_now(),
      source: :error
    }
  end
end
