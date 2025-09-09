defmodule TasRinhaback3ed.Router do
  use Plug.Router

  alias TasRinhaback3ed.{JSON, HealthController}
  alias TasRinhaback3ed.Controllers.PaymentController

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:json, :urlencoded, :multipart],
    pass: ["*/*"],
    json_decoder: Jason

  plug :match
  plug :dispatch

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
    JSON.send_json(conn, 404, %{error: "not_found"})
  end
end
