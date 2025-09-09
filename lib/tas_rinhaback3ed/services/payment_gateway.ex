defmodule TasRinhaback3ed.Services.PaymentGateway do
  @moduledoc """
  Sends payment requests to the external gateway using Req.

  The base URL can be configured via
  `Application.get_env(:tas_rinhaback_3ed, :payments_base_url, "http://localhost:8001")`.
  """

  @default_base_url "http://localhost:8001"
  @fallback_base_url "http://localhost:8002"

  @spec send_payment(map(), keyword()) :: :ok | {:error, term()}
  def send_payment(params, opts \\ []) when is_map(params) do
    url = mount_base_url(@default_base_url, opts)

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
      case Req.post(url, json: params) do
        {:ok, _resp} ->
          :ok

        # Finch reports queue pressure timeouts like this:
        {:error, %Finch.Error{reason: :pool_timeout}} ->
          {:error, :pool_timeout}

        # Other transport errors:
        {:error, %Mint.TransportError{} = e} ->
          {:error, e}

        {:error, e} ->
          {:error, e}
      end
    rescue
      # Convert unexpected raises (like NimblePool.exit!/3 -> RuntimeError) to {:error, ...}
      e in RuntimeError ->
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
end
