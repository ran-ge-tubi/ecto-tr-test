defmodule Friends.Test_Person do
  import Ecto.Query
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

    IO.inspect("multi to_list resut is ")
    IO.inspect(Multi.to_list(multi))

    multi
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
        from(Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]
        )

      IO.puts("leading exception because uniq key constraint")
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
        from(Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]
        )

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
        from(Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]
        )

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def test_fail_error_auto_rollback_catch_multi do
    # the main difference between this multi version and plain version in test_fail_error_auto_rollback_catch_plain
    # is that, because it enforces the component interface(input and output), jane_update would not be called,
    # and there would be no exception raised.
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

  # This is a helper method to help test nested transaction, this method will not trigger
  # 'operation in an aborted transaction" exception
  @spec test_fail_error_auto_rollback_catch_with_proper_ans_plain :: any
  def test_fail_error_auto_rollback_catch_with_proper_ans_plain do
    Friends.Repo.transaction(fn ->
      john_update =
        from(Friends.Person,
          where: [first_name: "John"],
          update: [set: [first_name: "Ran"]]
        )

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
        "this line can not be run, because manual rollback will immediately leave the funtion"
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
    # rollback in the multi, all you need is to return the {:error, value}, and you also acquite the
    # ability that control is not leaving the func, and you can do something you want in the final
    # pattern matching block, all of this is thanks to multi's abstraction of the transaction component.
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
    # this change would rollback, because the exception below
    Friends.Repo.transaction(fn ->
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
    # would be the same effect as `test_fail_error_nested_tr_plain`, \
    # because multi will not catch exception automatically, exception will raise
  end

  def test_fail_error_catch_nested_tr_plain do
    # without an outer transaction, return will be {:error, :rollback}
    ans = test_fail_error_auto_rollback_catch_with_proper_ans_plain()
    IO.inspect(ans)

    # this change would rollback, because the exception below
    Friends.Repo.transaction(fn ->
      ryan_update =
        from(Friends.Person,
          where: [first_name: "Ryan"],
          update: [inc: [age: 10]]
        )

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

  # This method is an helper method to helper test nested transaction with multi
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

    # multi will not catch exception automatically, we need to catch it manually with Multi.run()
    Multi.new()
    |> Multi.insert(:john, fn repo, _ ->
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
    # this change would rollback, because rolled back in the nested transaction
    Friends.Repo.transaction(fn ->
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

        {_, _} ->
          IO.puts("shoud not reach here")
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

  # This method is an helper method to helper test nested transaction with multi
  # when the transaction in the inner method is rolled back manually
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

  def test_update_and_update do
    Friends.Repo.transaction(fn ->
      person = Friends.Repo.get(Friends.Person, 3)
      IO.inspect(person)
      changeset = Friends.Person.changeset(person, %{first_name: "Ran"})

      # although there is no exception raised, the transaction is also rolled back
      # because the sql already touched the database
      res = Friends.Repo.update(changeset)
      IO.puts("this is an error")
      IO.inspect(res)

      jane_update =
        from(Friends.Person,
          where: [first_name: "Jane"],
          update: [inc: [age: -10]]
        )

      {1, _} = Friends.Repo.update_all(jane_update, [])
    end)
  end

  def tmp_test do
    user = %{first: "doomspork"}

    ans =
      with {:ok, first} <- Map.fetch(user, :first),
           {:ok, last} <- Map.fetch(user, :last),
           do: last <> ", " <> first

    ans
  end

  def update_jane() do
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

  def test_using_with_rollback do
    Friends.Repo.transaction(fn ->
      person = Friends.Repo.get(Friends.Person, 3)
      changeset = Friends.Person.changeset(person, %{first_name: "Ran"})

      # using plain transaction has a problem, that is fun returning {:error, _} does not
      # necessarily mean that the function underneath actually touched the db and trigger the
      # rollback, for example, some changeset validation is actually executed on client side
      # without touching the db, so basically that means, we need to add manual rollback at
      # everywhere where we checked the return value. But by using `with`, can I add a last rollback
      # as a whole at the end of with block?

      with_ans =
        with {:ok, _} <- update_jane(),
             {:ok, _} <- Friends.Repo.update(changeset) do
          IO.puts("this expression can not be run")
        end

      IO.puts("with ans is")
      IO.inspect(with_ans)

      case with_ans do
        {:ok, _} = with_ans ->
          with_ans

        {:error, _} = with_ans ->
          Friends.Repo.rollback("manually rollback at the end of the line")
          with_ans
      end
    end)
  end
end
