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
    Logger.info("[#{uid}] - Sending payment request to gateway...")
    url = mount_base_url(@default_base_url, opts)

    with :ok <- make_request(url, params, "default", uid) do
      Logger.info("[#{uid}] - Payment request succeeded.")
      :ok
    else
      # only fallback on pool timeout / connection queue pressure
      {:error, :pool_timeout} ->
        Logger.error("[#{uid}] - Primary gateway timed out (pool pressure). Trying fallback...")
        fallback_url = mount_base_url(@fallback_base_url, opts)
        make_request(fallback_url, params, "fallback", uid)

      # anything else: bubble up
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_request(url, params, route, uid) do
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

      case Req.post(url, opts) do
        {:ok, _resp} ->
          Logger.info("[#{uid}] - Payment gateway request successful.")
          TasRinhaback3ed.Services.Transactions.store_success(params, route)
          :ok

        # Finch reports queue pressure timeouts like this:
        {:error, %Finch.Error{reason: :pool_timeout} = e} ->
          Logger.error("[#{uid}] - Payment gateway pool timeout at #{url}: #{inspect(e)}")
          {:error, :pool_timeout}

        # Other Finch errors (not eligible for fallback)
        {:error, %Finch.Error{reason: reason} = e} ->
          Logger.error("[#{uid}] - Finch.Error (#{inspect(reason)}): #{inspect(e)}")
          {:error, reason}

        # Mint transport layer
        {:error, %Mint.TransportError{reason: reason} = e} ->
          Logger.error("[#{uid}] - Mint.TransportError (#{inspect(reason)}): #{inspect(e)}")
          {:error, reason}

        # Any other exception struct
        {:error, %_{} = e} ->
          Logger.error("[#{uid}] - Exception struct: #{inspect(e)} | message: #{Exception.message(e)}")
          {:error, e}

        # Unknown error term
        {:error, other} ->
          Logger.error("[#{uid}] - Unknown error term: #{inspect(other)}")
          {:error, other}
      end
    rescue
      # Convert unexpected raises (like NimblePool.exit!/3) to {:error, ...}
      e ->
        Logger.error("[#{uid}] - Unexpected exception: " <> Exception.format(:error, e, __STACKTRACE__))
        if Exception.message(e) |> to_string() |> String.contains?("unable to provide a connection within the timeout") do
          {:error, :pool_timeout}
        else
          {:error, e}
        end
    catch
      :exit, reason ->
        # Some layers may exit instead of raising; log and map if it's pool pressure
        Logger.error("[#{uid}] - EXIT during request: #{inspect(reason)}")
        msg = to_string(reason)
        if String.contains?(msg, "unable to provide a connection within the timeout") do
          {:error, :pool_timeout}
        else
          {:error, reason}
        end
    end
  end

  defp mount_base_url(base_url, opts) do
    Keyword.get(
      opts,
      :base_url,
      Application.get_env(:tas_rinhaback_3ed, :payments_base_url, base_url)
    ) <> "/payments"
  end

  #defp print_request_headers(request) do
  #  if request.options[:print_headers] do
  #    print_headers("> ", request.headers)
  #  end

  #  request
  #end

  #defp print_headers(prefix, headers) do
  #  for {name, value} <- headers do
  #    Logger.info([prefix, name, ": ", value])
  #  end
  #end
end
