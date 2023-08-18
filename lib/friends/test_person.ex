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

  def test_fail_error_auto_rollback_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]

      IO.puts("leading exception because uniq key constraint")
      Friends.Repo.update_all(john_update, [])
      IO.puts("can't not reach here because exception raised in the above line")

      jane_update =
        from Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def test_fail_error_auto_rollback_catch_plain do
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

      # code below will raise an exception
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

  def test_fail_error_nested_tr_plain do
    # this change would rollback, because the exception below
    Friends.Repo.transaction(fn ->
      ryan_update =
        from Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]

      {1, _} = Friends.Repo.update_all(ryan_update, [])
      case test_fail_error_auto_rollback_plain() do
        {:ok, _} -> IO.puts("success")
        {:error, _} -> IO.puts("fail")
        {_, _} -> IO.puts("shoud not reach here")
      end

      # code below can not run, because the exception above
      ryan_update =
        from Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
      {1, _} = Friends.Repo.update_all(ryan_update, [])
    end)
  end
end
