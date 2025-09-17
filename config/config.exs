import Config

# General application configuration can go here if needed.

# Use Jason for JSON library in Plug and Phoenix (if later added)
# config :plug, :json_library, Jason

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Payment queue defaults
config :tas_rinhaback_3ed, :payment_queue,
  max_concurrency: System.schedulers_online() * 280,
  max_queue_size: :infinity

# Ecto repos
config :tas_rinhaback_3ed, ecto_repos: [TasRinhaback3ed.Repo]
