defmodule TasRinhaback3ed.Services.PaymentGateway do
  @moduledoc """
  Sends payment requests to the external gateway using Req.

  The base URL can be configured via
  `Application.get_env(:tas_rinhaback_3ed, :payments_base_url, "http://localhost:8001")`.
  """

  @default_base_url "http://payment-processor-default:8080"
  @fallback_base_url "http://payment-processor-fallback:8080"

  require Logger

  @spec send_payment(map(), keyword()) :: :ok | {:error, term()}
  def send_payment(params, opts \\ []) when is_map(params) do
    uid = Integer.to_string(:erlang.unique_integer([:positive]))
    url = mount_base_url(@default_base_url, opts)

    case make_request(url, params, "default", uid) do
      {:ok, _resp} ->
        # Logger.info("[#{uid}] - Payment request succeeded.")
        :ok

      {:error, reason} ->
        Logger.error("[#{uid}] - Payment request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp make_request(url, params, route, uid) do
    try do
      # Add field requestedAt with current UTC timestamp in ISO 8601 format in params
      params = Map.put(params, "requestedAt", DateTime.utc_now() |> DateTime.to_iso8601())

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

      case TasRinhaback3ed.HTTP.request(req_opts) do
        {:ok, resp} ->
          # Logger.info("[#{uid}] - Response status: #{resp.status}")
          if resp.status == 500 do
            new_route = define_route(route)

            Logger.error(
              "[#{uid}] - #{route} gateway error #{resp.status}. Trying #{new_route}..."
            )

            new_url = mount_base_url(@fallback_base_url, opts)
            make_request(new_url, params, new_route, uid)
          else
            TasRinhaback3ed.Services.Transactions.store_success(params, route)
            # Update existing transaction (by correlation_id) with final route/amount
            # _ = TasRinhaback3ed.Services.Transactions.update_transaction(
            #  Map.get(params, "correlationId"),
            #  %{amount: Map.get(params, "amount"), route: route}
            # )
          end

          {:ok, resp}

        {:error, error} ->
          new_route = define_route(route)

          Logger.error(
            "[#{uid}] - #{route} gateway error #{inspect(error)}. Trying #{new_route}..."
          )

          fallback_url = mount_base_url(@fallback_base_url, opts)
          make_request(fallback_url, params, new_route, uid)
          :ok
      end
    rescue
      # Convert unexpected raises to {:error, e} so callers can handle uniformly
      e ->
        Logger.error("[#{uid}] - Unexpected exception during request: #{inspect(e)}")
        {:error, e}
    catch
      :exit, reason ->
        Logger.error("[#{uid}] - EXIT during request: #{inspect(reason)}")
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

  # defp print_request_headers(request) do
  #  if request.options[:print_headers] do
  #    print_headers("> ", request.headers)
  #  end

  #  request
  # end

  # defp print_headers(prefix, headers) do
  #  for {name, value} <- headers do
  #    Logger.info([prefix, name, ": ", value])
  #  end
  # end
end
