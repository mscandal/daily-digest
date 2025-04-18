defmodule DailyDigest.Rss do
  use GenServer
  import Crontab.CronExpression
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl true
  def init(_state) do
    schedule_next_run()
    {:ok, true}
  end

  @impl true
  def handle_info(:generate_book, _) do
    schedule_next_run()
    try do
      fetch_feed()
    rescue
      err -> Logger.error("Failed to generate digest", err)
    end
    {:noreply, true}
  end

  defp schedule_next_run() do
    now = DateTime.to_naive(Timex.local())
    cron_string = System.get_env("DIGEST_CRON", "30 7 * * *")
    cron = Crontab.CronExpression.Parser.parse!(cron_string)
    {:ok, date} = Crontab.Scheduler.get_next_run_date(cron, now)
    ms = NaiveDateTime.diff(date, now, :millisecond)
    Logger.info("Scheduling next run at #{NaiveDateTime.to_iso8601(date)}")
    Process.send_after(self(), :generate_book, ms)
  end

  defp get_text(content, selector, default) do
    with [node | _] <- Floki.find(content, selector) do
      Floki.text(node)
    else
      _ -> default
    end
  end

  defp fetch_article_contents(url) do
    with {:ok, resp} <- :httpc.request(:get, {url, []}, [], body_format: :binary),
         {{_, 200, _}, _headers, body} <- resp,
         {:ok, document} <- Floki.parse_document(body),
         [element | _] <- Floki.find(document, "article,.post") do
      {:ok, element}
    else
      err -> {:err, err}
    end
  end

  defp extract_images(base, content) do
    Floki.find_and_update([content], "img", fn
      {"img", attrs} ->
        {"src", src} =
          Enum.find(attrs, {"src", nil}, fn
            {"src", _src} -> true
            _ -> false
          end)

        with false <- is_nil(src),
             filename <- src |> URI.parse() |> Map.fetch!(:path) |> Path.basename(),
             {:ok, resp} <- :httpc.request(:get, {src, []}, [], body_format: :binary),
             {{_, 200, _}, _headers, body} <- resp,
             :ok <- File.write("#{base}/#{filename}", body) do
          {"img", [{"src", filename}]}
        else
          _ -> :delete
        end

      other ->
        other
    end)
  end

  defp build_page(html, id, title, author, publication) do
    """
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head>
        <title>#{id}</title>
        <meta content="application/xhtml+xml; charset=utf-8" http-equiv="Content-Type"/>
      </head>
      <body>
        <div class="body">
          <h1>#{publication} - #{title}</h1>
          <h3>#{author}</h3>
          #{html}
        </div>
      </body>
      </html>
    """
  end

  defp parse(content) do
    publication = get_text(content, "channel > title", "No title")

    last_run =
      DateTime.utc_now()
      |> DateTime.add(-1, :day)

    content
    |> Floki.find("item")
    |> Enum.filter(fn item ->
      with pub_date <- get_text(item, "pubdate", "Thu, 03 Apr 2025 14:00:09 +0000"),
           {:ok, date} <-
             Timex.parse(pub_date, "{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}") do
        DateTime.before?(last_run, date)
      else
        _ -> false
      end
    end)
    |> Enum.map(fn item ->
      title = get_text(item, "title", "No title")
      author = get_text(item, "creator,author", "No author")
      id = Slug.slugify(title)

      with url <- get_text(item, "link", nil),
           {:ok, content} <- fetch_article_contents(url),
           content <- extract_images("/tmp/daily/images", content),
           content <- Floki.filter_out(content, "script"),
           content <-
             Floki.traverse_and_update(content, fn
               {tag, attrs, children} ->
                 attrs =
                   Enum.filter(attrs, fn {name, _value} ->
                     name != "class"
                   end)

                 {tag, attrs, children}

               other ->
                 other
             end),
           html <- Floki.raw_html(content),
           page_content <- build_page(html, id, title, author, publication),
           path <- "/tmp/daily/#{id}.xhtml",
           :ok <- File.write!(path, page_content) do
        %BUPE.Item{
          id: id,
          description: title,
          href: path
        }
      else
        _ -> nil
      end
    end)
    |> Enum.filter(&(not is_nil(&1)))
  end

  defp parse_many(urls) do
    urls
    |> Enum.map(fn url ->
      with {:ok, resp} <- :httpc.request(:get, {url, []}, [], body_format: :binary),
           {{_, 200, _}, _headers, body} <- resp,
           {:ok, document} <- Floki.parse_document(body),
           items <- parse(document) do
        items
      else
        err ->
          Logger.error("Failed to handle feed #{url}", err)
          []
      end
    end)
    |> Enum.reduce([], &(&1 ++ &2))
  end

  defp fetch_feed() do
    urls =
      System.get_env("DAILY_URLS")
      |> String.split(",")

    {:ok, date} =
      Timex.local()
      |> Timex.format("{WDshort} {Mfull} {D} {YYYY}")

    title = "Daily Digest #{date}"
    slug = Slug.slugify(title)
    items = parse_many(urls)

    config = %BUPE.Config{
      title: title,
      language: "en",
      creator: "Matt Scandalis",
      publisher: "None",
      date: Timex.local(),
      unique_identifier: slug,
      pages: items,
      images: Path.wildcard("/tmp/daily/images/*")
    }

    epub = "/tmp/daily/#{slug}.epub"
    BUPE.Builder.run(config, epub)
    {_, 0} = System.cmd("calibredb", ["add", epub, System.get_env("CALIBRE_DB")])
    {:ok, _} = File.rm_rf("/tmp/daily")
  end
end
