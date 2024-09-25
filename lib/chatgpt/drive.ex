defmodule Chatgpt.Drive do
  alias GoogleApi.Drive.V3.Connection
  alias GoogleApi.Drive.V3.Api.Files

  def list_files(token) do
    conn = Connection.new(token)

    params = [
      pageSize: 1000,
      fields: "files(id,name,mimeType,modifiedTime)"
    ]

    case Files.drive_files_list(conn, params) do
      {:ok, %GoogleApi.Drive.V3.Model.FileList{files: files}} ->
        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
