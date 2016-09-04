defmodule Ankh.Frame.Encoder.Utils do
  def bool_to_int(true), do: 1
  def bool_to_int(false), do: 0
  def bool_to_int(_), do: raise ArgumentError

  def int_to_bool(1), do: true
  def int_to_bool(0), do: false
  def int_to_bool(_), do: raise ArgumentError

  def padding(n) when is_integer(n) and n > 0, do: :binary.copy(<<0>>, n)
end
