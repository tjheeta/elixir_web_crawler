defmodule ElixirWebCrawler do
  use Application
  def start(_type, _args) do
    ElixirWebCrawler.Worker.start_link
  end
end
