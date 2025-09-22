defmodule TasRinhaback3ed.Services.PaymentGatewayTest do
  use ExUnit.Case, async: true

  alias TasRinhaback3ed.Services.PaymentGateway

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    original_base = Application.get_env(:tas_rinhaback_3ed, :payments_base_url)

    Application.put_env(:tas_rinhaback_3ed, :payments_base_url, base_url)

    on_exit(fn ->
      if original_base do
        Application.put_env(:tas_rinhaback_3ed, :payments_base_url, original_base)
      else
        Application.delete_env(:tas_rinhaback_3ed, :payments_base_url)
      end
    end)

    if Process.whereis(TasRinhaback3ed.Finch) == nil do
      start_supervised!({Finch, name: TasRinhaback3ed.Finch})
    end

    {:ok, bypass: bypass}
  end

  test "returns error when fallback request fails", %{bypass: bypass} do
    test_pid = self()

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
end
