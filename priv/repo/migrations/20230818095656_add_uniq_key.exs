defmodule Friends.Repo.Migrations.AddUniqKey do
  use Ecto.Migration

  def change do
    create index("people", [:first_name], unique: true)
  end
end
