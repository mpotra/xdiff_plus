defmodule Xtree.Algorithms do
  alias Xtree

  @type xtree() :: Xtree.t()
  @type fn_traverse() ::
          (node :: xtree(), accumulator :: any() ->
             {:ok, accumulator :: any()} | {:halt, accumulator :: any()})

  @doc """
  Builds a hash map based on `tMD` of each XTree node
  """
  def build_hash_map(tree) do
    {:ok, hash_map} =
      dft_traverse(tree, %{}, fn %{tMD: tMD}, tMD_map ->
        tMD_map =
          case Map.get(tMD_map, tMD, nil) do
            nil -> Map.put(tMD_map, tMD, 1)
            value -> Map.put(tMD_map, tMD, value + 1)
          end

        {:ok, tMD_map}
      end)

    hash_map
  end

  @doc """
  Builds 3 maps out of an X-Tree:
    - hash_map - A map with key being the node hash and value being the node
    - id_map - A map with key being the n_id of node and value being the node
    - op_map - A map with key being the n_id of node and value being an operation
  """
  def build_tree_maps(tree) do
    {:ok, {hash_map, id_map, op_map}} =
      dft_traverse(tree, {%{}, %{}, %{}}, fn %{n_id: n_id, tMD: tMD} = node,
                                             {tMD_map, id_map, op_map} ->
        tMD_map =
          case Map.get(tMD_map, tMD, nil) do
            nil -> Map.put(tMD_map, tMD, 1)
            value -> Map.put(tMD_map, tMD, value + 1)
          end

        id_map = Map.put(id_map, n_id, node)

        # Put into the OpMap `node` as key and `{operation, ptrNode}` as value
        op_map = Map.put(op_map, n_id, nil)

        {:ok, {tMD_map, id_map, op_map}}
      end)

    {hash_map, id_map, op_map}
  end

  @doc """
  Depth-First pre-order Traverse
  """
  @spec dft_traverse(list(xtree()) | xtree(), accumulator :: any(), fn_visit :: fn_traverse()) ::
          {:ok, accumulator :: any()} | {:halt, accumulator :: any()}
  def dft_traverse([], acc, _fn_visit) do
    {:ok, acc}
  end

  def dft_traverse([node | nodes], acc, fn_visit) do
    case dft_traverse(node, acc, fn_visit) do
      {:ok, acc} -> dft_traverse(nodes, acc, fn_visit)
      {:halt, acc} -> {:halt, acc}
    end
  end

  def dft_traverse(%{children: children} = node, acc, fn_visit) do
    case fn_visit.(node, acc) do
      {:halt, acc} ->
        {:halt, acc}

      {:ok, acc} ->
        dft_traverse(children, acc, fn_visit)

      acc ->
        # Same as {:ok, acc}
        dft_traverse(children, acc, fn_visit)
    end
  end

  def dft_traverse(_, acc, _) do
    {:ok, acc}
  end

  @doc """
  Breadth-First pre-order Traverse
  """
  @spec bft_traverse(list(xtree()) | xtree(), accumulator :: any(), fn_visit :: fn_traverse()) ::
          {:ok, accumulator :: any()} | {:halt, accumulator :: any()}
  def bft_traverse([], [], acc, _fn_visit) do
    {:ok, acc}
  end

  def bft_traverse([], children, acc, fn_visit) do
    bft_traverse(children, [], acc, fn_visit)
  end

  def bft_traverse([%{children: node_children} = node | nodes], children, acc, fn_visit) do
    case fn_visit.(node, acc) do
      {:halt, acc} ->
        {:halt, acc}

      {:skip, acc} ->
        bft_traverse(nodes, children, acc, fn_visit)

      {:ok, acc} ->
        bft_traverse(nodes, Enum.concat(children, node_children), acc, fn_visit)

      acc ->
        # Same as {:ok, acc}
        bft_traverse(nodes, Enum.concat(children, node_children), acc, fn_visit)
    end
  end

  def bft_traverse(%{children: _} = node, acc, fn_visit) do
    bft_traverse([node], [], acc, fn_visit)
  end

  def bft_traverse(_, acc, _) do
    {:ok, acc}
  end

  def df_post_order_traverse(_, acc, _) do
    acc
  end

  @spec walk(node :: xtree() | list(xtree()), map_func :: (xtree() -> any())) :: any()
  def walk([], _fn_walk) do
    []
  end

  def walk([node | nodes], fn_walk) do
    ret = walk(node, fn_walk)
    [ret | walk(nodes, fn_walk)]
  end

  def walk(%Xtree{} = node, fn_walk) do
    case fn_walk.(node) do
      %{children: children} = ret ->
        children = walk(children, fn_walk)
        Map.put(ret, :children, children)

      ret ->
        ret
    end
  end

  def walk(ret, _) do
    ret
  end
end
