defmodule TasRinhaback3ed.Services.PaymentWorker do
  @moduledoc """
  Supervises task-based workers that drain `PaymentQueue` and forward each
  payload to the external payment gateway via `PaymentGateway.send_payment/2`.
  """

  use GenServer
  require Logger

  alias TasRinhaback3ed.Services.PaymentGateway
  alias TasRinhaback3ed.Services.PaymentQueue

  @sleep_ms 300

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    max_concurrency = resolve_max_concurrency(opts)
    state = %{max_concurrency: max_concurrency, worker_tasks: MapSet.new()}
    {:ok, start_workers(state)}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    worker_tasks = MapSet.delete(state.worker_tasks, ref)
    PaymentQueue.worker_finished()
    log_result(result)

    new_state =
      state
      |> Map.put(:worker_tasks, worker_tasks)
      |> start_workers()

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    if MapSet.member?(state.worker_tasks, ref) do
      worker_tasks = MapSet.delete(state.worker_tasks, ref)
      PaymentQueue.worker_finished()
      Logger.error("Payment worker crashed: #{inspect(reason)}")

      new_state =
        state
        |> Map.put(:worker_tasks, worker_tasks)
        |> start_workers()

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  defp start_workers(state) do
    current_workers = MapSet.size(state.worker_tasks)
    needed = max(state.max_concurrency - current_workers, 0)

    cond do
      needed <= 0 ->
        state

      true ->
        new_refs =
          1..needed
          |> Enum.map(fn _ -> start_worker() end)
          |> Enum.into(MapSet.new())

        %{state | worker_tasks: MapSet.union(state.worker_tasks, new_refs)}
    end
  end

  defp start_worker do
    task =
      Task.Supervisor.async_nolink(TasRinhaback3ed.PaymentTaskSup, fn ->
        PaymentQueue.worker_started()
        worker_loop()
      end)

    task.ref
  end

  defp worker_loop do
    case PaymentQueue.dequeue() do
      {:ok, payload, wait_ms} ->
        process_payload(payload, wait_ms)
        worker_loop()

      :empty ->
        Process.sleep(@sleep_ms)
        worker_loop()
    end
  rescue
    exception ->
      Logger.error("Payment worker loop error: #{inspect(exception)}")
      worker_loop()
  end

  defp process_payload(payload, wait_ms) do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        PaymentGateway.send_payment(payload)
      rescue
        exception ->
          Logger.error("Payment worker exception: #{inspect(exception)}")
          {:error, exception}
      catch
        :exit, reason ->
          Logger.error("Payment worker exit: #{inspect(reason)}")
          {:error, reason}
      end

    end_time = System.monotonic_time(:millisecond)
    elapsed_time = end_time - start_time

    Logger.debug(
      ";#{inspect(Map.get(payload, "correlationId"))}; Payment processed in; #{elapsed_time}"
    )

    case result do
      :ok ->
        :ok

      {:error, {:fallback_failed, details}} ->
        Logger.error(
          "  ;#{inspect(Map.get(payload, "correlationId"))}; Fallback gateway failed after; #{wait_ms}; #{inspect(details)}. Re-enqueueing payload."
        )

        requeue_payload(payload)
        Process.sleep(@sleep_ms)

      {:error, :gateways_unavailable} ->
        Logger.error(
          "  ;#{inspect(Map.get(payload, "correlationId"))}; No healthy payment processor routes available after; #{wait_ms}. Re-enqueueing payload."
        )

        requeue_payload(payload)
        Process.sleep(@sleep_ms)

      {:error, reason} ->
        Logger.error(
          "  ;#{inspect(Map.get(payload, "correlationId"))}; Payment processed with error after; #{wait_ms}; #{inspect(reason)}"
        )

      other ->
        Logger.debug("Payment gateway returned unexpected value: #{inspect(other)}")
    end
  end

  defp log_result(:ok), do: :ok

  defp log_result({:error, reason}) do
    Logger.error("Payment worker error: #{inspect(reason)}")
  end

  defp log_result(other) do
    Logger.warning("Payment worker result: #{inspect(other)}")
  end

  defp resolve_max_concurrency(opts) do
    config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])
    default = Keyword.get(config, :max_concurrency, System.schedulers_online() * 2)
    Keyword.get(opts, :max_concurrency, default)
  end

  defp requeue_payload(payload) do
    Logger.debug(
      ";#{inspect(Map.get(payload, "correlationId"))}; Queue stats before: #{inspect(PaymentQueue.stats())}"
    )

    case PaymentQueue.enqueue(payload) do
      :ok ->
        Logger.debug(
          ";#{inspect(Map.get(payload, "correlationId"))}; Queue stats after : #{inspect(PaymentQueue.stats())}"
        )

        :ok

      {:error, :queue_full} ->
        Logger.error(
          "  ;#{inspect(Map.get(payload, "correlationId"))}; Unable to re-enqueue payload: payment queue is full"
        )

      _ ->
        Logger.error(
          "  ;#{inspect(Map.get(payload, "correlationId"))}; Unable to re-enqueue payload: unknown error"
        )
    end
  end
end
