defmodule TasRinhaback3ed.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    queue_config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])
    queue_mode = Keyword.get(queue_config, :mode, :local)
    role = Application.get_env(:tas_rinhaback_3ed, :app_role, :api)

    http_client_children = [
      {Finch, name: TasRinhaback3ed.Finch, pools: finch_pools()}
    ]

    queue_children =
      case queue_mode do
        :local ->
          [
            {Task.Supervisor, name: TasRinhaback3ed.PaymentTaskSup},
            TasRinhaback3ed.Services.PaymentQueue,
            TasRinhaback3ed.Services.PaymentWorker
          ]

        {:remote, _node} ->
          []
      end

    Logger.warning("role: #{inspect(role)}")
    Logger.warning("queue_children: #{inspect(queue_children)}")

    repo_children = [TasRinhaback3ed.Repo]

    acceptors = String.to_integer(System.get_env("API_BANDIT_ACCEPTORS", "1"))
    max_conn  = String.to_integer(System.get_env("API_BANDIT_MAX_CONN", "200"))
    keep_ms   = String.to_integer(System.get_env("API_CONN_KEEPALIVE_MS", "3000"))

    http_children =
      cond do
        role == :worker ->
          []

        current_env() == :test ->
          []

        true ->
          port =
            case System.get_env("PORT") do
              nil -> 9999
              val -> String.to_integer(val)
            end

          [
            {
              Bandit,
              plug: TasRinhaback3ed.Router,
              scheme: :http,
              port: port,
              thousand_island_options: [num_acceptors: 1]
              #thousand_island_options: [num_acceptors: acceptors, num_connections: max_conn, read_timeout: keep_ms],
              #http_1_options: [max_header_length: 16_384, max_request_line_length: 8_192]
            }
          ]
      end

    children =
      repo_children ++ http_client_children ++ queue_children ++ http_children

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
    size = Keyword.get(cfg, :pool_size, 10)
    count = Keyword.get(cfg, :pool_count, 1)

    Logger.warning("finch_client_pool_size: #{inspect(size)}")
    Logger.warning("finch_client_pool_count: #{inspect(count)}")

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
