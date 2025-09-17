defmodule TasRinhaback3ed.Plugs.TraceRequestId do
  @moduledoc """
  Adds the current `request_id` as an OpenTelemetry span attribute so
  you can search for it in Grafana Tempo with TraceQL.

  Looks up the value from the Logger metadata set by `Plug.RequestId`
  and, as a fallback, from the incoming `x-request-id` header.
  """

  import Plug.Conn
  require Logger

  alias OpenTelemetry.{Span, Tracer}

  def init(opts), do: opts

  def call(conn, _opts) do
    req_id =
      Logger.metadata()[:request_id] ||
        get_req_header(conn, "x-request-id") |> List.first()

    if req_id do
      ctx = Tracer.current_span_ctx()
      if ctx != :undefined do
        # Record under a simple and a namespaced key for convenience
        Span.set_attribute(ctx, :request_id, req_id)
      end
    end

    conn
  end
end
