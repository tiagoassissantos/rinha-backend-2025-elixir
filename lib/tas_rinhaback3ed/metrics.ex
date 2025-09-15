defmodule TasRinhaback3ed.Metrics do
  import Telemetry.Metrics

  # 4a) Define metrics that Prometheus will expose
  def definitions do
    [
      # BEAM memory (bytes) and run queue lengths
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes_used", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),
      last_value("vm.process.count"),

      # HTTP latency & throughput (Plug/Bandit via Telemetry events)
      # Prometheus exporter does not support `summary`; use `distribution` (histogram)
      distribution("http.server.duration",
        unit: {:native, :millisecond},
        tags: [:method, :status],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),
      counter("http.server.request.count", tags: [:method, :status]),

      # Ecto query time
      distribution("db.query.total_time",
        unit: {:native, :millisecond},
        tags: [:source, :command],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),

      # Outbound HTTP (Req) latency
      distribution("http.client.duration",
        unit: {:native, :millisecond},
        tags: [:host, :method, :status],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),

      # Your GenServer mailboxes (per name)
      last_value("genserver.mailbox.length", tags: [:name])
    ]
  end

  # 4b) Periodic measurements (every 5s) sent as Telemetry events
  def vm_measurements do
    [
      # Wrap VM primitives and dispatch telemetry within these functions
      {__MODULE__, :dispatch_memory, []},
      {__MODULE__, :dispatch_run_queues, []},
      {__MODULE__, :dispatch_process_count, []},

      # Custom mailboxes – list all important GenServers here
      {__MODULE__, :measure_mailboxes, []}
    ]
  end

  # These wrappers call the old report_* helpers to keep event shapes stable
  def dispatch_memory do
    report_memory(:erlang.memory())
  end

  def dispatch_run_queues do
    report_run_queues(:erlang.statistics(:total_run_queue_lengths))
  end

  def dispatch_process_count do
    report_process_count(:erlang.system_info(:process_count))
  end

  def report_memory(mem) do
    :telemetry.execute([:vm, :memory], %{
      total: mem[:total],
      processes_used: mem[:processes_used],
      binary: mem[:binary]
    })
  end

  def report_run_queues({total, cpu, io}) do
    :telemetry.execute([:vm, :total_run_queue_lengths], %{
      total: total,
      cpu: cpu,
      io: io
    })
  end

  # Some OTP versions may return a single integer for total run queue lengths
  def report_run_queues(total) when is_integer(total) do
    :telemetry.execute([:vm, :total_run_queue_lengths], %{
      total: total,
      cpu: 0,
      io: 0
    })
  end

  @genservers [
    {:name, TasRinhaback3ed.Services.PaymentQueue}
  ]

  def measure_mailboxes do
    Enum.each(@genservers, fn
      {:name, name} ->
        if pid = Process.whereis(name), do: emit_mailbox(name, pid)

      {:pid, pid} when is_pid(pid) ->
        emit_mailbox(inspect(pid), pid)

      _ ->
        :ok
    end)
  end

  defp emit_mailbox(label, pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} ->
        :telemetry.execute([:genserver, :mailbox], %{length: len}, %{name: label})

      _ ->
        :ok
    end
  end

  def report_process_count(count) do
    :telemetry.execute([:vm, :process], %{count: count})
  end
end
