defmodule TasRinhaback3ed.Services.PaymentGateway do
  @moduledoc """
  Sends payment requests to the external gateway using Req.

  The base URL can be configured via
  `Application.get_env(:tas_rinhaback_3ed, :payments_base_url, "http://localhost:8001")`.
  """

  @default_base_url "http://payment-processor-default:8080"
  @fallback_base_url "http://payment-processor-fallback:8080"

  require Logger

  alias TasRinhaback3ed.Services.{PaymentGatewayHealth, Transactions}

  @spec send_payment(map(), keyword()) :: :ok | {:error, term()}
  def send_payment(params, opts \\ []) when is_map(params) do
    start_time = System.monotonic_time(:millisecond)

    params = Map.put(params, "requestedAt", DateTime.utc_now() |> DateTime.to_iso8601())

    default_url = mount_base_url(@default_base_url, opts, :default_base_url)
    fallback_url = mount_base_url(@fallback_base_url, opts, :fallback_base_url)

    status = PaymentGatewayHealth.current_status()
    default_healthy? = PaymentGatewayHealth.healthy?(status[:default])
    fallback_healthy? = PaymentGatewayHealth.healthy?(status[:fallback])

    result =
      cond do
        default_healthy? ->
          handle_default_route(params, default_url, fallback_url, fallback_healthy?)

        fallback_healthy? ->
          Logger.debug("default gateway skipped due to health check; using fallback")
          handle_fallback_only(params, fallback_url)

        true ->
          Logger.warning(
            " ;#{inspect(Map.get(params, "correlationId"))}; No healthy payment processor routes available; payload will be re-queued"
          )

          {:error, :gateways_unavailable}
      end

    case result do
      :ok ->
        end_time = System.monotonic_time(:millisecond)
        elapsed_time = end_time - start_time
        Logger.info(";#{inspect(Map.get(params, "correlationId"))}; Payment Gateway send_payment processed in #{elapsed_time}")
        :ok

      other ->
        other
    end
  end

  defp handle_default_route(params, default_url, fallback_url, fallback_healthy?) do
    case request_with_route(default_url, params, :default) do
      :ok ->
        :ok

      {:retry, default_failure} ->
        Logger.info(";#{inspect(Map.get(params, "correlationId"))}; default gateway failure: #{describe_failure(default_failure)}")

        if fallback_healthy? do
          Logger.info(";#{inspect(Map.get(params, "correlationId"))}; Trying fallback gateway after default failure")

          case request_with_route(fallback_url, params, :fallback) do
            :ok ->
              :ok

            {:retry, fallback_failure} ->
              Logger.error(";#{inspect(Map.get(params, "correlationId"))}; fallback gateway failure: #{describe_failure(fallback_failure)}")
              {:error,
               {:fallback_failed, %{default: default_failure, fallback: fallback_failure}}}
          end
        else
          {:error, :gateways_unavailable}
        end
    end
  end

  defp handle_fallback_only(params, fallback_url) do
    case request_with_route(fallback_url, params, :fallback) do
      :ok ->
        :ok

      {:retry, fallback_failure} ->
        Logger.error("Error from fallback gateway: #{describe_failure(fallback_failure)}")
        {:error, {:fallback_failed, %{fallback: fallback_failure}}}
    end
  end

  defp request_with_route(url, params, route) do
    request_with_route_start_time = System.monotonic_time(:millisecond)
    case make_request(url, params, route) do
      {:ok, %Req.Response{} = resp} ->
        Logger.debug("Payment response: #{inspect(resp)}")

        if success_status?(resp.status) do
          Logger.debug("#{route} gateway succeeded with status #{resp.status}")
          start_time = System.monotonic_time(:millisecond)
          Transactions.store_success(params, route)
          end_time = System.monotonic_time(:millisecond)
          elapsed_time = end_time - start_time

          Logger.info(
            ";#{inspect(Map.get(params, "correlationId"))}; Payment Gateway store_success processed in; #{elapsed_time}"
          )

          :ok
        else
          Logger.error(";#{inspect(Map.get(params, "correlationId"))}; Unexpected status #{resp.status} from #{route} gateway")
          end_time = System.monotonic_time(:millisecond)
          elapsed_time = end_time - request_with_route_start_time
          update_processor_health(elapsed_time, params, route)
          {:retry,
           %{route: route, kind: :unexpected_status, status: resp.status, body: resp.body}}
        end

      {:error, reason} ->
         Logger.error("Request error from #{route} gateway: #{inspect(reason)}")
        {:retry, %{route: route, kind: :request_error, error: reason}}
    end
  end

  defp describe_failure(%{route: route, kind: :unexpected_status, status: status, body: body}) do
    "#{route} responded with status #{status}, body: #{inspect(body)}"
  end

  defp describe_failure(%{route: route, kind: :request_error, error: error}) do
    "#{route} request error: #{inspect(error)}"
  end

  defp success_status?(status) when is_integer(status), do: status in 200..299 or status == 409

  defp success_status?(_), do: false

  defp make_request(url, params, route) do
    try do
      start_time = System.monotonic_time(:millisecond)

      headers = [{"Content-Type", "application/json"}]
      base_opts = [json: params, headers: headers]

      opts =
        if Application.get_env(:tas_rinhaback_3ed, :payments_debug, false) do
          Keyword.merge(base_opts, connect_options: [timeout: 500])
        else
          base_opts
        end

      req_opts = Keyword.merge([method: :post, url: url], opts)
      Logger.debug("Payment request: #{inspect(req_opts)}")
      response = TasRinhaback3ed.HTTP.request(req_opts)

      end_time = System.monotonic_time(:millisecond)
      elapsed_time = end_time - start_time

      #update_processor_health(elapsed_time, params, route)

      Logger.info(
        ";#{inspect(Map.get(params, "correlationId"))}; Payment Gateway make_request processed in; #{elapsed_time}"
      )

      response
    rescue
      e ->
        # Logger.error("Unexpected exception during request: #{inspect(e)}")
        {:error, e}
    catch
      :exit, reason ->
        # Logger.error("EXIT during request: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_processor_health(elapsed_time, params, route) do
    status = PaymentGatewayHealth.current_status()
    if elapsed_time > 30 && status[route].min_response_time < elapsed_time do
      Logger.warning(";#{inspect(Map.get(params, "correlationId"))}; Elapsed time is too high; #{elapsed_time}")

      failing? = status[route].failing

      PaymentGatewayHealth.put_status(%{
        failing: failing?,
        min_response_time: elapsed_time,
        checked_at: DateTime.utc_now(),
        source: :ok
      }, route)
    end
  end

  defp mount_base_url(base_url, opts, specific_key) do
    override =
      case Keyword.get(opts, specific_key) do
        nil -> Keyword.get(opts, :base_url)
        value -> value
      end

    (override || Application.get_env(:tas_rinhaback_3ed, :payments_base_url, base_url)) <>
      "/payments"
  end
end
