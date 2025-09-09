defmodule TasRinhaback3ed.HealthController do
  alias TasRinhaback3ed.JSON

  @spec index(Plug.Conn.t()) :: Plug.Conn.t()
  def index(conn) do
    JSON.send_json(conn, 200, %{status: "ok"})
  end
end
