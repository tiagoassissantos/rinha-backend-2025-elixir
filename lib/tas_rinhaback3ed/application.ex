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

    http_client_children = [
      {Finch, name: TasRinhaback3ed.Finch, pools: finch_pools()}
    ]

    queue_children = [
      {Task.Supervisor, name: TasRinhaback3ed.PaymentTaskSup},
      TasRinhaback3ed.Services.PaymentQueue
    ]

    repo_children =
      if current_env() == :test do
        []
      else
        [TasRinhaback3ed.Repo]
      end

    http_children =
      if current_env() == :test do
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

    children =
      repo_children ++ http_client_children ++ queue_children ++ http_children ++ opentel_children

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TasRinhaback3ed.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp current_env do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      Mix.env()
    else
      :prod
    end
  end

  defp finch_pools do
    cfg = Application.get_env(:tas_rinhaback_3ed, :http_client, [])
    size = Keyword.get(cfg, :pool_size, 50)
    count = Keyword.get(cfg, :pool_count, 1)

    conn_opts =
      Keyword.get(cfg, :conn_opts, transport_opts: [verify: :verify_peer], timeout: 1_000)

    default = [size: size, count: count, conn_opts: conn_opts]

    %{
      default: default
      # You can add per-origin pools here if needed, e.g.:
      # {:http, "payment-processor-default", 8080} => default,
      # {:http, "payment-processor-fallback", 8080} => default
    }
  end
end
