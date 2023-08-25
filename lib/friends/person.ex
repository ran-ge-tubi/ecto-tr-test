defmodule Friends.Person do
  use Ecto.Schema
  import Ecto.Query

  schema "people" do
    field :first_name, :string
    field :last_name, :string
    field :age, :integer
  end

  def changeset(person, params \\ %{}) do
    person
    |> Ecto.Changeset.cast(params, [:first_name, :last_name, :age])
    # |> Ecto.Changeset.validate_required([:first_name, :last_name])
    |> Ecto.Changeset.unique_constraint(:first_name)
    |> Ecto.Changeset.validate_length(:first_name, min: 5)
  end

  def test do
    Friends.Repo.transaction(fn ->
      john_update =
        from Friends.Person,
          where: [first_name: "John"],
          update: [inc: [age: +10]]

      {1, _} = Friends.Repo.update_all(john_update, [])

      jane_update =
        from Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end
end
