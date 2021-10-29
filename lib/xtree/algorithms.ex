defmodule Xtree.Algorithms do
  alias Xtree

  @type xtree() :: Xtree.t()
  @type fn_traverse() ::
          (node :: xtree(), accumulator :: any() ->
             {:ok, accumulator :: any()} | {:halt, accumulator :: any()})

  def build_hash_map(tree) do
    dft_traverse(tree, %{}, fn %{tMD: tMD}, tMD_map ->
      tMD_map =
        case Map.get(tMD_map, tMD, nil) do
          nil -> Map.put(tMD_map, tMD, 1)
          value -> Map.put(tMD_map, tMD, value + 1)
        end

      {:ok, tMD_map}
    end)
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
    case fn_visit.(node, acc) do
      {:halt, acc} ->
        {:halt, acc}

      {:ok, acc} ->
        case dft_traverse(node, acc, fn_visit) do
          {:ok, acc} -> dft_traverse(nodes, acc, fn_visit)
          {:halt, acc} -> {:halt, acc}
        end
    end
  end

  def dft_traverse(%{children: []}, acc, _fn_visit) do
    {:ok, acc}
  end

  def dft_traverse(%{children: children}, acc, fn_visit) do
    dft_traverse(children, acc, fn_visit)
  end

  def dft_traverse(_, acc, _) do
    {:ok, acc}
  end

  @doc """
  Breadth-First pre-order Traverse
  """
  @spec bft_traverse(list(xtree()) | xtree(), accumulator :: any(), fn_visit :: fn_traverse()) ::
          {:ok, accumulator :: any()} | {:halt, accumulator :: any()}
  def bft_traverse([], acc, _fn_visit) do
    {:ok, acc}
  end

  def bft_traverse([node | nodes], acc, fn_visit) do
    case fn_visit.(node, acc) do
      {:halt, acc} ->
        {:halt, acc}

      {:continue, acc} ->
        {:ok, acc}

      {:ok, acc} ->
        case bft_traverse(nodes, acc, fn_visit) do
          {:ok, acc} -> bft_traverse(node, acc, fn_visit)
          {:halt, acc} -> {:halt, acc}
        end
    end
  end

  def bft_traverse(%{children: []}, acc, _fn_visit) do
    {:ok, acc}
  end

  def bft_traverse(%{children: children}, acc, fn_visit) do
    bft_traverse(children, acc, fn_visit)
  end

  def bft_traverse(_, acc, _) do
    {:ok, acc}
  end
end
