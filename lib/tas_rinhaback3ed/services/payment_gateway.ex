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
    params = Map.put(params, "requestedAt", DateTime.utc_now() |> DateTime.to_iso8601())

    url = mount_base_url(@default_base_url, opts)
    route = "default"

    case make_request(url, params) do
      {:ok, resp} ->
        if resp.status == 500 do
          new_route = "fallback"

          Logger.error(
            "#{route} gateway error #{resp.status}. Response body: #{inspect(resp.body)} Trying #{new_route}..."
          )

          new_url = mount_base_url(@fallback_base_url, opts)
          _ = make_request(new_url, params)
        else
          TasRinhaback3ed.Services.Transactions.store_success(params, route)
        end

        :ok

      {:error, error} ->
        new_route = "fallback"

        Logger.error("#{route} gateway error #{inspect(error)}. Trying #{new_route}...")

        fallback_url = mount_base_url(@fallback_base_url, opts)
        _ = make_request(fallback_url, params)
        {:error, error}
    end
  end

  defp make_request(url, params) do
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
      req_opts = Keyword.merge([method: :post, url: url], opts)

      TasRinhaback3ed.HTTP.request(req_opts)
    rescue
      # Convert unexpected raises to {:error, e} so callers can handle uniformly
      e ->
        Logger.error("Unexpected exception during request: #{inspect(e)}")
        {:error, e}
    catch
      :exit, reason ->
        Logger.error("EXIT during request: #{inspect(reason)}")
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
end
