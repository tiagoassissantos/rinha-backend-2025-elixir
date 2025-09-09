import Config

# General application configuration can go here if needed.

# Use Jason for JSON library in Plug and Phoenix (if later added)
#config :plug, :json_library, Jason

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
