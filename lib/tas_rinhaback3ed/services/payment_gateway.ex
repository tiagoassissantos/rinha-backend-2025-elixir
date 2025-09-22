defmodule TasRinhaback3ed.Services.PaymentGateway do
  @moduledoc """
  Sends payment requests to the external gateway using Req.

  The base URL can be configured via
  `Application.get_env(:tas_rinhaback_3ed, :payments_base_url, "http://localhost:8001")`.
  """

  @default_base_url "http://payment-processor-default:8080"
  @fallback_base_url "http://payment-processor-fallback:8080"

  require Logger

  alias TasRinhaback3ed.Services.Transactions

  @spec send_payment(map(), keyword()) :: :ok | {:error, term()}
  def send_payment(params, opts \\ []) when is_map(params) do
    params = Map.put(params, "requestedAt", DateTime.utc_now() |> DateTime.to_iso8601())

    default_url = mount_base_url(@default_base_url, opts)
    fallback_url = mount_base_url(@fallback_base_url, opts)

    case request_with_route(default_url, params, "default") do
      :ok ->
        :ok

      {:retry, default_failure} ->
        Logger.error(
          "default gateway failure: #{describe_failure(default_failure)}. Trying fallback..."
        )

        case request_with_route(fallback_url, params, "fallback") do
          :ok ->
            :ok

          {:retry, fallback_failure} ->
            Logger.error("fallback gateway failure: #{describe_failure(fallback_failure)}")

            {:error, {:fallback_failed, %{default: default_failure, fallback: fallback_failure}}}
        end
    end
  end

  defp request_with_route(url, params, route) do
    case make_request(url, params) do
      {:ok, %Req.Response{} = resp} ->
        if success_status?(resp.status) do
          Transactions.store_success(params, route)
          :ok
        else
          {:retry,
           %{route: route, kind: :unexpected_status, status: resp.status, body: resp.body}}
        end

      {:error, reason} ->
        {:retry, %{route: route, kind: :request_error, error: reason}}
    end
  end

  defp describe_failure(%{route: route, kind: :unexpected_status, status: status, body: body}) do
    "#{route} responded with status #{status}, body: #{inspect(body)}"
  end

  defp describe_failure(%{route: route, kind: :request_error, error: error}) do
    "#{route} request error: #{inspect(error)}"
  end

  defp success_status?(status) when is_integer(status), do: status in 200..299

  defp success_status?(_), do: false

  defp make_request(url, params) do
    try do
      headers = [{"Content-Type", "application/json"}]
      base_opts = [json: params, headers: headers]

      opts =
        if Application.get_env(:tas_rinhaback_3ed, :payments_debug, false) do
          Keyword.merge(base_opts, receive_timeout: 2_000, connect_options: [timeout: 1_000])
        else
          base_opts
        end

      req_opts = Keyword.merge([method: :post, url: url], opts)

      TasRinhaback3ed.HTTP.request(req_opts)
    rescue
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
