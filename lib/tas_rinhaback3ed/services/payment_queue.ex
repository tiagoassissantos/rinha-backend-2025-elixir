defmodule TasRinhaback3ed.Services.PaymentQueue do
  @moduledoc """
  In-memory, high-performance payment queue using a GenServer + :queue
  and a Task.Supervisor for controlled concurrency.

  - Enqueue returns immediately and workers forward to the `PaymentGateway`.
  - Concurrency is bounded by `:max_concurrency` (configurable).
  - Optional `:max_queue_size` to apply back-pressure (default: :infinity).

  Config (in `config/*.exs`):
    config :tas_rinhaback_3ed, :payment_queue,
      max_concurrency: System.schedulers_online() * 2,
      max_queue_size: :infinity
  """

  use GenServer
  require Logger

  alias TasRinhaback3ed.Services.PaymentGateway

  @type payload :: map()
  @type enqueue_result :: {:ok, :queued} | {:error, :queue_full}

  # Public API
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueue a payment payload for asynchronous processing.
  """
  @spec enqueue(payload()) :: enqueue_result()
  def enqueue(payload) when is_map(payload) do
    # Capture caller's Logger metadata (includes request_id set by Plug.RequestId)
    caller_md = Logger.metadata()
    # Capture current OpenTelemetry context so worker spans join the HTTP trace
    otel_ctx = OpenTelemetry.Ctx.get_current()
    GenServer.call(__MODULE__, {:enqueue, payload, caller_md, otel_ctx})
  end

  # Server callbacks
  @impl true
  def init(opts) do
    config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])

    max_concurrency =
      Keyword.get(
        opts,
        :max_concurrency,
        Keyword.get(config, :max_concurrency, System.schedulers_online() * 2)
      )

    max_queue_size =
      Keyword.get(opts, :max_queue_size, Keyword.get(config, :max_queue_size, :infinity))

    state = %{
      queue: :queue.new(),
      queued_count: 0,
      in_flight: 0,
      max_concurrency: max_concurrency,
      max_queue_size: max_queue_size,
      tasks: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, payload, caller_md, otel_ctx}, _from, state) do
    cond do
      state.max_queue_size != :infinity and state.queued_count >= state.max_queue_size ->
        :telemetry.execute([:tas, :queue, :drop], %{queue_len: state.queued_count}, %{})
        emit_state(state)
        {:reply, {:error, :queue_full}, state}

      true ->
        entry = %{
          payload: payload,
          enq_mono: System.monotonic_time(),
          logger_md: caller_md,
          otel_ctx: otel_ctx
        }
        q = :queue.in(entry, state.queue)
        state = %{state | queue: q, queued_count: state.queued_count + 1}
        :telemetry.execute([:tas, :queue, :enqueue], %{queue_len: state.queued_count}, %{})
        state = dispatch(state)
        emit_state(state)
        {:reply, {:ok, :queued}, state}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed; demonitor and account
    _ = Process.demonitor(ref, [:flush])
    {_task, _payload} = Map.get(state.tasks, ref, {nil, nil})
    tasks = Map.delete(state.tasks, ref)
    state = %{state | tasks: tasks, in_flight: state.in_flight - 1}

    case result do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Payment worker error: #{inspect(reason)}")
      other -> Logger.debug("Payment worker result: #{inspect(other)}")
    end

    state = dispatch(state)
    emit_state(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # In case a task crashes without delivering a message, account it.
    if Map.has_key?(state.tasks, ref) do
      Logger.error("Payment worker crashed: #{inspect(reason)}")
      tasks = Map.delete(state.tasks, ref)
      state = %{state | tasks: tasks, in_flight: state.in_flight - 1}
      state = dispatch(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Internal: start as many tasks as capacity allows
  defp dispatch(state) do
    do_dispatch(state)
  end

  defp do_dispatch(%{in_flight: inflight, max_concurrency: max} = state) when inflight >= max,
    do: state

  # When queue empty, nothing to do
  defp do_dispatch(%{queued_count: 0} = state), do: state

  defp do_dispatch(state) do
    case :queue.out(state.queue) do
      {{:value, %{payload: payload, enq_mono: t0, logger_md: logger_md, otel_ctx: otel_ctx}}, q1} ->
        now = System.monotonic_time()
        wait_ms = System.convert_time_unit(now - t0, :native, :millisecond)
        :telemetry.execute([:tas, :queue, :wait_time], %{wait_ms: wait_ms}, %{})

        task =
          Task.Supervisor.async_nolink(TasRinhaback3ed.PaymentTaskSup, fn ->
            # Restore caller's Logger metadata in this task so logs include request_id
            if is_list(logger_md) and logger_md != [] do
              Logger.metadata(logger_md)
            end
            # Attach parent OpenTelemetry context so spans join the HTTP request trace
            token = if otel_ctx, do: OpenTelemetry.Ctx.attach(otel_ctx), else: nil
            :telemetry.span([:tas, :queue, :job], %{wait_ms: wait_ms}, fn ->
              try do
                result = PaymentGateway.send_payment(payload)
                meta = %{result: if(match?({:error, _}, result), do: :error, else: :ok)}
                {result, meta}
              after
                if token, do: OpenTelemetry.Ctx.detach(token)
              end
            end)
          end)

        tasks = Map.put(state.tasks, task.ref, {task, payload})

        state = %{
          state
          | queue: q1,
            queued_count: state.queued_count - 1,
            in_flight: state.in_flight + 1,
            tasks: tasks
        }

        emit_state(state)
        do_dispatch(state)

      {:empty, _q} ->
        new_state = %{state | queued_count: 0}
        emit_state(new_state)
        new_state
    end
  end

  defp emit_state(state) do
    :telemetry.execute(
      [:tas, :queue, :state],
      %{queue_len: state.queued_count, in_flight: state.in_flight},
      %{}
    )
  end
end
