defmodule BlockchainAPI.Repo.Migrations.AddPendingTransactionTable do
  use Ecto.Migration

  def change do
    create table(:pending_transactions) do
      add :hash, :binary, null: false
      add :type, :string, null: false
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create unique_index(:pending_transactions, [:hash], name: :unique_pending_txn_hash)
  end
end