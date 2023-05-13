defmodule Ankh.HTTP.Error do
  @moduledoc "HTTP Error"

  errors = [
    {:no_error, "Graceful shutdown"},
    {:protocol_error, "Protocol error detected"},
    {:internal_error, "Implementation fault"},
    {:flow_control_error, "Flow-control limits exceeded"},
    {:settings_timeout, "Settings not acknowledged"},
    {:stream_closed, "Frame received for closed stream"},
    {:frame_size_error, "Frame size incorrect"},
    {:refused_stream, "Stream not processed"},
    {:cancel, "Stream cancelled"},
    {:compression_error, "Compression state not updated"},
    {:connect_error, "TCP connection error for CONNECT method"},
    {:enanche_your_calm, "Processing capacity exceeded"},
    {:inadequate_security, "Negotiated TLS parameters not acceptable"},
    {:http_1_1_required, "Use HTTP/1.1 for the request"}
  ]

  @typedoc "HTTP/2 Error"
  @type reason ::
          unquote(
            Enum.map_join(errors, " | ", &inspect(elem(&1, 0)))
            |> Code.string_to_quoted!()
          )

  @doc """
  Returns a human readable string for the corresponding error code atom
  """
  @spec format(reason()) :: String.t()
  for {reason, message} <- errors do
    def format(unquote(reason)), do: unquote(message)
  end
end
