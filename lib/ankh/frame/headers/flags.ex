defmodule Ankh.Frame.Headers.Flags do
  @moduledoc false

  @type t :: %__MODULE__{
          end_stream: boolean,
          end_headers: boolean,
          padded: boolean,
          priority: boolean
        }
  defstruct end_stream: false, end_headers: false, padded: false, priority: false
end

defimpl Ankh.Frame.Flags, for: Ankh.Frame.Headers.Flags do
  import Ankh.Frame.Utils

  def decode!(flags, <<_::2, pr::1, _::1, pa::1, eh::1, _::1, es::1>>, _) do
    %{
      flags
      | end_stream: int_to_bool!(es),
        end_headers: int_to_bool!(eh),
        padded: int_to_bool!(pa),
        priority: int_to_bool!(pr)
    }
  end

  def encode!(%{end_stream: es, end_headers: eh, padded: pa, priority: pr}, _) do
    <<0::2, bool_to_int!(pr)::1, 0::1, bool_to_int!(pa)::1, bool_to_int!(eh)::1, 0::1,
      bool_to_int!(es)::1>>
  end
end
