defmodule DailyDigest do
  use Application

  def start(_type, _args) do
    children = [
      {DailyDigest.Rss, []}
    ]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
