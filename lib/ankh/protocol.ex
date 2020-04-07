defmodule Ankh.Protocol do
  @moduledoc """
  Protocol behavior
  """
  alias Ankh.Transport
  alias Ankh.HTTP.{Request, Response}

  @typedoc "Ankh protocol"
  @type t :: any()

  @typedoc "Protocol options"
  @type options :: Keyword.t()

  @typedoc "Request reference"
  @type request_ref :: reference()

  @doc """
  Accepts a client connection
  """
  @callback accept(t(), URI.t(), Transport.t(), Transport.options()) ::
              {:ok, t()} | {:error, any()}

  @doc """
  Closes the connection
  """
  @callback close(t()) :: :ok | {:error, any()}

  @doc """
  Connects to an host
  """
  @callback connect(t(), URI.t(), Transport.options()) :: {:ok, t()} | {:error, any()}

  @doc """
  Reports a connection error
  """
  @callback error(t()) :: {:ok, t()}

  @doc """
  Creates a new connection
  """
  @callback new(options()) :: t()

  @doc """
  Sends a request
  """
  @callback request(t(), Request.t()) :: {:ok, t(), request_ref()} | {:error, any()}

  @doc """
  Sends a response
  """
  @callback respond(t(), request_ref(), Response.t()) :: {:ok, t()} | {:error, any()}

  @doc """
  Handles transport messages
  """
  @callback stream(t(), any()) :: {:ok, binary, t()} | {:error, any()}
end
