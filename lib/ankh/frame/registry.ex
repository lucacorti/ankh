defmodule Ankh.Frame.Registry do
  @moduledoc """
  Frame registry
  """

  alias Ankh.Frame.{Continuation, Data, Goaway, Headers, Ping, Priority,
  PushPromise, RstStream, Settings, WindowUpdate}

  @doc """
  Returns frame struct for the given HTTP/2 frame type code

  Codes 0-9 are reserved for standard frame types.
  """
  @spec struct_for_type(Integer.t) :: Frame.t
  def struct_for_type(0x0), do: %Data{}
  def struct_for_type(0x1), do: %Headers{}
  def struct_for_type(0x2), do: %Priority{}
  def struct_for_type(0x3), do: %RstStream{}
  def struct_for_type(0x4), do: %Settings{}
  def struct_for_type(0x5), do: %PushPromise{}
  def struct_for_type(0x6), do: %Ping{}
  def struct_for_type(0x7), do: %Goaway{}
  def struct_for_type(0x8), do: %WindowUpdate{}
  def struct_for_type(0x9), do: %Continuation{}
end
