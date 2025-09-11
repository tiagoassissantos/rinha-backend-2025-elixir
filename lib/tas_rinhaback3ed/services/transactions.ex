defmodule TasRinhaback3ed.Services.Transactions do
  @moduledoc """
  Inserts and aggregates payment transactions.

  - `store_success/2` is best-effort: if Repo isn't started or DB is down, it logs and returns :ok.
  - `summary/2` returns aggregated counts and sums by route for a datetime range.
  """

  require Logger
  import Ecto.Query

  alias TasRinhaback3ed.Repo
  alias TasRinhaback3ed.Payments.Transaction

  @spec repo_available?() :: boolean()
  def repo_available? do
    Process.whereis(Repo) != nil
  end

  @doc """
  Persist a successful transaction. Route is "default" or "fallback".
  """
  @spec store_success(map(), String.t()) :: :ok
  def store_success(params, route) when route in ["default", "fallback"] do
    if repo_available?() do
      attrs = %{
        correlation_id: Map.get(params, "correlationId"),
        amount: cast_decimal(Map.get(params, "amount")),
        inserted_at: Map.get(params, "requestedAt"),
        route: route
      }

      changeset = Transaction.changeset(%Transaction{}, attrs)

      case Repo.insert(changeset) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          Logger.warning("Failed to insert transaction: #{inspect(changeset.errors)}")
          :ok
      end
    else
      :ok
    end
  rescue
    e ->
      Logger.warning("Error persisting transaction: #{Exception.message(e)}")
      :ok
  end

  @doc """
  Compute summary for [from, to) range.

  Returns `%{default: %{totalRequests, totalAmount}, fallback: %{...}}`.
  If Repo is unavailable, returns `{:error, :unavailable}`.
  """
  @spec summary(DateTime.t(), DateTime.t()) ::
          {:ok,
           %{
             default: %{totalRequests: non_neg_integer(), totalAmount: float()},
             fallback: %{totalRequests: non_neg_integer(), totalAmount: float()}
           }}
          | {:error, :unavailable}
  def summary(%DateTime{} = from_dt, %DateTime{} = to_dt) do
    if repo_available?() do
      q =
        from(t in Transaction,
          where: t.inserted_at >= ^from_dt and t.inserted_at < ^to_dt,
          group_by: t.route,
          select: {t.route, count(t.id), sum(t.amount)}
        )

      rows = Repo.all(q)

      acc = %{
        "default" => %{totalRequests: 0, totalAmount: 0.0},
        "fallback" => %{totalRequests: 0, totalAmount: 0.0}
      }

      result =
        Enum.reduce(rows, acc, fn {route, count, sum}, acc ->
          sum_float =
            case sum do
              nil -> 0.0
              %Decimal{} = d -> Decimal.to_float(d)
              other -> other
            end

          Map.update!(acc, route, fn _ -> %{totalRequests: count, totalAmount: sum_float} end)
        end)

      {:ok,
       %{
         default: result["default"],
         fallback: result["fallback"]
       }}
    else
      {:error, :unavailable}
    end
  end

  @doc """
  Update an existing transaction by `correlation_id`.

  Accepts a map with optional keys `"amount"`/`:amount` and `"route"`/`:route`.
  Returns `{:ok, %Transaction{}}` on success, `{:error, :not_found}` when the
  transaction doesn't exist, or `{:error, term}` for validation/unavailability errors.
  """
  @spec update_transaction(String.t(), map()) ::
          {:ok, Transaction.t()} | {:error, :not_found} | {:error, term()}
  def update_transaction(correlation_id, attrs)
      when is_binary(correlation_id) and is_map(attrs) do
    if repo_available?() do
      case Repo.get_by(Transaction, correlation_id: correlation_id) do
        nil ->
          {:error, :not_found}

        %Transaction{} = tx ->
          update_attrs = %{}

          update_attrs =
            case fetch_key(attrs, "amount", :amount) do
              {:ok, v} -> Map.put(update_attrs, :amount, cast_decimal(v))
              :error -> update_attrs
            end

          update_attrs =
            case fetch_key(attrs, "route", :route) do
              {:ok, v} -> Map.put(update_attrs, :route, v)
              :error -> update_attrs
            end

          tx
          |> Transaction.changeset(update_attrs)
          |> Repo.update()
      end
    else
      {:error, :unavailable}
    end
  rescue
    e ->
      Logger.warning("Error updating transaction: #{Exception.message(e)}")
      {:error, e}
  end

  defp cast_decimal(nil), do: nil
  defp cast_decimal(v) when is_integer(v), do: Decimal.new(v)
  defp cast_decimal(v) when is_float(v), do: Decimal.from_float(v)

  defp cast_decimal(v) when is_binary(v) do
    case Decimal.parse(v) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp cast_decimal(_), do: nil

  defp fetch_key(map, k1, k2) do
    cond do
      Map.has_key?(map, k1) -> {:ok, Map.get(map, k1)}
      Map.has_key?(map, k2) -> {:ok, Map.get(map, k2)}
      true -> :error
    end
  end
end
