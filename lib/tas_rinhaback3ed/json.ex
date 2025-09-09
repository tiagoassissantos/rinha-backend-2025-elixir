defmodule TasRinhaback3ed.JSON do
  @moduledoc """
  Small helpers for JSON responses.
  """

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  def send_json(conn, status, data) when is_map(data) do
    body = Jason.encode!(data)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end
end
