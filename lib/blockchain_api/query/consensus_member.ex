defmodule BlockchainAPI.Query.ConsensusMember do
  @moduledoc false
  import Ecto.Query, warn: false

  alias BlockchainAPI.{Repo, RORepo, Schema.ConsensusMember}

  def list(_params) do
    ConsensusMember
    |> order_by([ct], desc: ct.id)
    |> RORepo.all()
  end

  def create(attrs \\ %{}) do
    %ConsensusMember{}
    |> ConsensusMember.changeset(attrs)
    |> Repo.insert()
  end
end
