defmodule Friends.Test_Person do
  import Ecto.Query
  alias Mix.Tasks.Hex.Repo
  alias Ecto.Multi

  def test_success_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from(Friends.Person,
          where: [first_name: "John"],
          update: [inc: [age: +10]]
        )

      {1, _} = Friends.Repo.update_all(john_update, [])

      jane_update =
        from(Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]
        )

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  @spec test_success_multi :: any
  def test_success_multi do
    john_update =
      from(Friends.Person,
        where: [first_name: "John"],
        update: [inc: [age: +10]]
      )

    jane_update =
      from(Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]
      )

    multi = Multi.new()
    |> Multi.update_all(:john, john_update, [])
    |> Multi.run(:check_john, fn _repo, changes ->
      case changes do
        %{john: {1, _}} -> {:error, "what is going on"}
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

    IO.inspect("multi to_list resut is ")
    IO.inspect(Multi.to_list(multi))

    multi
    |> Friends.Repo.transaction()
    |> case do
      {:ok, changes} ->
        IO.inspect(changes)

      # {:ok, "success"}
      {:error, failed_operation, failed_value, changes} ->
        IO.inspect("failed op")
        IO.inspect(failed_operation)
        IO.inspect("failed value")
        IO.inspect(failed_value)
        IO.inspect("failed changes")
        IO.inspect(changes)
        {:error, "fail"}
    end
  end

  def test_fail_error_auto_rollback_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from(Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]
        )

      IO.puts("causing exception because uniq key constraint")
      Friends.Repo.update_all(john_update, [])
      IO.puts("can not reach here because exception raised in the above line")

      jane_update =
        from(Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]
        )

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def test_fail_error_auto_rollback_multi do
    john_update =
      from(Friends.Person,
        where: [first_name: "John"],
        update: [set: [first_name: "Ran"]]
      )

    jane_update =
      from(Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]
      )

    # multi will not catch exception automatically
    res =     Multi.new()
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

    IO.puts("what res is #{inspect(res)}")
  end

  def test_fail_error_auto_rollback_catch_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from(Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]
        )

      try do
        IO.puts("causing exception because uniq key constraint")
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
        from(Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]
        )

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def test_fail_error_auto_rollback_catch_multi do
    # the main difference between this multi version and plain version in test_fail_error_auto_rollback_catch_plain
    # is that, because it enforces the component interface(input and output), multi would terminate the execution
    # when it met {:error, _}, and jane_update would not be called, and there would be no running op in an aborted
    # transaction exception raised.
    john_update =
      from(Friends.Person,
        where: [first_name: "John"],
        update: [set: [first_name: "Ran"]]
      )

    jane_update =
      from(Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]
      )

    # multi will not catch exception automatically, we need to catch it manually with Multi.run()
    Multi.new()
    |> Multi.run(:john, fn repo, _ ->
      try do
        IO.puts("causing exception because uniq key constraint")
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
      IO.puts("geran")
      IO.inspect(changes)

      case changes do
        %{john: {1, _}} ->
          {:ok, nil}

        %{john: {_, _}} ->
          IO.puts("is this code really run?")
          {:error, {:failed_update, "john"}}
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

  # This is a helper method to help test nested transaction, this method
  # would manually catch the db exception
  @spec test_fail_error_auto_rollback_catch_with_proper_ans_plain :: any
  def test_fail_error_auto_rollback_catch_with_proper_ans_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from(Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]
        )

      # here, althought we catch the db exception, the value of the whole
      # Repo.transaction() would still be {:error, :rollback}
      try do
        IO.puts("causing exception because uniq key constraint")
        Friends.Repo.update_all(john_update, [])
        IO.puts("can not reach here because exception raised in the above line")
      rescue
        Postgrex.Error ->
          IO.puts("Caught a Postgrex error")
        # I think it's good habit to always call rollback when something goes wrong
        # Friends.Repo.rollback("manual rollback")
        "hello world"
      end
    end)
  end

  @spec test_fail_manually_rollback_plain :: any
  def test_fail_manually_rollback_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from(Friends.Person,
          where: [first_name: "John"],
          update: [inc: [age: -10]]
        )

      case Friends.Repo.update_all(john_update, []) do
        {1, _} ->
          IO.puts("gonna maunall roll back")
          Friends.Repo.rollback({:manual_rollback, "random message"})

        {_, _} ->
          IO.puts("do nothing")
      end

      IO.puts(
        "this line can not be run, because manual rollback will immediately leave the transaction call"
      )

      jane_update =
        from(Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]
        )

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def test_fail_manually_rollback_multi do
    # the main difference to the `test_fail_manually_rollback_plain` is that you don't need to manually
    # rollback in the multi, all you need is to return the {:error, value}, and the multi will just
    # terminate all the subsequent operations, and you also have the ability to inspect the transaction
    # execuation resule by the return value from Repo.transaction() when it is called with multi object
    john_update =
      from(Friends.Person,
        where: [first_name: "John"],
        update: [inc: [age: -10]]
      )

    jane_update =
      from(Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]
      )

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

        %{john: {_, _}} ->
          {:error, {:failed_update, "john"}}
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
    Friends.Repo.transaction(fn ->
      # this change would rollback, because the exception raised in the nested func below
      ryan_update =
        from(Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
        )

      {1, _} = Friends.Repo.update_all(ryan_update, [])

      case test_fail_error_auto_rollback_plain() do
        {:ok, _} -> IO.puts("success")
        {:error, _} -> IO.puts("fail")
        {_, _} -> IO.puts("shoud not reach here")
      end

      # code below can not run, because the exception above
      ryan_update =
        from(Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
        )

      {1, _} = Friends.Repo.update_all(ryan_update, [])
    end)
  end

  def test_fail_error_nested_tr_multi do
    # would be the same effect as `test_fail_error_nested_tr_plain`,
    # because multi will not catch exceptions raised by our own code
    # automatically, exception will raise
  end

  def test_fail_error_catch_nested_tr_plain do
    # here there is a tricky part, without an outer transaction,
    # test_fail_error_auto_rollback_catch_with_proper_ans_plain will return
    # {:error, :rollback}, this is the last value evaluated from the last expression,
    # which is Repo.transaction(), this behavior is as expected
    ans = test_fail_error_auto_rollback_catch_with_proper_ans_plain()
    IO.inspect(ans)

    Friends.Repo.transaction(fn ->
      # this change would rollback, because the exception below
      ryan_update =
        from(Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
        )

      {1, _} = Friends.Repo.update_all(ryan_update, [])

      # tricky here, if test_fail_error_auto_rollback_catch_with_proper_ans_plain is called
      # within an outer transaction, the return value would be
      # {:ok, #{value of the func param of the Repo.transaction()}}. Manually calling rollback()
      # in the rescue clause in the fuc would return the expected {:error, _} value, so I think
      # always manually calling rollback() when something goes wrong is a good habit
      ans = test_fail_error_auto_rollback_catch_with_proper_ans_plain()
      # the output would be {:ok, "hello world"}
      IO.inspect("within a tr, the result would be #{inspect(ans)}")
      case ans do
        {:ok, _} ->
          IO.inspect(ans)
          IO.puts("success")

        {:error, _} ->
          IO.inspect(ans)
          IO.puts("fail")

        {_, _} ->
          IO.puts("shoud not reach here")
      end

      # operation below will raise exception, because connection is aborted due to exception above
      ryan_update =
        from(Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
        )

      {1, _} = Friends.Repo.update_all(ryan_update, [])
    end)
  end

  # This method is an helper method to help test nested transaction with multi
  # when the exception raised in inner method has been rescued
  def test_fail_error_auto_rollback_catch_multi_inner_component do
    john_update =
      from(Friends.Person,
        where: [first_name: "John"],
        update: [set: [first_name: "Ran"]]
      )

    jane_update =
      from(Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]
      )

    # multi will not catch our own exception automatically, we need to catch it manually with Multi.run()
    Multi.new()
    |> Multi.run(:john, fn repo, _ ->
      try do
        IO.puts("causing exception because uniq key constraint")
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
  end

  def test_fail_error_catch_nested_tr_multi do
    ryan_update =
      from(Friends.Person,
        where: [first_name: "Ryan"],
        update: [inc: [age: 10]]
      )

    test_fail_error_auto_rollback_catch_multi_inner_component()
    |> Multi.update_all(:ryan, ryan_update, [])
    |> Multi.run(:check_ryan, fn _repo, changes ->
      case changes do
        %{jane: {1, _}} -> {:ok, nil}
        %{jane: {_, _}} -> {:error, {:failed_update, "ryan"}}
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

  @spec test_fail_manual_rollback_nested_tr_plain :: any
  def test_fail_manual_rollback_nested_tr_plain do
    Friends.Repo.transaction(fn ->
      # this change would rollback, because the rollback in the nested transaction
      ryan_update =
        from(Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
        )

      {1, _} = Friends.Repo.update_all(ryan_update, [])

      case ans = test_fail_manually_rollback_plain() do
        {:ok, _} ->
          IO.inspect(ans)
          IO.puts("success")

        {:error, _} ->
          IO.inspect(ans)
          IO.puts("fail")

          # do manual rollback again to prevent the db op below from running, which would raise exception
          Friends.Repo.rollback("this is a random message")

        {_, _} ->
          IO.puts("shoud not reach here")
      end

      # if there is no rollback above on the pattern matching clause,
      # code below would raise exception, because the transacation has
      # already been rolled back in the nested transaction
      ryan_update =
        from Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
      {1, _} = Friends.Repo.update_all(ryan_update, [])
    end)
  end

  # This method is an helper method to helper test nested transaction with multi
  # when the transaction in the inner method is rolled back manually
  @spec test_fail_manual_rollback_catch_multi_inner_component :: Ecto.Multi.t()
  def test_fail_manual_rollback_catch_multi_inner_component do
    john_update =
      from(Friends.Person,
        where: [first_name: "John"],
        update: [inc: [age: -10]]
      )

    jane_update =
      from(Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]
      )

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

        %{john: {_, _}} ->
          {:error, {:failed_update, "john"}}
      end
    end)
    |> Multi.update_all(:jane, jane_update, [])
    |> Multi.run(:check_jane, fn _repo, changes ->
      case changes do
        %{jane: {1, _}} -> {:ok, nil}
        %{jane: {_, _}} -> {:error, {:failed_update, "jane"}}
      end
    end)
  end

  def test_fail_manual_rollback_nested_tr_multi do
    ryan_update =
      from(Friends.Person,
        where: [first_name: "Ryan"],
        update: [inc: [age: 10]]
      )

    test_fail_manual_rollback_catch_multi_inner_component()
    |> Multi.update_all(:ryan, ryan_update, [])
    |> Multi.run(:check_ryan, fn _repo, changes ->
      case changes do
        %{jane: {1, _}} -> {:ok, nil}
        %{jane: {_, _}} -> {:error, {:failed_update, "ryan"}}
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

  def test_difference_between_update_and_update! do
    Friends.Repo.transaction(fn ->
      person = Friends.Repo.get(Friends.Person, 3)
      IO.inspect(person)
      changeset = Friends.Person.changeset(person, %{first_name: "Ran"})

      # Because we have Ecto.Changeset.unique_constraint(:first_name) config
      # when wireing changeset, calling update() would not raise exception,
      # but update!() would still raise exception.
      # Although there is no exception raised, the transaction still gets rolled back,
      # because the sql has already touched the database.
      res = Friends.Repo.update(changeset)
      case res do
        {:ok, _} -> IO.puts("success update")
        {:error, _} ->
          IO.puts("there is an error")
          # if we don't rollback here, the sql operation below would raise excpetion
          # because of aborted transaction exception, so we need to check the result
          # of db result to properly rollback the tr.
          Friends.Repo.rollback("needs to rollback here")
      end

      jane_update =
        from(Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]
        )
      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def test_with_clause do
    user = %{first: "doomspork"}
    ans =
      with {:ok, first} <- Map.fetch(user, :first),
           {:ok, last} <- Map.fetch(user, :last),
           do: last <> ", " <> first
    IO.puts("ans is #{inspect(ans)}")
  end

  def update_jane_helper() do
    jane_update =
      from(Friends.Person,
        where: [first_name: "Jane"],
        update: [inc: [age: -10]]
      )

    case Friends.Repo.update_all(jane_update, []) do
      {1, val} -> {:ok, val}
      {_, _} -> {:error, "update fail"}
    end
  end

  @spec test_using_with_rollback :: any
  def test_using_with_rollback do
    Friends.Repo.transaction(fn ->
      person = Friends.Repo.get(Friends.Person, 3)
      changeset = Friends.Person.changeset(person, %{first_name: "Ran"})

      # When using plain Repo.transaction(), because besically we need to check
      # every return value of the nesting func call (because ) to prevent causing
      # db operation on oborted transaction excpeiton, and when the condition
      # checking is complex, we need to write a lot of check code as
      # https://hexdocs.pm/ecto/composable-transactions-with-multi.html#composing-with-data-structures
      # shows, but we can use `with` clause to make the rollback operation be at
      # a centor place to make code clean.

      with_ans =
        with {:ok, _} <- update_jane_helper(),
              # this second op would return error
             {:ok, _} <- Friends.Repo.update(changeset) do
          IO.puts("this expression can not be run")
        end

      IO.puts("with ans is")
      IO.inspect(with_ans)

      case with_ans do
        {:ok, _} = with_ans ->
          with_ans

        {:error, _} -> Friends.Repo.rollback("manually rollback at the end of the line")
      end
    end)
  end

  def test_get_behavior() do
    ans = Friends.Repo.get!(Friends.Person, 1)
    IO.puts("#{inspect(ans)}")
  end

end
