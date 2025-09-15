defmodule TasRinhaback3ed.MixProject do
  use Mix.Project

  def project do
    [
      app: :tas_rinhaback_3ed,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      releases: [
        tas_rinhaback_3ed: [
          applications: [
            opentelemetry_exporter: :temporary,
            opentelemetry: :temporary
          ]
        ]
      ],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # Ensure TLS certificate store app is started before OTLP exporter init
      extra_applications: [:logger, :tls_certificate_check, :opentelemetry_exporter],
      mod: {TasRinhaback3ed.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.15"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.1"},
      {:req, "~> 0.5.0"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:bypass, "~> 2.1", only: :test},

      # OpenTelemetry core & exporter (OTLP)
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_semantic_conventions, "~> 1.27"},

      # Server-side HTTP (Bandit) tracing
      {:opentelemetry_bandit, "~> 0.3"},

      # DB tracing
      {:opentelemetry_ecto, "~> 1.2"},

      # Outbound HTTP (Req) tracing
      {:opentelemetry_req, "~> 1.0"},

      # Telemetry → Prometheus reporter + built-in /metrics server
      {:telemetry_metrics_prometheus, "~> 1.1"},

      # Periodic VM/process measurements
      {:telemetry_poller, "~> 1.3"}
    ]
  end
end
