defmodule TasRinhaback3ed.Controllers.HealthController do
  alias TasRinhaback3ed.JSON
  alias TasRinhaback3ed.Services.PaymentQueue

  @spec index(Plug.Conn.t()) :: Plug.Conn.t()
  def index(conn) do
    queue_stats = PaymentQueue.stats()

    response = %{
      status: "ok",
      queue: queue_stats,
      memory: inspect(:erlang.memory()),
      system_info: inspect(:erlang.system_info(:wordsize))
    }

    JSON.send_json(conn, 200, response)
  end
end
