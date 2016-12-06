defmodule Ankh.Frame.Utils do
  @moduledoc """
  Utility functions for encoding/decoding values
  """

  @doc """
  Converts a boolean into the corresponding 0/1 integer values

  Raises on wrong arguments
  """
  @spec bool_to_int!(boolean) :: 0 | 1
  def bool_to_int!(false), do: 0
  def bool_to_int!(true), do: 1

  @doc """
  Converts 0/1 integers into the corresponding boolean values

  Raises on wrong arguments
  """
  @spec int_to_bool!(0 | 1) :: boolean
  def int_to_bool!(0), do: false
  def int_to_bool!(1), do: true

  @doc """
  Generates an 0 padding binary of the specified size
  """
  @spec padding(Integer.t) :: binary
  def padding(size) when is_integer(size) and size > 0 do
    :binary.copy(<<0>>, size)
  end
end
