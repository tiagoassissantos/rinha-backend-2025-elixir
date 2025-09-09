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
    url = mount_base_url(@default_base_url, opts)

    IO.puts("Sending payment to #{url} with params #{inspect(params)}")

    with :ok <- make_request(url, params) do
      :ok
    else
      # only fallback on pool timeout / connection queue pressure
      {:error, :pool_timeout} ->
        IO.puts("Primary gateway timed out (pool pressure). Trying fallback...")
        fallback_url = mount_base_url(@fallback_base_url, opts)
        make_request(fallback_url, params)

      # anything else: bubble up
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_request(url, params) do
    try do
      headers = [{"Content-Type", "application/json"}]
      #req =
        #Req.new()
        #|> Req.Request.register_options([:trace])
        #|> Req.Request.prepend_request_steps(print_headers: &print_request_headers/1)

      #case Req.post(req, url: url, json: params, headers: headers) do
      case Req.post(url, json: params, headers: headers) do
        {:ok, resp} ->
          IO.inspect(resp, label: "Payment gateway response")
          :ok

        # Finch reports queue pressure timeouts like this:
        {:error, %Finch.Error{reason: :pool_timeout} = e} ->
          Logger.warn("Payment gateway pool timeout at #{url}: #{inspect(e)}")
          {:error, :pool_timeout}

        # Other transport errors:
        {:error, %Mint.TransportError{} = e} ->
          IO.inspect(e, label: "Payment gateway transport error")
          {:error, e}

        {:error, %Mint.TransportError{reason: reason} = e} ->
          Logger.error("Transport error at #{url}: #{inspect(reason)} | full: #{inspect(e)}")
          {:error, reason}

        {:error, e} ->
          Logger.error("Unknown error: #{inspect(e)} | message: #{Exception.message(e)}")
          {:error, e}
      end
    rescue
      # Convert unexpected raises (like NimblePool.exit!/3 -> RuntimeError) to {:error, ...}
      e in RuntimeError ->
        IO.inspect(e, label: "Payment gateway unexpected error")
        if String.contains?(Exception.message(e), "unable to provide a connection within the timeout") do
          {:error, :pool_timeout}
        else
          {:error, e}
        end
    end
  end

  defp mount_base_url(base_url, opts \\ []) do
    Keyword.get(
      opts,
      :base_url,
      Application.get_env(:tas_rinhaback_3ed, :payments_base_url, base_url)
    ) <> "/payments"
  end

  defp print_request_headers(request) do
    if request.options[:print_headers] do
      print_headers("> ", request.headers)
    end

    request
  end

  defp print_headers(prefix, headers) do
    for {name, value} <- headers do
      Logger.info([prefix, name, ": ", value])
    end
  end
end
