defmodule AnkhTest do
  use ExUnit.Case

  alias AnkhTest.StreamGen

  doctest Ankh

  test "stream gen client works" do
    {:ok, stream_gen} = StreamGen.start_link(:client)
    assert 1 = StreamGen.next_stream_id(stream_gen)
    assert 3 = StreamGen.next_stream_id(stream_gen)
  end

  test "stream gen server works" do
    {:ok, stream_gen} = StreamGen.start_link(:server)
    assert 2 = StreamGen.next_stream_id(stream_gen)
    assert 4 = StreamGen.next_stream_id(stream_gen)
  end
end

defmodule AnkhTest.StreamGen do

  @values %{client: -1, server: 0}

  @doc """
  Init client or server stream number generator
  """
  @spec start_link(:client|:server) :: Agent.on_start
  def start_link(type), do: Agent.start_link(fn -> Map.get(@values, type) end)

  @doc """
  Get next stream id
  """
  def next_stream_id(bucket) do
    :ok = Agent.update(bucket, fn stream_id -> stream_id + 2 end)
    Agent.get(bucket, fn stream_id -> stream_id end)
  end
end
