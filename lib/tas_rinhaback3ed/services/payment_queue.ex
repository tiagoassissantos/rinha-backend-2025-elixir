defmodule TasRinhaback3ed.Services.PaymentQueue do
  @moduledoc """
  High-performance, lock-free payment queue using ETS as MPSC queue.

  - HTTP processes write directly to ETS (no GenServer bottleneck)
  - Workers drain ETS concurrently using :ets.first/1 → :ets.take/2
  - Back-pressure via atomic counters (no mailbox pressure)
  - Bounded concurrency with Task.Supervisor

  Architecture:
  - ETS table: :ordered_set for FIFO processing
  - Key: {monotonic_time, unique_ref} for ordering
  - Value: {payload, enqueue_time, span_ctx}
  - Atomic counters: queue_size, in_flight workers

  Config:
    config :tas_rinhaback_3ed, :payment_queue,
      max_concurrency: System.schedulers_online() * 2,
      max_queue_size: :infinity
  """

  use GenServer
  require Logger

  alias TasRinhaback3ed.Services.PaymentGateway

  @type payload :: map()
  @type enqueue_result :: :ok | {:error, :queue_full}

  # ETS table name
  @table_name :payment_work_queue

  # Atomic counter names
  @queue_size_counter :payment_queue_size
  @in_flight_counter :payment_in_flight

  # Public API

  @doc """
  Start the payment queue supervisor and workers.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueue a payment payload directly to ETS (lock-free).
  Returns :ok immediately or {:error, :queue_full} if over capacity.
  """
  @spec enqueue(payload()) :: enqueue_result()
  def enqueue(payload) when is_map(payload) do
    # Check back-pressure before writing
    config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])
    max_queue_size = Keyword.get(config, :max_queue_size, :infinity)

    cond do
      max_queue_size != :infinity ->
        current_size = :atomics.get(:persistent_term.get(@queue_size_counter), 1)

        if current_size >= max_queue_size do
          :telemetry.execute([:tas, :queue, :drop], %{queue_len: current_size}, %{})
          {:error, :queue_full}
        else
          do_enqueue(payload)
        end

      true ->
        do_enqueue(payload)
    end
  end

  defp do_enqueue(payload) do
    # Generate ordered key for FIFO processing
    key = {System.monotonic_time(), make_ref()}

    # Capture OpenTelemetry context for tracing
    span_ctx = OpenTelemetry.Ctx.get_current()

    # Direct ETS write (lock-free)
    entry = {payload, System.monotonic_time(), span_ctx}
    :ets.insert(@table_name, {key, entry})

    # Update atomic counter
    :atomics.add(:persistent_term.get(@queue_size_counter), 1, 1)

    # Emit telemetry
    new_size = :atomics.get(:persistent_term.get(@queue_size_counter), 1)
    :telemetry.execute([:tas, :queue, :enqueue], %{queue_len: new_size}, %{})

    :ok
  end

  @doc """
  Get current queue statistics.
  """
  @spec stats() :: %{queue_size: non_neg_integer(), in_flight: non_neg_integer()}
  def stats do
    queue_size = :atomics.get(:persistent_term.get(@queue_size_counter), 1)
    in_flight = :atomics.get(:persistent_term.get(@in_flight_counter), 1)

    %{queue_size: max(0, queue_size), in_flight: max(0, in_flight)}
  end

  # GenServer callbacks (for worker management only)

  @impl true
  def init(opts) do
    config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])

    max_concurrency =
      Keyword.get(
        opts,
        :max_concurrency,
        Keyword.get(config, :max_concurrency, System.schedulers_online() * 2)
      )

    # Create ETS table for work queue
    table_opts = [
      :ordered_set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ]

    @table_name = :ets.new(@table_name, table_opts)

    # Create atomic counters
    queue_counter = :atomics.new(1, [])
    in_flight_counter = :atomics.new(1, [])

    # Store counters in persistent_term for fast access
    :persistent_term.put(@queue_size_counter, queue_counter)
    :persistent_term.put(@in_flight_counter, in_flight_counter)

    state = %{
      max_concurrency: max_concurrency,
      worker_tasks: MapSet.new()
    }

    # Start initial worker pool
    {:ok, start_workers(state), {:continue, :emit_initial_state}}
  end

  @impl true
  def handle_continue(:emit_initial_state, state) do
    emit_state()
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Worker completed
    _ = Process.demonitor(ref, [:flush])

    # Remove from worker set and decrement in-flight counter
    worker_tasks = MapSet.delete(state.worker_tasks, ref)
    :atomics.sub(:persistent_term.get(@in_flight_counter), 1, 1)

    case result do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Payment worker error: #{inspect(reason)}")
      other -> Logger.debug("Payment worker result: #{inspect(other)}")
    end

    # Maintain worker pool size
    state = %{state | worker_tasks: worker_tasks}
    state = start_workers(state)

    emit_state()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Worker crashed
    if MapSet.member?(state.worker_tasks, ref) do
      Logger.error("Payment worker crashed: #{inspect(reason)}")

      worker_tasks = MapSet.delete(state.worker_tasks, ref)
      :atomics.sub(:persistent_term.get(@in_flight_counter), 1, 1)

      state = %{state | worker_tasks: worker_tasks}
      state = start_workers(state)

      emit_state()
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Private functions

  # Start workers up to max concurrency
  defp start_workers(state) do
    current_workers = MapSet.size(state.worker_tasks)
    needed_workers = state.max_concurrency - current_workers

    if needed_workers > 0 do
      new_tasks =
        1..needed_workers
        |> Enum.map(fn _ -> start_worker() end)
        |> Enum.into(MapSet.new())

      worker_tasks = MapSet.union(state.worker_tasks, new_tasks)
      %{state | worker_tasks: worker_tasks}
    else
      state
    end
  end

  # Start a single worker task
  defp start_worker do
    task =
      Task.Supervisor.async_nolink(TasRinhaback3ed.PaymentTaskSup, fn ->
        worker_loop()
      end)

    :atomics.add(:persistent_term.get(@in_flight_counter), 1, 1)
    task.ref
  end

  # Worker main loop - drain ETS queue
  defp worker_loop do
    case take_next_work() do
      {:ok, payload, _enqueue_time, span_ctx, wait_ms} ->
        # Process the payment
        token = if span_ctx, do: OpenTelemetry.Ctx.attach(span_ctx), else: nil

        :telemetry.span([:tas, :queue, :job], %{wait_ms: wait_ms}, fn ->
          try do
            result = PaymentGateway.send_payment(payload)
            meta = %{result: if(match?({:error, _}, result), do: :error, else: :ok)}
            {result, meta}
          after
            if token, do: OpenTelemetry.Ctx.detach(token)
          end
        end)

        # Continue processing
        worker_loop()

      :empty ->
        # No work available, sleep briefly then retry
        Process.sleep(1)
        worker_loop()
    end
  rescue
    error ->
      Logger.error("Worker loop error: #{inspect(error)}")
      # Continue despite errors
      worker_loop()
  end

  # Take the next work item from ETS queue
  defp take_next_work do
    case :ets.first(@table_name) do
      :"$end_of_table" ->
        :empty

      key ->
        case :ets.take(@table_name, key) do
          [{^key, {payload, enqueue_time, span_ctx}}] ->
            # Successfully took work item
            :atomics.sub(:persistent_term.get(@queue_size_counter), 1, 1)

            # Calculate wait time
            now = System.monotonic_time()
            wait_ms = System.convert_time_unit(now - enqueue_time, :native, :millisecond)
            :telemetry.execute([:tas, :queue, :wait_time], %{wait_ms: wait_ms}, %{})

            {:ok, payload, enqueue_time, span_ctx, wait_ms}

          [] ->
            # Someone else took it, try again
            take_next_work()
        end
    end
  end

  # Emit queue state telemetry
  defp emit_state do
    queue_size = :atomics.get(:persistent_term.get(@queue_size_counter), 1)
    in_flight = :atomics.get(:persistent_term.get(@in_flight_counter), 1)

    :telemetry.execute(
      [:tas, :queue, :state],
      %{queue_len: max(0, queue_size), in_flight: max(0, in_flight)},
      %{}
    )
  end

  @impl true
  def terminate(_reason, _state) do
    # Clean up persistent terms
    :persistent_term.erase(@queue_size_counter)
    :persistent_term.erase(@in_flight_counter)

    # ETS table will be cleaned up automatically
    :ok
  end
end
