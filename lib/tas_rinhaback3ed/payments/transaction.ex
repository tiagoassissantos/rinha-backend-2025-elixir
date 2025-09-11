defmodule TasRinhaback3ed.Payments.Transaction do
  @moduledoc """
  Ecto schema for successful payment transactions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "transactions" do
    field(:correlation_id, Ecto.UUID)
    field(:amount, :decimal)
    field(:route, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:correlation_id, :amount, :route, :inserted_at])
    |> validate_required([:correlation_id, :amount, :route, :inserted_at])
    |> validate_inclusion(:route, ["default", "fallback"])
  end
end
