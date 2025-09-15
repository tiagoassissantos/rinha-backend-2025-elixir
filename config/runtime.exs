import Config

if config_env() == :prod do
  port =
    case System.get_env("PORT") do
      nil -> 9999
      val -> String.to_integer(val)
    end

  config :tas_rinhaback_3ed, :http, port: port
end

# Repo configuration in runtime for dev and prod
if config_env() in [:dev, :prod] do
  db_url = System.get_env("DATABASE_URL")

  repo_config =
    if db_url && db_url != "" do
      [url: db_url]
    else
      [
        hostname: System.get_env("DB_HOST", "localhost"),
        port: String.to_integer(System.get_env("DB_PORT", "5432")),
        username: System.get_env("DB_USER", "postgres"),
        password: System.get_env("DB_PASSWORD", "postgres"),
        database: System.get_env("DB_NAME", "tasrinha_dev")
      ]
    end

  pool_size =
    case System.get_env("DB_POOL_SIZE") do
      nil -> System.schedulers_online() * 2
      v -> String.to_integer(v)
    end

  ssl = System.get_env("DB_SSL", "false") in ["1", "true", "TRUE", "yes", "on"]

  config :tas_rinhaback_3ed,
         TasRinhaback3ed.Repo,
         Keyword.merge(repo_config, pool_size: pool_size, ssl: ssl, log: false)
end

# OpenTelemetry exporter/runtime configuration (dev + prod)
if config_env() in [:dev, :prod] do
  collector_host = System.get_env("OTEL_COLLECTOR_HOST", "otel-collector")
  collector_grpc_port = String.to_integer(System.get_env("OTEL_COLLECTOR_GRPC_PORT", "4317"))
  service_name = System.get_env("OTEL_SERVICE_NAME", "tas_rinhaback_3ed")

  config :opentelemetry, :resource, service: [name: service_name]

  # Export traces/metrics via OTLP gRPC to the Collector
  config :opentelemetry, :processors, [
    {:otel_batch_processor,
     %{
       exporter:
         {:opentelemetry_exporter,
          %{
            endpoints: [
              {:grpc, String.to_charlist(collector_host), collector_grpc_port, []}
            ]
          }}
     }}
  ]
end
