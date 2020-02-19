defmodule Ankh.Protocol do
  @moduledoc """
  Transport behavior
  """
  alias Ankh.Transport
  alias Ankh.HTTP.{Request, Response}

  @type t :: any()

  @doc """
  Creates a new connection
  """
  @callback new(keyword) :: t()

  @doc """
  Accepts a client connection
  """
  @callback accept(t(), URI.t(), Transport.t(), Transport.options()) ::
              {:ok, t()} | {:error, any()}

  @doc """
  Connects to an host
  """
  @callback connect(t(), URI.t(), Transport.options()) :: {:ok, t()} | {:error, any()}

  @doc """
  Sends a request
  """
  @callback request(t(), Request.t()) :: {:ok, t(), reference()} | {:error, any()}

  @doc """
  Sends a response
  """
  @callback respond(t(), reference(), Response.t()) :: {:ok, t()} | {:error, any()}

  @doc """
  Closes the connection
  """
  @callback close(t()) :: :ok | {:error, any()}

  @doc """
  Handles transport messages
  """
  @callback stream(t(), any()) :: {:ok, binary, t()} | {:error, any()}
end
