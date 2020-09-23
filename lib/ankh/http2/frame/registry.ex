defmodule Ankh.HTTP2.Frame.Registry do
  @moduledoc """
  Frame registry
  """

  alias Ankh.HTTP2.Frame

  alias Ankh.HTTP2.Frame.{
    Continuation,
    Data,
    GoAway,
    Headers,
    Ping,
    Priority,
    PushPromise,
    RstStream,
    Settings,
    WindowUpdate
  }

  alias Ankh.Protocol

  @doc """
  Returns frame struct for the given HTTP/2 frame type code

  Codes 0-9 are reserved for standard frame types.
  """
  @spec frame_for_type(Protocol.t(), Frame.type()) :: {:ok, Frame.t()} | {:error, :not_found}
  def frame_for_type(_protocol, 0x0), do: {:ok, %Data{}}
  def frame_for_type(_protocol, 0x1), do: {:ok, %Headers{}}
  def frame_for_type(_protocol, 0x2), do: {:ok, %Priority{}}
  def frame_for_type(_protocol, 0x3), do: {:ok, %RstStream{}}
  def frame_for_type(_protocol, 0x4), do: {:ok, %Settings{}}
  def frame_for_type(_protocol, 0x5), do: {:ok, %PushPromise{}}
  def frame_for_type(_protocol, 0x6), do: {:ok, %Ping{}}
  def frame_for_type(_protocol, 0x7), do: {:ok, %GoAway{}}
  def frame_for_type(_protocol, 0x8), do: {:ok, %WindowUpdate{}}
  def frame_for_type(_protocol, 0x9), do: {:ok, %Continuation{}}
  def frame_for_type(_protocol, _type), do: {:error, :not_found}
end
