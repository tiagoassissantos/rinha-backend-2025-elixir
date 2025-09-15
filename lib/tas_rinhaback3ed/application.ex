defmodule TasRinhaback3ed.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # OpenTelemetry exporter is configured via config/runtime.exs

    # ---- Bandit/Plug server spans ----
    OpentelemetryBandit.setup()

    # ---- Ecto spans ----
    # Telemetry prefix for this app's Repo (derived from module name)
    OpentelemetryEcto.setup([:tas_rinhaback3ed, :repo])

    # Observability components (Prometheus exporter and periodic VM metrics)
    opentel_children = [
      {TelemetryMetricsPrometheus, metrics: TasRinhaback3ed.Metrics.definitions()},
      # telemetry_poller expects the evaluated list, not a function capture
      {:telemetry_poller, measurements: TasRinhaback3ed.Metrics.vm_measurements(), period: 5_000}
    ]

    queue_children = [
      {Task.Supervisor, name: TasRinhaback3ed.PaymentTaskSup},
      TasRinhaback3ed.Services.PaymentQueue
    ]

    repo_children =
      if Mix.env() == :test do
        []
      else
        [TasRinhaback3ed.Repo]
      end

    http_children =
      if Mix.env() == :test do
        []
      else
        port =
          case System.get_env("PORT") do
            nil -> 9999
            val -> String.to_integer(val)
          end

        [
          {
            Bandit,
            plug: TasRinhaback3ed.Router, scheme: :http, port: port
          }
        ]
      end

    children = repo_children ++ queue_children ++ http_children ++ opentel_children

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TasRinhaback3ed.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
