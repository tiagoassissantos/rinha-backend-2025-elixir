import Config

# General application configuration can go here if needed.

# Use Jason for JSON library in Plug and Phoenix (if later added)
# config :plug, :json_library, Jason

# Logger configuration - optimized for performance (warning level, minimal metadata)
config :logger, :console,
  level: :warning,
  format: "$time [$level] $message\n",
  metadata: []

# Payment queue defaults
config :tas_rinhaback_3ed, :payment_queue,
  max_concurrency: System.schedulers_online() * 1,
  max_queue_size: 50_000

# Ecto repos
config :tas_rinhaback_3ed, ecto_repos: [TasRinhaback3ed.Repo]
