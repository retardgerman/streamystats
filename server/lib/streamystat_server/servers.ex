defmodule StreamystatServer.Servers do
  import Ecto.Query, warn: false
  alias StreamystatServer.Repo
  alias StreamystatServer.Servers.Server
  alias HTTPoison

  def list_servers do
    Repo.all(Server)
  end

  def get_server(id), do: Repo.get(Server, id)

  def create_server(attrs \\ %{}) do
    case verify_and_get_server_info(attrs) do
      {:ok, server_info} ->
        attrs = Map.merge(attrs, server_info)
        do_create_server(attrs)

      {:error, :missing_url} ->
        changeset = Server.changeset(%Server{}, %{})
        {:error, Ecto.Changeset.add_error(changeset, :url, "is required")}

      {:error, reason} ->
        changeset = Server.changeset(%Server{}, %{})
        {:error, Ecto.Changeset.add_error(changeset, :base, to_string(reason))}
    end
  end

  defp verify_and_get_server_info(%{"url" => url}) when is_binary(url) and byte_size(url) > 0 do
    case HTTPoison.get("#{url}/System/Info/Public") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, server_info} ->
            {:ok,
             %{
               "local_address" => server_info["LocalAddress"],
               "name" => server_info["ServerName"],
               "version" => server_info["Version"],
               "product_name" => server_info["ProductName"],
               "operating_system" => server_info["OperatingSystem"],
               "jellyfin_id" => server_info["Id"],
               "startup_wizard_completed" => server_info["StartupWizardCompleted"]
             }}

          {:error, _} ->
            {:error, :invalid_json}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :server_not_found}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp verify_and_get_server_info(_), do: {:error, :missing_url}

  defp do_create_server(attrs) do
    %Server{}
    |> Server.changeset(attrs)
    |> Repo.insert()
  end

  def update_server(%Server{} = server, attrs) do
    server
    |> Server.changeset(attrs)
    |> Repo.update()
  end

  def delete_server(%Server{} = server) do
    Repo.delete(server)
  end
end
