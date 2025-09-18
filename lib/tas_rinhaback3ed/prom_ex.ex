defmodule TasRinhaback3ed.PromEx do
  @moduledoc """
  Prometheus metrics configuration powered by PromEx.
  """

  use PromEx, otp_app: :tas_rinhaback_3ed

  alias PromEx.Plugins

  @router_event_prefix [:tas_rinhaback3ed, :router]

  @impl true
  def plugins do
    [
      Plugins.Beam,
      {Plugins.Application, otp_app: :tas_rinhaback_3ed},
      plug_router_plugin()
    ] ++ repo_plugins()
  end

  defp plug_router_plugin do
    {Plugins.PlugRouter,
     event_prefix: @router_event_prefix,
     routers: [TasRinhaback3ed.Router],
     ignore_routes: ["/metrics"]}
  end

  defp repo_plugins do
    case Application.get_env(:tas_rinhaback_3ed, :ecto_repos, []) do
      [] ->
        []

      repos ->
        [
          {Plugins.Ecto, repos: repos}
        ]
    end
  end
end
