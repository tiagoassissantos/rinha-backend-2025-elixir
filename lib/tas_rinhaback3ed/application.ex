defmodule TasRinhaback3ed.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    queue_children = [
      {Task.Supervisor, name: TasRinhaback3ed.PaymentTaskSup},
      TasRinhaback3ed.Services.PaymentQueue
    ]

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

    children = queue_children ++ http_children

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TasRinhaback3ed.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
