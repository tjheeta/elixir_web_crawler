defmodule ElixirWebCrawler.Parser do
  """ 
  This takes the url and reads the file off disk to parse
  """
  def normalize_link(url_to_parse, url) do
    uri = URI.parse(to_string(url))
    original_uri = URI.parse(to_string(url_to_parse))
    if uri.host && uri.scheme do
      url
    else
      "#{original_uri.scheme}://#{original_uri.host}#{uri.path}"
    end
  end

  def on_origin(origin_url, url) do
    (String.starts_with?(url, "/") and URI.parse(url).host == nil)
      or URI.parse(origin_url).host == URI.parse(url).host
  end

  def is_url_uploadable(url_to_parse, url) do
    if url != nil do
      on_origin(url_to_parse, url)
    else
      false
    end
  end

  def parse_links(url_to_parse) do
    {:ok, body} = ElixirWebCrawler.File.read_file(url_to_parse)
    data = :qrly_html.parse_string(body) 
      |> :qrly.filter('a') 
      |> Enum.map(&get_href/1)
      |> Enum.filter(&is_url_uploadable(url_to_parse, &1))
      |> Enum.map(&(normalize_link(url_to_parse, &1)))
    data
  end

  # List of the href after :qrly_html.parse_string |> :qrly.filter('a')
  def get_href({"a", attrs, _content}) do
    case List.keyfind attrs, "href", 0 do
      {_, href} -> href
      _ -> nil
    end
  end
end
