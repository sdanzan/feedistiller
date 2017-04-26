defmodule Feedistiller.Http.Test do
  use ExUnit.Case, async: false
  import Mock
  doctest Feedistiller.Http

  alias Feedistiller.Http

  test "stream_get!/6" do
    with_mock HTTPoison, [get!: fn
        (_url, [], [stream_to: _, hackney: _]) ->
          data = "DATA"
          send(self(), %HTTPoison.AsyncStatus{code: 200, id: Kernel.make_ref()})
          send(self(), %HTTPoison.AsyncHeaders{})
          send(self(), %HTTPoison.AsyncChunk{chunk: data})
          send(self(), %HTTPoison.AsyncEnd{})
    end] do
      {:ok, data} = Http.stream_get!(
        "url",
        fn (chunk, acc) -> acc <> chunk end,
        <<>>,
        60, "user", "password")

      assert data == "DATA"
    end
  end

  test "stream_get!/6 timeout" do
    with_mock HTTPoison, [get!: fn
        (_url, [], [stream_to: _, hackney: _]) ->
          send(self(), %HTTPoison.AsyncStatus{code: 200})
    end] do
      assert_raise Http.TimeoutError, fn -> Http.stream_get!(
        "url",
        fn (chunk, acc) -> acc <> chunk end,
        <<>>,
        1, "user", "password")
      end
    end
  end

  test "stream_get!/6 with redirect" do
    with_mock HTTPoison, [get!: fn
        ("url", [], [stream_to: _, hackney: _]) ->
          send(self(), %HTTPoison.AsyncRedirect{to: "url2"})
        ("url2", [], [stream_to: _, hackney: _]) ->
          data = "DATA"
          send(self(), %HTTPoison.AsyncChunk{chunk: data})
          send(self(), %HTTPoison.AsyncEnd{})
    end] do
      {:ok, data} = Http.stream_get!(
        "url",
        fn (chunk, acc) -> acc <> chunk end,
        <<>>,
        60, "user", "password")

      assert data == "DATA"
    end
  end

  test "stream_get!/7 with too many redirect" do
    with_mock HTTPoison, [get!: fn
        ("url", [], [stream_to: _, hackney: _]) ->
          send(self(), %HTTPoison.AsyncRedirect{to: "url2"})
        ("url2", [], [stream_to: _, hackney: _]) ->
          data = "DATA"
          send(self(), %HTTPoison.AsyncChunk{chunk: data})
          send(self(), %HTTPoison.AsyncEnd{})
    end] do
      assert_raise Http.TooManyRedirectError, fn -> Http.stream_get!(
        "url",
        fn (chunk, acc) -> acc <> chunk end,
        <<>>,
        60, 0, "user", "password")
      end
    end
  end
end
