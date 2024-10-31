defmodule StreamystatServer.Auth do
  alias StreamystatServer.Servers.Server
  alias StreamystatServer.HttpClient
  require Logger

  def authenticate_user(%Server{} = server, username, password) do
    url = "#{server.url}/Users/AuthenticateByName"
    body = Jason.encode!(%{Username: username, Pw: password})

    headers = [
      {"Content-Type", "application/json"},
      {"X-Emby-Authorization", generate_emby_authorization_header()}
    ]

    Logger.debug("Authenticating user: #{username} with server: #{server.url}")

    case HttpClient.post(url, body, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, parsed_body} = Jason.decode(response_body)
        access_token = Map.get(parsed_body, "AccessToken")
        user = Map.get(parsed_body, "User")
        Logger.debug("Authentication successful. Access token: #{access_token}")
        {:ok, %{access_token: access_token, user: user}}

      {:ok, %{status_code: status_code}} ->
        Logger.error("Authentication failed with status code: #{status_code}")
        {:error, "Authentication failed with status code: #{status_code}"}

      {:error, reason} ->
        Logger.error("Authentication request failed: #{inspect(reason)}")
        {:error, "Authentication request failed: #{inspect(reason)}"}
    end
  end

  def verify_token(%Server{} = server, token) do
    url = "#{server.url}/Users/Me"

    headers = [
      {"X-Emby-Token", token},
      {"Content-Type", "application/json"}
    ]

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, parsed_body} = Jason.decode(response_body)
        user_id = Map.get(parsed_body, "Id")
        {:ok, user_id}

      {:ok, %{status_code: 401}} ->
        {:error, "Invalid token"}

      {:ok, %{status_code: status_code}} ->
        {:error, "Token verification failed with status code: #{status_code}"}

      {:error, reason} ->
        {:error, "Token verification request failed: #{inspect(reason)}"}
    end
  end

  def get_user_info(%Server{} = server, user_id) do
    url = "#{server.url}/Users/#{user_id}"

    headers = [
      {"X-Emby-Token", server.api_key},
      {"Content-Type", "application/json"}
    ]

    Logger.debug("Fetching user info from server: #{server.url}")

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        Logger.debug("User info fetch successful. Response body: #{inspect(response_body)}")
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: status_code}} ->
        Logger.error("User info fetch failed with status code: #{status_code}")
        {:error, "Failed to fetch user info with status code: #{status_code}"}

      {:error, reason} ->
        Logger.error("User info fetch request failed: #{inspect(reason)}")
        {:error, "User info fetch request failed: #{inspect(reason)}"}
    end
  end

  defp generate_emby_authorization_header do
    client = "StreamystatServer"
    device = "Server"
    device_id = generate_device_id()
    # Replace with your actual version
    version = "1.0.0"

    "MediaBrowser " <>
      "Client=\"#{client}\", " <>
      "Device=\"#{device}\", " <>
      "DeviceId=\"#{device_id}\", " <>
      "Version=\"#{version}\""
  end

  defp generate_device_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
