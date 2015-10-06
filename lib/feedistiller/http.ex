defmodule Feedistiller.Http do
  @moduledoc """
  HTTP wrappers to get feed content.
  """
  
  @vsn 1
  
  @doc """
  Synchronous get returning the full response body. Redirection is
  handled automatically.
  """
  @spec full_get!(String.t) :: binary
  def full_get!(url) do
    %HTTPoison.Response{body: body} = HTTPoison.get! url, [], [hackney: [follow_redirect: true]]
    body
  end

  @doc """
  Asynchronous get returning the body in chunks, with redirection handling
  (up to 5).
  A provided callback is called on each chunks in order with an accumulator.
  """
  @spec stream_get!(binary, fun, any) :: :ok
  def stream_get!(url, process_chunk, state) do
    stream_get!(url, process_chunk, state, 5)
  end

  @doc """
  Asynchronous get returning the body in chunks, with redirection handling
  (up to provided maximum redirections).
  A provided callback is called on each chunks in order with an accumulator.
  """
  @spec stream_get!(binary, fun, any, integer) :: :ok

  def stream_get!(_, _, _, -1) do
    raise :too_many_redirect
  end

  def stream_get!(url, process_chunk, state, max_redirect)
  when is_integer(max_redirect) and max_redirect >= 0
  do
    HTTPoison.get! url, [], [stream_to: self, hackney: [follow_redirect: true]]
    stream_get_loop!(process_chunk, state, max_redirect)
  end

  @spec stream_get_loop!(fun, any, integer) :: {:ok, any}
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
