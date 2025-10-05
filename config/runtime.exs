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

  db_pool_size =
    case System.get_env("DB_POOL_SIZE") do
      nil -> System.schedulers_online() * 5
      v -> String.to_integer(v)
    end

  db_pool_count =
    case System.get_env("DB_POOL_COUNT") do
      nil -> 1
      v -> String.to_integer(v)
    end

  IO.puts("db_pool_size: #{inspect(db_pool_size)}")
  IO.puts("db_pool_count: #{inspect(db_pool_count)}")

  ssl = System.get_env("DB_SSL", "false") in ["1", "true", "TRUE", "yes", "on"]

  config :tas_rinhaback_3ed,
         TasRinhaback3ed.Repo,
         Keyword.merge(repo_config,
              pool_size: db_pool_size,
              cache_size: 100,
              ssl: ssl,
              log: false)
end

# HTTP client (Finch) pool configuration
if config_env() in [:dev, :prod] do
  pool_size =
    case System.get_env("FINCH_POOL_SIZE") do
      nil -> 300
      v -> String.to_integer(v)
    end

  pool_count =
    case System.get_env("FINCH_POOL_COUNT") do
      nil -> 5
      v -> String.to_integer(v)
    end

  IO.puts("http_pool_size: #{inspect(pool_size)}")
  IO.puts("http_pool_count: #{inspect(pool_count)}")

  config :tas_rinhaback_3ed, :http_client, pool_size: pool_size, pool_count: pool_count
end

if config_env() in [:dev, :prod] do
  queue_env_value = System.get_env("PAYMENT_QUEUE_MAX_SIZE")

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

    queue_config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])

    config :tas_rinhaback_3ed,
           :payment_queue,
           Keyword.put(queue_config, :max_queue_size, queue_max_size)
  end

  role =
    System.get_env("APP_ROLE", "api")
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> :api
      "api" -> :api
      "worker" -> :worker
      other ->
        raise ArgumentError, "APP_ROLE must be either \"api\" or \"worker\", got: #{inspect(other)}"
    end

  queue_config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])

  queue_mode =
    case {role, System.get_env("PAYMENT_QUEUE_NODE")} do
      {:worker, _} ->
        :local

      {:api, nil} ->
        Keyword.get(queue_config, :mode, :local)

      {:api, node_name} ->
        trimmed = String.trim(node_name)

        if trimmed == "" do
          Keyword.get(queue_config, :mode, :local)
        else
          unless String.contains?(trimmed, "@") do
            raise ArgumentError,
                  "PAYMENT_QUEUE_NODE must include a node and host, e.g., worker1@worker1"
          end

          {:remote, String.to_atom(trimmed)}
        end
    end

  queue_config = Keyword.put(queue_config, :mode, queue_mode)

  config :tas_rinhaback_3ed, :payment_queue, queue_config
  config :tas_rinhaback_3ed, :app_role, role
end
