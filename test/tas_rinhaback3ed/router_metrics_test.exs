defmodule TasRinhaback3ed.RouterMetricsTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias TasRinhaback3ed.Router

  @opts Router.init([])

  setup do
    start_supervised!(TasRinhaback3ed.PromEx)
    :ok
  end

  test "GET /metrics exposes Prometheus metrics" do
    conn =
      :get
      |> conn("/metrics")

    conn = Router.call(conn, @opts)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert String.contains?(conn.resp_body, "# HELP")
  end
end
