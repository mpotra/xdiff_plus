defmodule Xtree do
  @moduledoc """
  Builds an X-Tree

  Each node has:
  - `n_id` - (integer() >= 0) The unique ID in the tree
  """
  alias Xtree.Util
  alias Xtree.Protocol

  defstruct n_id: 0,
            type: :element,
            label: "",
            value: "",
            index: 0,
            idx_label: "",
            id_attr?: false,
            nMD: "",
            tMD: "",
            iMD: "",
            # nPtr: nil,
            # op: :nop,
            children: [],
            parent_ids: [],
            ref: nil

  @type n_id() :: non_neg_integer()
  @type node_type() :: :element | :text
  @type op() :: :nop | :del | :mov | :ins | :upd | :copy
  @type t() :: %__MODULE__{
          n_id: n_id(),
          type: node_type(),
          label: String.t(),
          value: String.t(),
          index: non_neg_integer(),
          idx_label: String.t(),
          id_attr?: boolean(),
          nMD: String.t(),
          tMD: String.t(),
          iMD: String.t(),
          # nPtr: nil | t(),
          # op: :nop | op(),
          children: list(t()),
          parent_ids: list(n_id()),
          ref: any()
        }

  def build(node) do
    {root, _last_n_id} = build_node(node)
    root
  end

  defp build_node(node, index \\ 0, n_id \\ 0, parent_ids \\ []) do
    label = Protocol.name(node)
    value = Protocol.value(node)

    # uniquely identify each node
    {iMD, has_id_attr} =
      case Protocol.id(node) do
        nil -> {Util.hash(label), false}
        "" -> {Util.hash(label), false}
        uid -> {Util.hash(label <> uid), true}
      end

    nMD = Util.hash(label <> value)

    {children, last_n_id} =
      node
      |> Protocol.children()
      |> build_children(%{}, n_id + 1, [n_id | parent_ids])

    # children = Enum.reverse(children)

    # Tree message digest
    tMD = Util.hash(nMD <> concat_tMD(children))

    {%__MODULE__{
       n_id: n_id,
       type: Protocol.type(node),
       label: label,
       index: index,
       value: value,
       idx_label: ".#{label}[#{index}]",
       id_attr?: has_id_attr,
       # Node message digest
       nMD: nMD,
       # ID message digest
       iMD: iMD,
       # Tree message digest
       tMD: tMD,
       children: children,
       parent_ids: parent_ids,
       ref: node
     }, last_n_id}
  end

  # Build children, by assigning indexes based on sibling label
  defp build_children([], _, last_n_id, _parent_ids) do
    {[], last_n_id}
  end

  defp build_children([node | nodes], idx_map, last_n_id, parent_ids) when is_list(nodes) do
    {%__MODULE__{label: label} = child, last_n_id} = build_node(node, 0, last_n_id, parent_ids)

    index =
      case Map.get(idx_map, label, nil) do
        nil -> 0
        value -> value + 1
      end

    idx_map = Map.put(idx_map, label, index)

    {children, last_n_id} = build_children(nodes, idx_map, last_n_id, parent_ids)

    # Update both index and idx_label
    {[%{child | index: index, idx_label: ".#{label}[#{index}]"} | children], last_n_id}
  end

  defp concat_tMD([]) do
    ""
  end

  defp concat_tMD([%__MODULE__{tMD: tMD} | nodes]) do
    tMD <> concat_tMD(nodes)
  end
end
