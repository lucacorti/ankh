defmodule Ankh do
  @moduledoc """
  Pure Elixir HTTP/2 implementation

  This library provides HTTP/2 (https://tools.ietf.org/html/rfc7540)
  connection management and frame (de)serialization facilities.
  The aim is to provide a solid foundation upon which clients and
  eventually servers can be implemented providing higher layer features.

  Ankh only supports HTTP/2 over TLS. Support for HTTP/2 over plaintext
  TCP was intentionally left out.
  """

  use Application

  @doc false
  def start(_type, _args), do: Ankh.Supervisor.start_link()
end
