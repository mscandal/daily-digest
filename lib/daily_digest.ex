defmodule DailyDigest do
  use Application

  def start(_type, _args) do
    Logger.add_backend {LoggerFileBackend, :debug}
    Logger.configure_backend {LoggerFileBackend, :debug},
      path: "/tmp/daily-debug.log",
      level: :debug

    children = [
      {DailyDigest.Rss, []}
    ]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
