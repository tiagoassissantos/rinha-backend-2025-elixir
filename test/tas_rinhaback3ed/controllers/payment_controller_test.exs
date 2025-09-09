defmodule TasRinhaback3ed.Controllers.PaymentControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias TasRinhaback3ed.Router

  @opts Router.init([])

  describe "POST /payments" do
    test "forwards JSON to external gateway and returns 200" do
      bypass = Bypass.open()
      base_url = "http://localhost:#{bypass.port}"

      original_base = Application.get_env(:tas_rinhaback_3ed, :payments_base_url)
      Application.put_env(:tas_rinhaback_3ed, :payments_base_url, base_url)
      on_exit(fn ->
        if original_base, do: Application.put_env(:tas_rinhaback_3ed, :payments_base_url, original_base), else: Application.delete_env(:tas_rinhaback_3ed, :payments_base_url)
      end)

      payload = %{"correlationId" => "4a7901b8-7d26-4d9d-aa19-4dc1c7cf60b3", "amount" => 19.90}

      Bypass.expect(bypass, "POST", "/payments", fn conn ->
        {:ok, body, conn} = read_body(conn)
        assert get_req_header(conn, "content-type") |> Enum.at(0) =~ "application/json"
        assert Jason.decode!(body) == payload
        resp(conn, 202, ~s({"ok":true}))
      end)

      conn =
        :post
        |> conn("/payments", Jason.encode!(payload))
        |> put_req_header("content-type", "application/json")

      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "payment_received"
      assert body["received_params"] == payload
    end

    test "returns 400 for missing/invalid fields" do
      payload = %{"amount" => "not-a-decimal"}

      conn =
        :post
        |> conn("/payments", Jason.encode!(payload))
        |> put_req_header("content-type", "application/json")

      conn = Router.call(conn, @opts)

      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "invalid_request"
      assert is_list(body["errors"]) and length(body["errors"]) >= 1
    end
  end
end
