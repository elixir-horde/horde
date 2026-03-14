defmodule Horde.TableUtils do
  @moduledoc false

  @type table :: :ets.table()

  @spec new_table(atom()) :: table()
  def new_table(name) do
    :ets.new(name, [:set, :protected])
  end

  @spec size_of(table()) :: non_neg_integer()
  def size_of(table) do
    :ets.info(table, :size)
  end

  @spec get_item(table(), term()) :: term() | nil
  def get_item(table, id) do
    case :ets.lookup(table, id) do
      [{_, item}] -> item
      [] -> nil
    end
  end

  @spec delete_item(table(), term()) :: table()
  def delete_item(table, id) do
    :ets.delete(table, id)
    table
  end

  @spec pop_item(table(), term()) :: {term() | nil, table()}
  def pop_item(table, id) do
    item = get_item(table, id)
    delete_item(table, id)
    {item, table}
  end

  @spec put_item(table(), term(), term()) :: table()
  def put_item(table, id, item) do
    :ets.insert(table, {id, item})
    table
  end

  @spec all_items_values(table()) :: [term()]
  def all_items_values(table) do
    :ets.select(table, [{{:"$1", :"$2"}, [], [:"$2"]}])
  end

  @spec any_item(table(), (term() -> boolean())) :: boolean()
  def any_item(table, predicate) do
    try do
      :ets.safe_fixtable(table, true)
      first_key = :ets.first(table)
      ets_any?(table, predicate, first_key)
    after
      :ets.safe_fixtable(table, false)
    end
  end

  @spec ets_any?(table(), (term() -> boolean()), term()) :: boolean()
  def ets_any?(_table, _predicate, :"$end_of_table") do
    false
  end

  def ets_any?(table, predicate, key) do
    entry = get_item(table, key)

    if predicate.(entry) do
      true
    else
      ets_any?(table, predicate, :ets.next(table, key))
    end
  end
end
