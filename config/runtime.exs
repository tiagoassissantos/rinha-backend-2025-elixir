import Config

if config_env() == :prod do
  port =
    case System.get_env("PORT") do
      nil -> 9999
      val -> String.to_integer(val)
    end

  config :tas_rinhaback_3ed, :http, port: port
end
