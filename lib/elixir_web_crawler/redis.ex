defmodule ElixirWebCrawler.RedisSupervisor do
  use Supervisor

  # this will create a linked process and call init
  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    pool_options = [
      {:name, {:local, :redis_pool}},
      {:worker_module, :eredis}, 
      {:size, 5},
      {:max_overflow, 10}
      ]
    eredis_args = [
      {:host, String.to_char_list(Confort.get(:master_ip))},
      {:port, 6379}
      ]
    children = [
      :poolboy.child_spec( :redis_pool, pool_options, eredis_args )
      ]
    supervise(children, strategy: :one_for_one)
  end

  # a redis query transaction function
  def q(args) do
    {:ok, item} = :poolboy.transaction(:redis_pool, fn(worker) -> :eredis.q(worker, args, 5000) end)
  end

end
