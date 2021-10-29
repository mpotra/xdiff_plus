defmodule Xtree do
  alias Xtree.Util
  alias Xtree.Protocol

  defstruct type: :element,
            label: "",
            value: "",
            index: 0,
            nMD: "",
            tMD: "",
            iMD: "",
            nPtr: nil,
            op: nil,
            children: []

  @type node_type() :: :element | :text
  @type op() :: :del | :mov | :ins | :upd | :copy
  @type t() :: %__MODULE__{
          type: node_type(),
          label: String.t(),
          value: String.t(),
          index: non_neg_integer(),
          nMD: String.t(),
          tMD: String.t(),
          iMD: String.t(),
          nPtr: nil | t(),
          op: nil | op(),
          children: list(t())
        }

  def build(node) do
    build_node(node)
  end

  defp build_node(node, index \\ 0) do
    label = Protocol.name(node)
    value = Protocol.value(node)

    # uniquely identify each node
    iMD =
      case Protocol.id(node) do
        nil -> Util.hash(label)
        "" -> Util.hash(label)
        uid -> Util.hash(label <> uid)
      end

    nMD = Util.hash(label <> value)

    children =
      node
      |> Protocol.children()
      |> build_children(%{})
      |> Enum.reverse()

    # Tree message digest
    tMD = Util.hash(nMD <> concat_tMD(children))

    %__MODULE__{
      type: Protocol.type(node),
      label: label,
      index: index,
      value: value,
      # Node message digest
      nMD: nMD,
      # ID message digest
      iMD: iMD,
      # Tree message digest
      tMD: tMD,
      children: children
    }
  end

  # Build children, by assigning indexes based on sibling label
  defp build_children([], _) do
    []
  end

  defp build_children([node | nodes], idx_map) when is_list(nodes) do
    %__MODULE__{label: label} = child = build_node(node)

    idx =
      case Map.get(idx_map, label, nil) do
        nil -> 0
        value -> value + 1
      end

    idx_map = Map.put(idx_map, label, idx)

    [%{child | index: idx} | build_children(nodes, idx_map)]
  end

  defp concat_tMD([]) do
    ""
  end

  defp concat_tMD([%__MODULE__{tMD: tMD} | nodes]) do
    tMD <> concat_tMD(nodes)
  end
end
