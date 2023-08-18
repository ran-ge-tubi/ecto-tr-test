defmodule Friends.Test_Person do
  import Ecto.Query
  alias Ecto.Multi

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

  def test_success_multi do
      john_update =
        from Friends.Person,
          where: [first_name: "John"],
          update: [inc: [age: +10]]

      jane_update =
        from Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]

      Multi.new()
      |> Multi.update_all(:john, john_update, [])
      |> Multi.run(:check_john, fn _repo, changes ->
        case changes do
          %{john: {1, _}} -> {:ok, nil}
          %{john: {_, _}} -> {:error, {:failed_update, "john"}}
        end
      end)
      |> Multi.update_all(:jane, jane_update, [])
      |> Multi.run(:check_jane, fn _repo, changes ->
        case changes do
          %{jane: {1, _}} -> {:ok, nil}
          %{jane: {_, _}} -> {:error, {:failed_update, "jane"}}
        end
      end)
      |> Friends.Repo.transaction()
      |> case do
        {:ok, changes} ->
          IO.inspect(changes)
          # {:ok, "success"}
        {:error, failed_operation, failed_value, changes} ->
          IO.inspect(failed_operation)
          IO.inspect(failed_value)
          IO.inspect(changes)
          {:error, "fail"}
      end
  end

  def test_fail_error_auto_rollback_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]

      IO.puts("leading exception because uniq key constraint")
      Friends.Repo.update_all(john_update, [])
      IO.puts("can not reach here because exception raised in the above line")

      jane_update =
        from Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def test_fail_error_auto_rollback_multi do
    john_update =
      from Friends.Person,
        where: [first_name: "John"],
        update: [set: [first_name: "Ran"]]

    jane_update =
      from Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]

    # multi can not do much for exception
    Multi.new()
    |> Multi.update_all(:john, john_update, [])
    |> Multi.run(:check_john, fn _repo, changes ->
      case changes do
        %{john: {1, _}} -> {:ok, nil}
        %{john: {_, _}} -> {:error, {:failed_update, "john"}}
      end
    end)
    |> Multi.update_all(:jane, jane_update, [])
    |> Multi.run(:check_jane, fn _repo, changes ->
      case changes do
        %{jane: {1, _}} -> {:ok, nil}
        %{jane: {_, _}} -> {:error, {:failed_update, "jane"}}
      end
    end)
    |> Friends.Repo.transaction()
    |> case do
      {:ok, changes} ->
        IO.inspect(changes)
        {:ok, "success"}
      {:error, failed_operation, failed_value, changes} ->
        IO.inspect(failed_operation)
        IO.inspect(failed_value)
        IO.inspect(changes)
        {:error, "fail"}
    end
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
        IO.puts("can not reach here because exception raised in the above line")
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

  def test_fail_error_auto_rollback_catch_multi do
    # the main difference between this multi version and plain version in test_fail_error_auto_rollback_catch_plain
    # is that, because it enforces the component interface(input and output), jane_update would not be called,
    # and there would be no exception raised.
    john_update =
      from Friends.Person,
        where: [first_name: "John"],
        update: [set: [first_name: "Ran"]]

    jane_update =
      from Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]

    # multi can not do much for exception
    Multi.new()
    |> Multi.run(:john, fn repo, _ ->
      try do
        IO.puts("leading exception because uniq key constraint")
        repo.update_all(john_update, [])
        IO.puts("can not reach here because exception raised in the above line")
        {:ok, "success"}
      rescue
        Postgrex.Error ->
          IO.puts("Caught a Postgrex error")
          {:error, "fail"}
      end
    end)
    |> Multi.run(:check_john, fn _repo, changes ->
      case changes do
        %{john: {1, _}} -> {:ok, nil}
        %{john: {_, _}} -> {:error, {:failed_update, "john"}}
      end
    end)
    |> Multi.update_all(:jane, jane_update, [])
    |> Multi.run(:check_jane, fn _repo, changes ->
      case changes do
        %{jane: {1, _}} -> {:ok, nil}
        %{jane: {_, _}} -> {:error, {:failed_update, "jane"}}
      end
    end)
    |> Friends.Repo.transaction()
    |> case do
      {:ok, changes} ->
        IO.inspect(changes)
        {:ok, "success"}
      {:error, failed_operation, failed_value, changes} ->
        IO.inspect(failed_operation)
        IO.inspect(failed_value)
        IO.inspect(changes)
        {:error, "fail"}
    end
  end

  def test_fail_error_auto_rollback_catch_with_proper_ans_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]

      try do
        IO.puts("leading exception because uniq key constraint")
        Friends.Repo.update_all(john_update, [])
        IO.puts("can not reach here because exception raised in the above line")
      rescue
        Postgrex.Error ->
          IO.puts("Caught a Postgrex error")
      end
    end)
  end

  def test_fail_error_auto_rollback_catch_with_proper_ans_multi do
    # we don't need test this case, because using multi prevents any operations from running in an aborted transaction
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

  def test_fail_manually_rollback_multi do
    # the main difference to the `test_fail_manually_rollback_plain` is that you don't need to manually
    # rollback in the multi, all you need is to return the {:error, value}, and you also acquite the
    # ability that control is not leaving the func, and you can do something you want in the final
    # pattern matching block, all of this is thanks to multi's abstraction of the transaction component.
    john_update =
      from Friends.Person,
        where: [first_name: "John"],
        update: [inc: [age: -10]]

    jane_update =
      from Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]

    # multi can not do much for exception
    Multi.new()
    |> Multi.update_all(:john, john_update, [])
    |> Multi.run(:check_john, fn _repo, changes ->
      case changes do
        %{john: {1, _}} ->
          # you can not manual roll back in multi
          # IO.puts("gonna maunall roll back")
          # repo.rollback({:manual_rollback, "rollback the john change"})

          # if you want to terminate the transaction and rollback, just return {:error, value}
          {:error, "mock manual rollback"}
        %{john: {_, _}} -> {:error, {:failed_update, "john"}}
      end
    end)
    |> Multi.update_all(:jane, jane_update, [])
    |> Multi.run(:check_jane, fn _repo, changes ->
      case changes do
        %{jane: {1, _}} -> {:ok, nil}
        %{jane: {_, _}} -> {:error, {:failed_update, "jane"}}
      end
    end)
    |> Friends.Repo.transaction()
    |> case do
      {:ok, changes} ->
        IO.inspect(changes)
        {:ok, "success"}
      {:error, failed_operation, failed_value, changes} ->
        IO.inspect(failed_operation)
        IO.inspect(failed_value)
        IO.inspect(changes)
        IO.inspect("I can do some clean job here")
        {:error, "fail"}
    end
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

  def test_fail_error_nested_tr_multi do
    # would be the same effect as `test_fail_error_nested_tr_plain`, \
    # because multi can not do much to exception, exception will raise
  end

  def test_fail_error_catch_nested_tr_plain do
    # without an outer transaction, return will be {:error, :rollback}
    ans = test_fail_error_auto_rollback_catch_with_proper_ans_plain()
    IO.inspect(ans)

    # this change would rollback, because the exception below
    Friends.Repo.transaction(fn ->
      ryan_update =
        from Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]

      {1, _} = Friends.Repo.update_all(ryan_update, [])
      # within an outer transaction, the result will be {:ok, :ok}, this is so tricky
      # TODO, need to investigate further
      case ans = test_fail_error_auto_rollback_catch_with_proper_ans_plain() do
        {:ok, _} ->
          IO.inspect(ans)
          IO.puts("success")
        {:error, _} ->
          IO.inspect(ans)
          IO.puts("fail")
        {_, _} -> IO.puts("shoud not reach here")
      end

      # operation below can not run, because connection is aborted due to exception above
      ryan_update =
        from Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
      {1, _} = Friends.Repo.update_all(ryan_update, [])
    end)
  end

  @spec test_fail_error_catch_nested_tr_multi :: nil
  def test_fail_error_catch_nested_tr_multi do
    #TODO
  end

  @spec test_fail_manual_rollback_nested_tr_plain :: any
  def test_fail_manual_rollback_nested_tr_plain do
    # this change would rollback, because rolled back in the nested transaction
    Friends.Repo.transaction(fn ->
      ryan_update =
        from Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
      {1, _} = Friends.Repo.update_all(ryan_update, [])

      case ans = test_fail_manually_rollback_plain() do
        {:ok, _} ->
          IO.inspect(ans)
          IO.puts("success")
        {:error, _} ->
          IO.inspect(ans)
          IO.puts("fail")
        {_, _} -> IO.puts("shoud not reach here")
      end

      # code below would raise exception, because the transacation has already been rolled back
      # ryan_update =
      #   from Friends.Person,
      #     where: [first_name: "Ryan"],
      #     update: [inc: [age: 10]]
      # {1, _} = Friends.Repo.update_all(ryan_update, [])

      # or some other things
      IO.puts("print something nonsense")

      # can do manual rollback again
      Friends.Repo.rollback("this is a random message")
    end)
  end

  def test_fail_manual_rollback_nested_tr_multi do
    # TODO
  end

end
