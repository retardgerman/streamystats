defmodule StreamystatServer.Statistics do
  import Ecto.Query, warn: false
  alias StreamystatServer.Jellyfin.PlaybackActivity
  alias StreamystatServer.Jellyfin.Item
  alias StreamystatServer.Jellyfin.Library
  alias StreamystatServer.Jellyfin.User
  alias StreamystatServer.Repo
  require Logger

  def create_playback_stat(attrs \\ %{}) do
    %PlaybackActivity{}
    |> PlaybackActivity.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, stat} ->
        {:ok, stat}

      {:error, changeset} ->
        Logger.warning("Failed to create playback stat: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def get_formatted_stats(start_date, end_date, server_id, user_id \\ nil) do
    stats = get_stats(start_date, end_date, server_id, user_id)

    %{
      most_watched_items: get_top_watched_items(stats),
      watchtime_per_day: get_watchtime_per_day(stats),
      average_watchtime_per_week_day: get_average_watchtime_per_week_day(stats),
      total_watch_time: get_total_watch_time(stats)
    }
  end

  def get_library_statistics(server_id) do
    %{
      movies_count:
        Repo.one(
          from(i in Item, where: i.server_id == ^server_id and i.type == "Movie", select: count())
        ),
      episodes_count:
        Repo.one(
          from(i in Item,
            where: i.server_id == ^server_id and i.type == "Episode",
            select: count()
          )
        ),
      series_count:
        Repo.one(
          from(i in Item,
            where: i.server_id == ^server_id and i.type == "Series",
            select: count()
          )
        ),
      libraries_count:
        Repo.one(from(l in Library, where: l.server_id == ^server_id, select: count())),
      users_count: Repo.one(from(u in User, where: u.server_id == ^server_id, select: count()))
    }
  end

  def get_item_statistics(
        server_id,
        page \\ 1,
        search \\ nil,
        sort_by \\ :total_watch_time,
        sort_order \\ :desc
      ) do
    per_page = 20

    # Validate and normalize sort parameters
    sort_by =
      case sort_by do
        :watch_count -> :watch_count
        :total_watch_time -> :total_watch_time
        _ -> :total_watch_time
      end

    sort_order =
      case sort_order do
        :asc -> :asc
        :desc -> :desc
        _ -> :desc
      end

    # Base query for items of type "Movie" and "Episode"
    base_query =
      from(i in Item,
        left_join: pa in PlaybackActivity,
        on: pa.item_id == i.jellyfin_id and pa.server_id == i.server_id,
        where: i.server_id == ^server_id and i.type in ["Movie", "Episode"],
        group_by: [i.id, i.jellyfin_id, i.name, i.type],
        select: %{
          item_id: i.jellyfin_id,
          item: i,
          watch_count: coalesce(count(pa.id), 0),
          total_watch_time: coalesce(sum(pa.play_duration), 0)
        }
      )

    # Apply search filter if provided
    query =
      if search do
        search_term = "%#{search}%"

        where(
          base_query,
          [i, pa],
          ilike(i.name, ^search_term) or
            ilike(fragment("?::text", i.production_year), ^search_term) or
            ilike(i.season_name, ^search_term) or
            ilike(i.series_name, ^search_term)
        )
      else
        base_query
      end

    # Apply sorting
    query =
      case {sort_by, sort_order} do
        {:watch_count, :asc} ->
          order_by(query, [i, pa], asc: coalesce(count(pa.id), 0))

        {:watch_count, :desc} ->
          order_by(query, [i, pa], desc: coalesce(count(pa.id), 0))

        {:total_watch_time, :asc} ->
          order_by(query, [i, pa], asc: coalesce(sum(pa.play_duration), 0))

        {:total_watch_time, :desc} ->
          order_by(query, [i, pa], desc: coalesce(sum(pa.play_duration), 0))
      end

    # Paginate items
    offset = (page - 1) * per_page

    items =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Count total items
    total_items_query =
      from(i in Item,
        where: i.server_id == ^server_id and i.type in ["Movie", "Episode"],
        select: i.id
      )

    # Apply the same search filter to the count query
    total_items_query =
      if search do
        search_term = "%#{search}%"

        where(
          total_items_query,
          [i],
          ilike(i.name, ^search_term) or
            ilike(fragment("?::text", i.production_year), ^search_term) or
            ilike(i.season_name, ^search_term) or
            ilike(i.series_name, ^search_term)
        )
      else
        total_items_query
      end

    # Fetch total item count
    total_items = total_items_query |> Repo.aggregate(:count, :id)
    total_pages = div(total_items + per_page - 1, per_page)

    %{
      items: items,
      page: page,
      per_page: per_page,
      total_items: total_items,
      total_pages: total_pages,
      sort_by: sort_by,
      sort_order: sort_order
    }
  end

  defp get_stats(start_date, end_date, server_id, user_id) do
    start_datetime = to_naive_datetime(start_date)
    end_datetime = to_naive_datetime(end_date, :end_of_day)

    query =
      from(pa in PlaybackActivity,
        join: i in StreamystatServer.Jellyfin.Item,
        on: pa.item_id == i.jellyfin_id,
        where: pa.date_created >= ^start_datetime and pa.date_created <= ^end_datetime,
        order_by: [asc: pa.date_created],
        preload: [:user],
        select: %{
          date_created: pa.date_created,
          item_id: i.jellyfin_id,
          item: i,
          user_id: pa.user_id,
          play_duration: pa.play_duration,
          playback_activity: pa
        }
      )

    query = if server_id, do: query |> where([pa], pa.server_id == ^server_id), else: query
    query = if user_id, do: query |> where([pa], pa.user_id == ^user_id), else: query

    Repo.all(query)
  end

  defp to_naive_datetime(date, time \\ :beginning_of_day) do
    date
    |> DateTime.new!(Time.new!(0, 0, 0), "Etc/UTC")
    |> DateTime.to_naive()
    |> then(fn
      naive_dt when time == :end_of_day -> NaiveDateTime.add(naive_dt, 86399, :second)
      naive_dt -> naive_dt
    end)
  end

  defp get_total_watch_time(stats) do
    stats
    |> Enum.reduce(0, fn stat, acc ->
      acc + (stat.play_duration || 0)
    end)
  end

  defp get_top_watched_items(stats) do
    alias StreamystatServer.Jellyfin.Item
    alias StreamystatServer.Repo
    import Ecto.Query

    stats
    |> Enum.group_by(& &1.item.type)
    |> Enum.map(fn {item_type, type_stats} ->
      top_items =
        type_stats
        |> Enum.group_by(& &1.item_id)
        |> Enum.map(fn {item_id, items} ->
          total_play_count = length(items)
          total_play_duration = Enum.sum(Enum.map(items, & &1.play_duration))

          item_query =
            from(i in Item,
              where: i.jellyfin_id == ^item_id,
              select: %{
                id: i.id,
                name: i.name,
                type: i.type,
                production_year: i.production_year,
                series_name: i.series_name,
                season_name: i.season_name,
                index_number: i.index_number,
                jellyfin_id: i.jellyfin_id
              }
            )

          item_data = Repo.one(item_query)

          Map.merge(item_data, %{
            total_play_count: total_play_count,
            total_play_duration: total_play_duration
          })
        end)
        |> Enum.sort_by(& &1.total_play_duration, :desc)
        |> Enum.take(10)

      {item_type, top_items}
    end)
    |> Enum.into(%{})
  end

  defp get_watchtime_per_day([]), do: []

  defp get_watchtime_per_day(stats) do
    stats
    |> Enum.group_by(
      fn stat -> {NaiveDateTime.to_date(stat.date_created), stat.item.type} end,
      fn stat -> stat.play_duration || 0 end
    )
    |> Enum.map(fn {{date, item_type}, durations} ->
      %{
        date: Date.to_iso8601(date),
        item_type: item_type,
        total_duration: Enum.sum(durations)
      }
    end)
    |> Enum.group_by(& &1.date)
    |> Enum.map(fn {date, items} ->
      %{
        date: date,
        watchtime_by_type:
          Enum.map(items, fn item ->
            %{
              item_type: item.item_type,
              total_duration: item.total_duration
            }
          end)
      }
    end)
    |> Enum.sort_by(& &1.date)
  end

  defp get_average_watchtime_per_week_day(stats) do
    stats
    |> Enum.group_by(&Date.day_of_week(NaiveDateTime.to_date(&1.date_created)))
    |> Enum.map(fn {day_of_week, items} ->
      total_duration = Enum.sum(Enum.map(items, &(&1.play_duration || 0)))
      average_duration = total_duration / length(items)

      %{
        day_of_week: day_of_week,
        average_duration: Float.round(average_duration, 2)
      }
    end)
    |> Enum.sort_by(& &1.day_of_week)
  end
end
