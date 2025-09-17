defmodule TasRinhaback3ed.HTTP do
  @moduledoc """
  Centralized Req client with OpenTelemetry instrumentation.

  - Attaches `OpentelemetryReq` to create client spans and propagate headers
  - Sets sane TLS defaults
  - Use `request/1` passing standard Req options (e.g. `method`, `url`, `json`)
  """

  defp base_client do
    rid = Logger.metadata()[:request_id]

    Req.new(finch: TasRinhaback3ed.Finch)
    # Inject x-request-id so OpentelemetryReq captures it as an attribute
    |> Req.merge(headers: (if rid, do: [{"x-request-id", rid}], else: []))
    |> OpentelemetryReq.attach(
      propagate_trace_headers: true,
      # Record templated path as attribute so it’s searchable (TraceQL)
      opt_in_attrs: [OpenTelemetry.SemConv.Incubating.URLAttributes.url_template()],
      # Capture common correlation headers when present
      request_header_attrs: ["x-request-id", "x-correlation-id"],
      response_header_attrs: ["x-request-id", "x-correlation-id"]
    )
  end

  @spec request(Req.Request.t() | keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def request(%Req.Request{} = req), do: Req.request(req)
  def request(opts) when is_list(opts), do: base_client() |> Req.request(opts)
end
