defmodule TasRinhaback3ed.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions) do
      add :correlation_id, :uuid, null: false
      add :amount, :decimal, null: false
      add :route, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:transactions, [:inserted_at])
    create index(:transactions, [:route])
  end
end

