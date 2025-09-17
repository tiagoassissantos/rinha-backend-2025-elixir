defmodule TasRinhaback3ed.Router do
  use Plug.Router

  alias TasRinhaback3ed.{JSON, HealthController}
  alias TasRinhaback3ed.Controllers.PaymentController

  plug(TasRinhaback3ed.Plugs.TraceRequestId)

  # Lightweight request timing events for telemetry
  plug(Plug.Telemetry, event_prefix: [:tas, :http])

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    length: 8_192,
    validate_utf8: false
  )

  plug(:match)
  plug(:dispatch)

  get "/health" do
    HealthController.index(conn)
  end

  post "/payments" do
    PaymentController.payments(conn, conn.params)
  end

  get "/payments-summary" do
    PaymentController.payments_summary(conn, conn.params)
  end

  match _ do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(404, Jason.encode_to_iodata!(%{error: "not_found"}))
  end
end
