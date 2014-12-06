defmodule ElixirWebCrawler.Worker do
  use Supervisor
  """
    Redis is using 
      set - download_queue
      hash - processing_{item}
      set - download_finished
      set - download_failed
    Using sets so can easily see downloaded or not
  """

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    # An anonymous function to create download workers
    spec_fun = fn(x) ->
      worker_name = "worker_download" <> to_string(x)
      worker(ElixirWebCrawler.Worker, [], restart: :permanent, id: worker_name, function: :spawn_download)
    end
    # setup 5 download workers
    download_workers = Enum.map(1..5, spec_fun)

    children = [
      worker(ElixirWebCrawler.RedisSupervisor, []),
      worker(ElixirWebCrawler.Worker, [], restart: :permanent, id: "worker_parse", function: :spawn_parse),
      worker(ElixirWebCrawler.Worker, [], restart: :permanent, id: "worker_requeue", function: :spawn_requeue)
      ] ++ download_workers

    supervise(children, strategy: :one_for_one)
  end


  def q(args) do
    {:ok, item} = :poolboy.transaction(:redis_pool, fn(worker) -> :eredis.q(worker, args, 5000) end)
    item
  end

  def spawn_download() do
    pid=spawn_link(__MODULE__, :loop_download, [])
    {:ok, pid}
  end

  def spawn_parse() do
    pid=spawn_link(__MODULE__, :loop_parse, [])
    {:ok, pid}
  end

  def spawn_requeue() do
    pid=spawn_link(__MODULE__, :loop_requeue, [])
    {:ok, pid}
  end

  def loop_download() do
    pid = :erlang.pid_to_list(self())|> to_string
    IO.puts "download_loop_#{pid}"
    item = timepop("download_queue")
    process_item(item)
    loop_download()
  end

  def loop_parse() do
    pid = :erlang.pid_to_list(self())|> to_string
    IO.puts "parse_loop_#{pid}"
    item = timepop("parse_queue")
    q(["SADD", "parse_processing", item])
    parse_and_queue_download(item)
    q(["SREM", "parse_processing", item])
    loop_parse()
  end

  def loop_requeue() do
    requeue_dl_errors()
    requeue_parse_errors()
    :timer.sleep(1200000)
    loop_requeue()
  end

  def parse_and_queue_download(url) do
    ElixirWebCrawler.Parser.parse_links(url) |>
    Enum.each(fn(x) ->
      IO.puts x
      q(["SADD", "download_queue", x])
    end)
  end

  def requeue_dl_errors() do
    requeue_dl_fn = fn(x) -> 
      start_time = q(["hget", x, "start_time"])
      #IO.puts "#{unixtime() - 3600}, #{start_time}"
      if unixtime() - 3600 > String.to_integer(start_time) do
        IO.puts "requeueing #{String.slice(x,11..-1)}"
        q(["SADD", "download_queue", String.slice(x,11..-1)])
        q(["HDEL", x, "start_time", "attempts"])
      end
    end

    q(["keys", "processing_http*"]) |> Enum.each( requeue_dl_fn )
    # don't requeue failures automaticallyy
    #q(["smembers", "download_failed"]) |>
    #Enum.each( fn(x) ->
    #  q(["SMOVE", "download_failed", "download_queue", x])
    #end)
  end

  def requeue_parse_errors() do
    q(["smembers", "parse_processing"]) |>
    Enum.each( fn(x) ->
      q(["SMOVE", "parse_processing", "parse_queue", x])
    end)
  end

  def handle_failure(item, msg) do
    IO.puts msg
    :timer.sleep(30000)
    :init.stop()
  end

  def process_item(item) do
    "
    Pop item - 'download_queue'
    Make sure that it is not a repeat - SISMEMBER('download_finished', item)
    Insert into processing hash HMSET processing_{item} tries 1 time unixtime
    Do DL and save to disk
    HDEL processing_item_{item}
    SADD('download_finished', item)
    Any error goes to download_failed set"

    IO.puts "#{item} - START process_item"

    # keep a count of the number of times a host fetches
    tmp = q(["HGET", "#{URI.parse(item).host}", "#{Node.self}"])
    if tmp == :undefined do
      current_count = 0
    else
      current_count = tmp |> Integer.parse |> elem(0)
    end
    IO.puts "count = #{URI.parse(item).host} - #{current_count}"

    cond do 
      # Check if count is too high from this node
      current_count > 100 ->
        handle_failure(item, "shutting down as limit has passed - check worker.ex line 143 ")
      q(["SISMEMBER", "download_finished", item]) == "1" ->
        IO.puts "already done #{item}"
      # Check if it's processing already
      q(["HEXISTS", "processing_#{item}", "start_time"]) == "1" ->
        IO.puts "already started #{item}"
        # should check how long it has been and whether to increment and continue
      true ->
        # Set that it's processing
        IO.puts "processing #{item}"
        q(["HINCRBY","#{URI.parse(item).host}", "#{Node.self}", 1])
        q(["HMSET","processing_#{item}", "start_time", unixtime(), "attempts", 1])
        case download(item) do 
          {:ok, _ } -> 
            q(["SADD","download_finished", item])
            IO.puts "putting into parse_queue"
            q(["SADD","parse_queue",item])
          {:error, msg} -> 
            q(["SADD","download_failure", item])
            handle_failure(item, "Error in download #{msg}")
        end
        # Delete the processing queue
        q(["HDEL","processing_#{item}", "start_time", "attempts"]) 
    end
    IO.puts "#{item} - END process_item"
    :ok
  end

  def timepop( name ) do
    item = q(["SPOP",name])
    if item == :undefined  do
      :timer.sleep(1000)
      item = timepop( name )
    end
    item
  end

  def unixtime() do
    :calendar.datetime_to_gregorian_seconds(:calendar.now_to_universal_time( :erlang.now()))-719528*24*3600
  end

  def random_number(min, max) do
    :random.seed(:os.timestamp)
    :random.seed(:os.timestamp)
    (max - min) * :random.uniform + min
  end

  def download(url) when is_binary(url) do
    download String.to_char_list(url)
  end

  def download(url) do
    r = round(random_number(10000,40000))
    IO.puts "Sleeping for #{r}"
    :timer.sleep(r)

    case :ibrowse.send_req(url, [], :get, [], [{ "http_vsn", "HTTP/1.0"}]) do
      {:ok, '200', _headers, body} -> 
        {:ok} = ElixirWebCrawler.File.save_remote(url, body)
        {:ok, "saved successfully"}
      {:ok, status, _headers, _body} -> 
        {:error, "#{status} is not 200"}
      {:error, reason} ->
          {:error, reason}
    end
  end
end
