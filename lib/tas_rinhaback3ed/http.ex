defmodule TasRinhaback3ed.HTTP do
  @moduledoc """
  Centralized Req client used by the application.

  - Reuses the shared Finch pool
  - Injects the current `x-request-id` if present
  - Use `request/1` passing standard Req options (e.g. `method`, `url`, `json`)
  """

  @default_request_opts [receive_timeout: 2_000, pool_timeout: 2_000]

  defp base_client do
    rid = Logger.metadata()[:request_id]

    Req.new(finch: TasRinhaback3ed.Finch)
    |> Req.merge(@default_request_opts)
    |> maybe_put_request_id(rid)
  end

  @spec request(Req.Request.t() | keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def request(%Req.Request{} = req) do
    req
    |> Req.merge(@default_request_opts)
    |> maybe_put_request_id(Logger.metadata()[:request_id])
    |> Req.request()
  end

  def request(opts) when is_list(opts), do: base_client() |> Req.request(opts)

  defp maybe_put_request_id(req, nil), do: req

  defp maybe_put_request_id(req, rid),
    do: Req.merge(req, headers: [{"x-request-id", rid}])
end
