defmodule Chatgpt.Drive do
  alias GoogleApi.Drive.V3.Connection
  alias GoogleApi.Drive.V3.Api.Files
  require Logger

  def list_files(token) do
    conn = Connection.new(token)

    params = [
      pageSize: 1000,
      fields: "files(id,name,mimeType,modifiedTime)",
      # Add this line
      q: "mimeType != 'application/vnd.google-apps.folder'"
    ]

    case Files.drive_files_list(conn, params) do
      {:ok, %GoogleApi.Drive.V3.Model.FileList{files: files}} ->
        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def search_files(token, query) do
    conn = Connection.new(token)

    params = [
      q:
        "name contains '#{String.replace(query, "'", "\\'")}' and mimeType != 'application/vnd.google-apps.folder'",
      pageSize: 100,
      fields: "files(id,name,mimeType,modifiedTime)"
    ]

    case Files.drive_files_list(conn, params) do
      {:ok, %GoogleApi.Drive.V3.Model.FileList{files: files}} ->
        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_file_info_and_content(token, file_id) do
    conn = Connection.new(token)

    with {:ok, file} <- Files.drive_files_get(conn, file_id),
         {:ok, content} <- get_file_content(conn, file) do
      {:ok, file, content}
    else
      {:error, reason} ->
        Logger.error(
          "Error getting file info and content for file_id: #{file_id}. Reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp get_file_content(conn, file) do
    case file.mimeType do
      "application/vnd.google-apps.document" ->
        Files.drive_files_export(conn, file.id, "text/plain")

      "application/vnd.google-apps.spreadsheet" ->
        Files.drive_files_export(conn, file.id, "text/csv")

      "application/vnd.google-apps.presentation" ->
        Files.drive_files_export(conn, file.id, "text/plain")

      _ ->
        Files.drive_files_get(conn, file.id, alt: "media")
    end
    |> case do
      {:ok, %Tesla.Env{body: content}} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end
end
