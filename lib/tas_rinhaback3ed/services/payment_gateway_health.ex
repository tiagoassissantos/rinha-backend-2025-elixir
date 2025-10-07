defmodule TasRinhaback3ed.Services.PaymentGatewayHealth do
  @moduledoc """
  Periodically polls the payment processor service-health endpoints and caches
  their status for the `PaymentGateway`.
  """

  use GenServer
  require Logger

  alias TasRinhaback3ed.HTTP

  @poll_interval 5_000
  @default_health_url "http://payment-processor-default:8080/payments/service-health"
  @fallback_health_url "http://payment-processor-fallback:8080/payments/service-health"
  @status_key {__MODULE__, :status}

  @type route :: :default | :fallback
  @type health_info :: %{
          failing: boolean(),
          min_response_time: non_neg_integer() | :infinity,
          checked_at: DateTime.t() | nil,
          source: :ok | :error
        }
  @type status_map :: %{default: health_info(), fallback: health_info()}

  @doc """
  Returns the cached health status for both payment processor routes.
  """
  @spec current_status() :: status_map()
  def current_status do
    :persistent_term.get(@status_key, default_status())
  end

  @doc """
  Returns `true` when the given health info meets the criteria established for routing.
  """
  @spec healthy?(health_info() | nil) :: boolean()
  def healthy?(%{failing: false, min_response_time: min}) when is_integer(min) and min < 30,
    do: true

  def healthy?(_), do: false

  @doc false
  @spec put_status(status_map()) :: :ok
  def put_status(status) when is_map(status) do
    :persistent_term.put(@status_key, status)
  end

  @doc false
  @spec put_status(health_info(), atom()) :: :ok
  def put_status(%{} = info, route) do
    current_status()
    |> Map.put(route, info)
    |> put_status()
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    :persistent_term.put(@status_key, default_status())

    state = %{
      default_url: Keyword.get(opts, :default_health_url, @default_health_url),
      fallback_url: Keyword.get(opts, :fallback_health_url, @fallback_health_url)
    }

    Process.send_after(self(), :poll, 0)

    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_status =
      current_status()
      |> update_route(:default, state.default_url)
      |> update_route(:fallback, state.fallback_url)

    :persistent_term.put(@status_key, new_status)
    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :persistent_term.erase(@status_key)
    :ok
  end

  defp update_route(status_map, route, url) do
    case fetch_health(url) do
      {:ok, info} ->
        Map.put(status_map, route, build_health(info, :ok))

      {:error, reason} ->
        Logger.warning("Payment gateway health check failed for #{route}: #{inspect(reason)}")

        Map.put(status_map, route, build_error_health(status_map[route]))
    end
  end

  defp fetch_health(url) do
    case HTTP.request(method: :get, url: url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        decode_body(body)

      {:ok, %Req.Response{status: 429} = resp} ->
        Logger.error("Error from #{url}: #{inspect(resp)}")
        {:error, {:rate_limited, resp.status}}

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Error from #{url}: #{inspect(status)}")
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.error("Error from #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    exception ->
      {:error, exception}
  catch
    :exit, reason ->
      {:error, reason}
  end

  defp decode_body(%{"failing" => failing, "minResponseTime" => min}) do
    with true <- is_boolean(failing),
         {:ok, min_value} <- normalize_min_response(min) do
      {:ok, %{failing: failing, min_response_time: min_value}}
    else
      _ -> {:error, :invalid_body}
    end
  end

  defp decode_body(body) when is_binary(body) do
    with {:ok, decoded} <- Jason.decode(body) do
      decode_body(decoded)
    end
  end

  defp decode_body(_), do: {:error, :invalid_body}

  defp normalize_min_response(value) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp normalize_min_response(value) when is_float(value) and value >= 0,
    do: {:ok, round(value)}

  defp normalize_min_response(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> {:error, :invalid_min_response_time}
    end
  end

  defp normalize_min_response(_), do: {:error, :invalid_min_response_time}

  defp build_health(%{failing: failing, min_response_time: min}, source) do
    %{
      failing: failing,
      min_response_time: min,
      checked_at: DateTime.utc_now(),
      source: source
    }
  end

  defp build_error_health(nil) do
    %{
      failing: true,
      min_response_time: :infinity,
      checked_at: DateTime.utc_now(),
      source: :error
    }
  end

  defp build_error_health(%{checked_at: last_checked} = previous) do
    previous
    |> Map.put(:failing, true)
    |> Map.put(:min_response_time, :infinity)
    |> Map.put(:checked_at, last_checked || DateTime.utc_now())
    |> Map.put(:source, :error)
  end

  defp default_status do
    now = DateTime.utc_now()

    base = %{
      failing: false,
      min_response_time: 0,
      checked_at: now,
      source: :ok
    }

    %{default: base, fallback: base}
  end
end
