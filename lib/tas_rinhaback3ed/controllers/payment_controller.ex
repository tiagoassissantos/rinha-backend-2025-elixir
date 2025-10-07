defmodule TasRinhaback3ed.Controllers.PaymentController do
  @moduledoc """
  Documentation for TasRinhaback3ed.Controllers.PaymentController.
  """

  require Logger
  alias TasRinhaback3ed.Services.PaymentQueue
  alias TasRinhaback3ed.Services.Transactions

  # Prebuild static responses to avoid allocations
  @empty_response_204 ""

  @queue_full_response_iodata Jason.encode_to_iodata!(%{error: "queue_full"})
  @invalid_request_response_iodata Jason.encode_to_iodata!(%{error: "invalid_request"})

  def payments(conn, params) do
    # Enqueue with back-pressure handling
    start_time = System.monotonic_time(:millisecond)

    case PaymentQueue.enqueue(params) do
      :ok ->
        end_time = System.monotonic_time(:millisecond)
        elapsed_time = end_time - start_time
        Logger.info(";#{inspect(Map.get(params, "correlationId"))}; Request processed in #{elapsed_time}")
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(204, @empty_response_204)

      {:error, :queue_full} ->
        send_json_iodata(conn, 503, @queue_full_response_iodata)
    end
  end

  def payments_summary(conn, %{"from" => from_str, "to" => to_str})
      when is_binary(from_str) and is_binary(to_str) do
    Logger.debug("Received payment summary request from #{from_str} to #{to_str}")
    with {:ok, from_dt} <- parse_iso8601(from_str),
         {:ok, to_dt} <- parse_iso8601(to_str) do
      Logger.debug("Parsed dates successfully: #{from_dt} to #{to_dt}")
      case Transactions.summary(from_dt, to_dt) do
        {:ok, result} ->
          Logger.debug("Payment summary result: #{inspect(result)}")
          response_iodata = result |> normalize_amounts() |> Jason.encode_to_iodata!()
          send_json_iodata(conn, 200, response_iodata)

        {:error, :unavailable} ->
          Logger.error("Payment summary unavailable")
          # Prebuild fallback response to avoid allocations
          response_iodata =
            Jason.encode_to_iodata!(%{
              default: %{
                totalRequests: 0,
                totalAmount: 0
              },
              fallback: %{
                totalRequests: 0,
                totalAmount: 0
              }
            })

          send_json_iodata(conn, 200, response_iodata)
      end
    else
      {:error, _} ->
        send_json_iodata(conn, 400, @invalid_request_response_iodata)
    end
  end

  def payments_summary(conn, _params) do
    send_json_iodata(conn, 400, @invalid_request_response_iodata)
  end

  # Fast JSON response helper using iodata
  defp send_json_iodata(conn, status, iodata) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, iodata)
  end

  # Ensure numbers are JSON-friendly floats
  defp normalize_amounts(%{default: d, fallback: f}) do
    %{
      default: %{totalRequests: d.totalRequests, totalAmount: to_float(d.totalAmount)},
      fallback: %{totalRequests: f.totalRequests, totalAmount: to_float(f.totalAmount)}
    }
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(v) when is_number(v), do: v

  # Optimized ISO8601 parsing without error details for speed
  defp parse_iso8601(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      _ -> {:error, :invalid}
    end
  end
end
