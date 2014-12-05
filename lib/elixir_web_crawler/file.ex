defmodule ElixirWebCrawler.File do
  """
  Transfers files to and from different nodes
  """
  def generate_path(url) do
    uri = URI.parse(to_string(url))
    # could have malicious urls with ../../../, but this is demo code
    path = Path.join("/home/erlang/dl", uri.host)
    path = cond do
      uri.path == nil ->
        Path.join(path, "index.html")
      uri.path ->
        tmp = Path.join(path,uri.path)
        if String.ends_with? uri.path, "/" do
          tmp = Path.join(tmp, "index.html")
        end
        tmp
    end
    path = path <> ".gz"
    path
  end

  def save_remote(url, body) do
    ip = Confort.get(:master_ip)
    node_name = :"node@#{ip}"
    {:ok} = :rpc.call(node_name, ElixirWebCrawler.File, :save_file, [ url, body])
  end

  def save_file(url, body) do
    path = generate_path(url)
    File.mkdir_p(Path.dirname(path))
    {:ok, file} = File.open path, [:write]
    IO.binwrite file, :zlib.gzip(body)
    File.close(file)
    IO.puts "SAVED #{url} to #{path}"
    {:ok}
  end

  def read_remote(url) do
    ip = Confort.get(:master_ip)
    node_name = :"node@#{ip}"
    {:ok, body} = :rpc.call(node_name, ElixirWebCrawler.File, :read_file, [ url ])
    {:ok, body}
  end

  def read_file(url) do
    # this will crash unless it returns {:ok, body}
    # make sure it's in a processing queue somewhere 
    path = generate_path(url)
    case File.read path do
      {:ok, body} ->
        status=:ok
        value=:zlib.gunzip(body)
      {:error, body} ->
        if Node.self != :"node@#{Confort.get(:master_ip)}" do
          {:ok, body} = read_remote(url)
          status=:ok
          value=body
        else
          status=:error
          value="File doesn't exist on master"
        end
    end
    {status,value}
  end
end
