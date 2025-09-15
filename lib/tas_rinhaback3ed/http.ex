defmodule TasRinhaback3ed.HTTP do
  @moduledoc """
  Centralized Req client with OpenTelemetry instrumentation.

  - Attaches `OpentelemetryReq` to create client spans and propagate headers
  - Sets sane TLS defaults
  - Use `request/1` passing standard Req options (e.g. `method`, `url`, `json`)
  """

  defp base_client do
    Req.new()
    |> OpentelemetryReq.attach()
    |> Req.merge(connect_options: [transport_opts: [verify: :verify_peer]])
  end

  @spec request(Req.Request.t() | keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def request(%Req.Request{} = req), do: Req.request(req)
  def request(opts) when is_list(opts), do: base_client() |> Req.request(opts)
end
