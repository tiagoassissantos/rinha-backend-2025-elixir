defmodule TasRinhaback3ed.Services.PaymentQueue do
  @moduledoc """
  Lock-free ETS-backed queue that stores payment payloads.

  Producers (controllers) enqueue payloads with `enqueue/1` while
  `TasRinhaback3ed.Services.PaymentWorker` drains the queue via `dequeue/0`
  and forwards each payload to the payment gateway. Queue statistics are
  tracked through `:atomics` counters stored in `:persistent_term`.
  """

  use GenServer
  require Logger

  @type payload :: map()
  @type enqueue_result :: :ok | {:error, :queue_full} | {:error, :queue_unavailable}
  @type dequeue_result :: {:ok, payload(), non_neg_integer()} | :empty

  @table_name :payment_work_queue
  @queue_size_counter :payment_queue_size
  @in_flight_counter :payment_in_flight
  @max_queue_size_key {__MODULE__, :max_queue_size}

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
    case max_queue_size() do
      :infinity ->
        do_enqueue(payload)

      max when is_integer(max) ->
        queue_counter = queue_counter()
        current_size = :atomics.get(queue_counter, 1)

        if current_size >= max do
          {:error, :queue_full}
        else
          do_enqueue(payload)
        end
    end
  end

  @doc """
  Retrieve the next payload from the queue.
  Returns `{:ok, payload, wait_ms}` when work is available or `:empty`.
  """
  @spec dequeue() :: dequeue_result()
  def dequeue do
    case :ets.first(@table_name) do
      :"$end_of_table" ->
        :empty

      key ->
        case :ets.take(@table_name, key) do
          [{^key, {payload, enqueue_time}}] ->
            :atomics.sub(queue_counter(), 1, 1)

            wait_ms =
              System.monotonic_time()
              |> Kernel.-(enqueue_time)
              |> System.convert_time_unit(:native, :millisecond)

            {:ok, payload, wait_ms}

          [] ->
            dequeue()
        end
    end
  end

  @doc """
  Increment the in-flight worker counter (called when a worker starts).
  """
  @spec worker_started() :: :ok
  def worker_started do
    :atomics.add(in_flight_counter(), 1, 1)
    :ok
  end

  @doc """
  Decrement the in-flight worker counter (called when a worker stops).
  """
  @spec worker_finished() :: :ok
  def worker_finished do
    counter = in_flight_counter()
    new_value = :atomics.sub(counter, 1, 1)

    if new_value < 0 do
      :atomics.put(counter, 1, 0)
    end

    :ok
  end

  @doc """
  Get current queue statistics.
  """
  @spec stats() :: %{queue_size: non_neg_integer(), in_flight: non_neg_integer()}
  def stats do
    queue_size = :atomics.get(queue_counter(), 1)
    in_flight = :atomics.get(in_flight_counter(), 1)

    %{queue_size: max(0, queue_size), in_flight: max(0, in_flight)}
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])

    max_queue_size =
      opts
      |> Keyword.get(:max_queue_size, Keyword.get(config, :max_queue_size, :infinity))

    ensure_queue_table!()
    ensure_counters!()

    :persistent_term.put(@max_queue_size_key, max_queue_size)

    {:ok, %{max_queue_size: max_queue_size}}
  end

  @impl true
  def terminate(_reason, _state) do
    cleanup_persistent_terms()
    cleanup_table()
    :ok
  end

  defp do_enqueue(payload) do
    # Generate ordered key for FIFO processing
    key = {System.monotonic_time(), make_ref()}
    entry = {payload, System.monotonic_time()}

    :ets.insert(@table_name, {key, entry})
    :atomics.add(queue_counter(), 1, 1)

    Logger.debug(";#{inspect(Map.get(payload, "correlationId"))}; Do enqueue called")

    :ok
  end

  defp max_queue_size do
    :persistent_term.get(@max_queue_size_key, :infinity)
  end

  defp ensure_queue_table! do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    :ok
  end

  defp ensure_counters! do
    queue_counter = :atomics.new(1, [])
    in_flight_counter = :atomics.new(1, [])

    :persistent_term.put(@queue_size_counter, queue_counter)
    :persistent_term.put(@in_flight_counter, in_flight_counter)
  end

  defp queue_counter do
    :persistent_term.get(@queue_size_counter)
  end

  defp in_flight_counter do
    :persistent_term.get(@in_flight_counter)
  end

  defp cleanup_persistent_terms do
    :persistent_term.erase(@queue_size_counter)
    :persistent_term.erase(@in_flight_counter)
    :persistent_term.erase(@max_queue_size_key)
  end

  defp cleanup_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ok

      _tid ->
        :ets.delete(@table_name)
        :ok
    end
  end
end
