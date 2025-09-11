defmodule TasRinhaback3ed.PromEx do
  use PromEx, otp_app: :tas_rinhaback_3ed

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Ecto, repos: [TasRinhaback3ed.Repo]},
      {PromEx.Plugins.PlugRouter,
       event_prefix: [:tas, :http],
       routers: [TasRinhaback3ed.Router],
       ignore_routes: ["/metrics"]},
      TasRinhaback3ed.PromEx.Queue
    ]
  end

  @impl true
  def dashboards, do: []
end
