defmodule TasRinhaback3ed.PromEx.Queue do
  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = PromEx.metric_prefix(otp_app, :queue)

    [
      PromEx.MetricTypes.Event.build(:tas_queue, [
        counter(metric_prefix ++ [:enqueued, :total],
          event_name: [:tas, :queue, :enqueue],
          description: "Total enqueued items"
        ),
        counter(metric_prefix ++ [:dropped, :total],
          event_name: [:tas, :queue, :drop],
          description: "Total dropped due to queue_full"
        ),
        last_value(metric_prefix ++ [:length],
          event_name: [:tas, :queue, :state],
          measurement: :queue_len,
          description: "Current queue length"
        ),
        last_value(metric_prefix ++ [:in_flight],
          event_name: [:tas, :queue, :state],
          measurement: :in_flight,
          description: "Current in-flight workers"
        ),
        distribution(metric_prefix ++ [:job, :duration, :milliseconds],
          event_name: [:tas, :queue, :job, :stop],
          measurement: :duration,
          description: "Time spent processing a job (gateway call)",
          tags: [:result],
          tag_values: &__MODULE__.queue_job_tag_values/1,
          unit: {:native, :millisecond},
          reporter_options: [buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2500]]
        ),
        distribution(metric_prefix ++ [:wait_time, :milliseconds],
          event_name: [:tas, :queue, :wait_time],
          measurement: :wait_ms,
          description: "Time spent waiting in queue",
          unit: :millisecond,
          reporter_options: [buckets: [0, 1, 2, 5, 10, 25, 50, 100, 250, 500]]
        )
      ])
    ]
  end

  def queue_job_tag_values(%{result: result}), do: %{result: result}
end

