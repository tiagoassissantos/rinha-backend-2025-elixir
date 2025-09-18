defmodule TasRinhaback3ed.HTTP do
  @moduledoc """
  Centralized Req client used by the application.

  - Reuses the shared Finch pool
  - Injects the current `x-request-id` if present
  - Use `request/1` passing standard Req options (e.g. `method`, `url`, `json`)
  """

  defp base_client do
    rid = Logger.metadata()[:request_id]

    Req.new(finch: TasRinhaback3ed.Finch)
    |> Req.merge(headers: if(rid, do: [{"x-request-id", rid}], else: []))
  end

  @spec request(Req.Request.t() | keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def request(%Req.Request{} = req), do: Req.request(req)
  def request(opts) when is_list(opts), do: base_client() |> Req.request(opts)
end
