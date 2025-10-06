defmodule TasRinhaback3ed.Controllers.PaymentControllerTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias TasRinhaback3ed.Router

  @opts Router.init([])

  setup do
    case :ets.whereis(:payment_work_queue) do
      :undefined -> :ok
      table -> :ets.delete_all_objects(table)
    end

    :ok
  end

  describe "POST /payments" do
    test "enqueues successfully and worker forwards JSON" do
      bypass = Bypass.open()
      base_url = "http://localhost:#{bypass.port}"

      original_base = Application.get_env(:tas_rinhaback_3ed, :payments_base_url)
      Application.put_env(:tas_rinhaback_3ed, :payments_base_url, base_url)

      on_exit(fn ->
        if original_base,
          do: Application.put_env(:tas_rinhaback_3ed, :payments_base_url, original_base),
          else: Application.delete_env(:tas_rinhaback_3ed, :payments_base_url)
      end)

      payload = %{"correlationId" => "4a7901b8-7d26-4d9d-aa19-4dc1c7cf60b3", "amount" => 19.90}

      test_pid = self()

      Bypass.expect(bypass, "POST", "/payments", fn conn ->
        {:ok, body, conn} = read_body(conn)
        assert get_req_header(conn, "content-type") |> Enum.at(0) =~ "application/json"
        decoded = Jason.decode!(body)
        assert decoded["correlationId"] == payload["correlationId"]
        assert decoded["amount"] == payload["amount"]
        send(test_pid, {:processor_called, decoded})
        resp(conn, 202, ~s({"ok":true}))
      end)

      conn =
        :post
        |> conn("/payments", Jason.encode!(payload))
        |> put_req_header("content-type", "application/json")

      conn = Router.call(conn, @opts)

      assert conn.status == 204
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
      assert conn.resp_body == ""
      assert_receive {:processor_called, received}, 1_000
      assert received["correlationId"] == payload["correlationId"]
    end

    test "accepts payloads even when fields are invalid" do
      payload = %{"amount" => "not-a-decimal"}

      conn =
        :post
        |> conn("/payments", Jason.encode!(payload))
        |> put_req_header("content-type", "application/json")

      conn = Router.call(conn, @opts)

      assert conn.status == 204
      assert conn.resp_body == ""
    end
  end

  describe "GET /payments-summary" do
    test "returns the expected summary JSON with from/to params" do
      qs = "from=2020-07-10T12:34:56.000Z&to=2020-07-10T12:35:56.000Z"

      conn =
        :get
        |> conn("/payments-summary?" <> qs)

      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      body = Jason.decode!(conn.resp_body)
      assert body["default"]["totalRequests"] == 0
      assert body["default"]["totalAmount"] == 0
      assert body["fallback"]["totalRequests"] == 0
      assert body["fallback"]["totalAmount"] == 0
    end

    test "returns 400 when from/to are missing" do
      conn =
        :get
        |> conn("/payments-summary")

      conn = Router.call(conn, @opts)
      assert conn.status == 400

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "invalid_request"
    end
  end
end
