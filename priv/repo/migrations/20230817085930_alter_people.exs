defmodule Friends.Repo.Migrations.AlterPeople do
  use Ecto.Migration

  def change do
    alter table("people") do
      add :first_name, :string
      add :last_name, :string
      remove :name
    end
  end
end
