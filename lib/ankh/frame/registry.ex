defmodule Ankh.Frame.Registry do
  @moduledoc """
  Frame registry
  """

  alias Ankh.Frame.{Continuation, Data, GoAway, Headers, Ping, Priority,
  PushPromise, RstStream, Settings, WindowUpdate}

  @doc """
  Returns frame struct for the given HTTP/2 frame type code

  Codes 0-9 are reserved for standard frame types.
  """
  @spec struct_for_type(URI.t, Integer.t) :: Frame.t | nil
  def struct_for_type(_, 0x0), do: %Data{}
  def struct_for_type(_, 0x1), do: %Headers{}
  def struct_for_type(_, 0x2), do: %Priority{}
  def struct_for_type(_, 0x3), do: %RstStream{}
  def struct_for_type(_, 0x4), do: %Settings{}
  def struct_for_type(_, 0x5), do: %PushPromise{}
  def struct_for_type(_, 0x6), do: %Ping{}
  def struct_for_type(_, 0x7), do: %GoAway{}
  def struct_for_type(_, 0x8), do: %WindowUpdate{}
  def struct_for_type(_, 0x9), do: %Continuation{}
  def struct_for_type(%URI{} = uri, type) when is_integer(type)
  and type > 9 and type < 256 do
    Agent.get({:via, Registry, {__MODULE__, uri}}, &Map.get(&1, type))
  end


  @spec register(uri :: URI.t, type :: Integer.t, frame :: Frame.t) :: :ok
  def register(%URI{} = uri, type, frame)
  when is_integer(type) and type > 9 and type < 256 do
    Agent.update({:via, Registry, {__MODULE__, uri}}, &Map.put(&1, type, frame))
  end
end
