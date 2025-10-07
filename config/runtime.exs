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
      nil -> System.schedulers_online() * 5
      v -> String.to_integer(v)
    end

  ssl = System.get_env("DB_SSL", "false") in ["1", "true", "TRUE", "yes", "on"]

  config :tas_rinhaback_3ed,
         TasRinhaback3ed.Repo,
         Keyword.merge(repo_config,
              pool_size: pool_size,
              cache_size: 100,
              ssl: ssl,
              log: false)
end

# HTTP client (Finch) pool configuration
if config_env() in [:dev, :prod] do
  pool_size =
    case System.get_env("HTTP_POOL_SIZE") do
      nil -> 300
      v -> String.to_integer(v)
    end

  pool_count =
    case System.get_env("HTTP_POOL_COUNT") do
      nil -> 1
      v -> String.to_integer(v)
    end

  config :tas_rinhaback_3ed, :http_client, pool_size: pool_size, pool_count: pool_count
end

if config_env() in [:dev, :prod] do
  queue_env_value = System.get_env("PAYMENT_QUEUE_MAX_SIZE")

  queue_config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])
  IO.puts("queue_config: #{inspect(queue_config)}")

  if queue_env_value && queue_env_value != "" do
    normalized = String.downcase(queue_env_value)

    queue_max_size =
      case normalized do
        "infinity" ->
          :infinity

        value ->
          case Integer.parse(value) do
            {int, ""} when int >= 0 ->
              int

            _ ->
              raise ArgumentError,
                    "PAYMENT_QUEUE_MAX_SIZE must be a positive integer or \"infinity\""
          end
      end

    config :tas_rinhaback_3ed,
           :payment_queue,
           Keyword.put(queue_config, :max_queue_size, queue_max_size)
  end
end
