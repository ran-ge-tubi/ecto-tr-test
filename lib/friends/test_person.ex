defmodule Friends.Test_Person do
  import Ecto.Query

  def test_success_plain do
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

  def test_fail_auto_rollback_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]

      try do
        IO.puts("leading exception because uniq key constraint")
        Friends.Repo.update_all(john_update, [])
        IO.puts("can't not reach here because exception raised in the above line")
      rescue
        Postgrex.Error ->
          IO.puts("Caught a Postgrex error")
      end

      IO.puts("this line can be run, but the db operatoin below can not run
       because the transacation is aborted")

      jane_update =
        from Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def test_fail_manually_rollback_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from Friends.Person,
          where: [first_name: "John"],
          update: [inc: [age: -10]]

      case Friends.Repo.update_all(john_update, []) do
        {1, _} ->
          IO.puts("gonna maunall roll back")
          Friends.Repo.rollback({:manual_rollback, "random message"})
        {_, _} -> IO.puts("do nothing")
      end

      IO.puts("this line can not be run, because manual rollback will immediately leave the funtion")
      jane_update =
        from Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end
end
