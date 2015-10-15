# Copyright 2015 Serge Danzanvilliers <serge.danzanvilliers@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Feedistiller.Http do
  @moduledoc """
  HTTP wrappers to get feed content.
  """
  
  @vsn 3

  defmodule TimeoutError do
    defexception message: "Connection timeout"
  end
  
  @doc """
  Asynchronous get returning the body in chunks, with redirection handling
  (up to 5).
  A provided callback is called on each chunks in order with an accumulator.
  """
  @spec stream_get!(binary, fun, any, String.t, String.t) :: :ok
  def stream_get!(url, process_chunk, state, user, password) do
    stream_get!(url, process_chunk, state, 5, user, password)
  end

  @doc """
  Asynchronous get returning the body in chunks, with redirection handling
  (up to provided maximum redirections).
  A provided callback is called on each chunks in order with an accumulator.
  """
  @spec stream_get!(binary, fun, any, integer, String.t, String.t) :: :ok

  def stream_get!(_, _, _, -1, _, _) do
    raise :too_many_redirect
  end

  def stream_get!(url, process_chunk, state, max_redirect, user, password)
  when is_integer(max_redirect) and max_redirect >= 0
  do
    hackney = [follow_redirect: true]
    if user != "" or password != "" do
      hackney = [basic_auth: {user, password}] ++ hackney
    end
    HTTPoison.get!(url, [], [stream_to: self, hackney: hackney])
    stream_get_loop!(process_chunk, state, max_redirect, user, password)
  end

  @spec stream_get_loop!(fun, any, integer, String.t, String.t) :: {:ok, any}
  defp stream_get_loop!(p, s, r, u, pw) do
    receive do
      %HTTPoison.AsyncChunk{chunk: {:redirect, location, _headers}} ->
        stream_get!(location, p, s, r - 1, u, pw)
      %HTTPoison.AsyncChunk{chunk: chunk} -> 
        stream_get_loop!(p, p.(chunk, s), r, u, pw)
      %HTTPoison.AsyncEnd{} -> {:ok, s}
      _ -> stream_get_loop!(p, s, r, u, pw)
    after
      # no response for a long time, just give up
      120_000 -> raise TimeoutError
    end
  end
end
