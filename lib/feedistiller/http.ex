defmodule Feedistiller.Http do
  # Synchronous get (the full body is returned) with redirection handling.
  @spec full_get!(String.t) :: binary
  def full_get!(url) do
    %HTTPoison.Response{body: body} = HTTPoison.get! url, [], [hackney: [follow_redirect: true]]
    body
  end

  # Asynchronous get (body is returned in chunks) with redirection handling.
  # `process_chunk` is called on each chunks.

  def stream_get!(url, process_chunk, state) do
    stream_get!(url, process_chunk, state, 5)
  end

  def stream_get!(_, _, _, 0) do
    raise :too_many_redirect
  end

  def stream_get!(url, process_chunk, state, max_redirect) do
    HTTPoison.get! url, [], [stream_to: self, hackney: [follow_redirect: true]]
    stream_get_loop!(process_chunk, state, max_redirect)
  end

  defp stream_get_loop!(p, s, r) do
    receive do
      %HTTPoison.AsyncChunk{chunk: {:redirect, location, _headers}} ->
        stream_get!(location, p, s, r - 1)
      %HTTPoison.AsyncChunk{chunk: chunk} -> stream_get_loop!(p, p.(chunk, s), r)
      %HTTPoison.AsyncEnd{} -> {:ok, s}
      _ -> stream_get_loop!(p, s, r)
    after
      # no response for a long time, just give up
      60_000 -> raise :connection_timeout
    end
  end
end
