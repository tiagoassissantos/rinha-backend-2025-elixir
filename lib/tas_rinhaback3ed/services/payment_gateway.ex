defmodule TasRinhaback3ed.Services.PaymentGateway do
  @moduledoc """
  Sends payment requests to the external gateway using Req.

  The base URL can be configured via
  `Application.get_env(:tas_rinhaback_3ed, :payments_base_url, "http://localhost:8001")`.
  """

  @default_base_url "http://payment-processor-default:8080"
  @fallback_base_url "http://payment-processor-fallback:8080"

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  alias OpenTelemetry.Span

  @spec send_payment(map(), keyword()) :: :ok | {:error, term()}
  def send_payment(params, opts \\ []) when is_map(params) do
    Tracer.with_span "payment_gateway.request", kind: :internal do
      # Attach request correlation attributes to this span for TraceQL search
      if rid = Logger.metadata()[:request_id] do
        ctx = Tracer.current_span_ctx()
        Span.set_attribute(ctx, :request_id, rid)
      end

      # Use string keys for custom attributes; avoid :'ns.key' atoms to prevent :ns.key/0 parsing
      Span.set_attribute(Tracer.current_span_ctx(), "tas.route", "default")

      params = Map.put(params, "requestedAt", DateTime.utc_now() |> DateTime.to_iso8601())

      url = mount_base_url(@default_base_url, opts)
      route = "default"

      case make_request(url, params, route) do
        {:ok, resp} ->
          # Logger.info("Payment gateway response: #{inspect(resp)}")
          if resp.status == 500 do
            new_route = "fallback"

            Logger.error(
              "#{route} gateway error #{resp.status}. Response body: #{inspect(resp.body)} Trying #{new_route}..."
            )

            Span.add_event(Tracer.current_span_ctx(), "gateway_error", %{
              status: resp.status,
              route: route
            })

            new_url = mount_base_url(@fallback_base_url, opts)
            resp = make_request(new_url, params, new_route)
            # Logger.info("Fallback response: #{inspect(resp)}")
          else
            # Logger.info("Payment request succeeded.")
            TasRinhaback3ed.Services.Transactions.store_success(params, route)
          end

          :ok

        {:error, error} ->
          new_route = "fallback"

          Logger.error("#{route} gateway error #{inspect(error)}. Trying #{new_route}...")

          Span.add_event(Tracer.current_span_ctx(), "gateway_error", %{
            error: inspect(error),
            route: route
          })

          fallback_url = mount_base_url(@fallback_base_url, opts)
          make_request(fallback_url, params, new_route)
          {:error, error}
      end
    end
  end

  defp make_request(url, params, route) do
    try do
      headers = [{"Content-Type", "application/json"}]
      # Optional debug timeouts to help reproduce failures locally
      base_opts = [json: params, headers: headers]

      opts =
        if Application.get_env(:tas_rinhaback_3ed, :payments_debug, false) do
          Keyword.merge(base_opts, receive_timeout: 2_000, connect_options: [timeout: 1_000])
        else
          base_opts
        end

      # Give client spans a readable, searchable name
      req_opts =
        Keyword.merge(
          [
            method: :post,
            url: url,
            span_name: "POST /payments (#{route})",
            # Ensure URL template attribute is set and span name is searchable
            path_params_style: :colon,
            path_params: [resource: "payments"]
          ],
          opts
        )

      TasRinhaback3ed.HTTP.request(req_opts)
    rescue
      # Convert unexpected raises to {:error, e} so callers can handle uniformly
      e ->
        Logger.error("Unexpected exception during request: #{inspect(e)}")
        Span.add_event(Tracer.current_span_ctx(), "exception", %{error: inspect(e)})
        {:error, e}
    catch
      :exit, reason ->
        Logger.error("EXIT during request: #{inspect(reason)}")
        Span.add_event(Tracer.current_span_ctx(), "exit", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  defp mount_base_url(base_url, opts) do
    Keyword.get(
      opts,
      :base_url,
      Application.get_env(:tas_rinhaback_3ed, :payments_base_url, base_url)
    ) <> "/payments"
  end

  defp define_route(route) do
    case route do
      "default" -> "fallback"
      "fallback" -> "default"
      _ -> "default"
    end
  end
end
