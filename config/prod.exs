import Config

config :logger,
  level: :warning,
  backends: [:console],
  truncate: 4096,
  compile_time_purge_matching: [[level_lower_than: :info]]
