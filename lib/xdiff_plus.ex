defmodule XdiffPlus do
  @moduledoc """
  X-tree Diff+: Efficient Change Detection Algorithm in XML Documents
  Suk Kyoon Lee°, Dong Ah Kim
  http://dl.ifip.org/db/conf/euc/euc2006/LeeK06.pdf

  Reference: https://github.com/yidafu/x-tree-diff-plus/blob/master/src/XTreeDiffPlus.ts
  """
  alias Xtree
  alias Xtree.Algorithms

  def assign_node(%{n_id: n_id, tMD: tMD} = node, {tMD_map, id_map, op_map}) do
    # Build the tMD map
    # Each node tMD hash (`node.tMD`) is the key
    # Value is the number of times the tMD hash appears in the tree
    tMD_map = Map.update(tMD_map, tMD, 1, &(&1 + 1))
    # case Map.get(tMD_map, tMD, nil) do
    #   nil -> Map.put(tMD_map, tMD, 1)
    #   value -> Map.put(tMD_map, tMD, value + 1)
    # end

    # Build the ID map, where each node id (`node.n_id`)
    # is the key, and the value is the `node` object
    id_map = Map.put(id_map, n_id, node)

    # Build the operations map for the tree
    # where is node id is the key and the value is the operation
    # tuple {operation_name, reference node id}
    # default set to `nil`
    op_map = Map.put(op_map, n_id, nil)

    {tMD_map, id_map, op_map}
  end

  def build_old_tree_maps(tree) do
    {:ok, acc} =
      Algorithms.dft_traverse(
        tree,
        {%{}, %{}, %{}, %{}},
        fn %{tMD: tMD} = node, {tMD_map, id_map, op_map, o_htable} ->
          {tMD_map, id_map, op_map} = assign_node(node, {tMD_map, id_map, op_map})

          # Store only non-unique nodes in o_htable
          o_htable =
            if Map.get(tMD_map, tMD, 1) > 1 do
              Map.update(o_htable, tMD, [node], fn nodes -> [node | nodes] end)
            else
              o_htable
            end

          {tMD_map, id_map, op_map, o_htable}
        end
      )

    acc
  end

  def build_new_tree_maps(tree) do
    {:ok, acc} =
      Algorithms.dft_traverse(
        tree,
        {%{}, %{}, %{}, %{}, %{}},
        fn %{tMD: tMD, iMD: iMD, id_attr?: id_attr?} = node,
           {tMD_map, id_map, op_map, n_htable, n_idtable} ->
          {tMD_map, id_map, op_map} = assign_node(node, {tMD_map, id_map, op_map})

          # Store only unique nodes in n_htable
          # Because we don't want to iterate over the nodes again
          # at the end of the traversal, we store each node in the table
          # when its tMD count is 1 and as the count increases
          # we delete it from the n_htable
          n_htable =
            if Map.get(tMD_map, tMD) == 1 do
              Map.put(n_htable, tMD, node)
            else
              Map.delete(n_htable, tMD)
            end

          # Store all nodes with unique iMDs (if they have the ID attribute set)
          n_idtable =
            if id_attr? do
              Map.put(n_idtable, iMD, node)
            else
              n_idtable
            end

          {tMD_map, id_map, op_map, n_htable, n_idtable}
        end
      )

    acc
  end

  def diff(%Xtree{} = new_tree, %Xtree{} = old_tree) do
    # build the tree message digest map for the old XTree
    {_o_tMD_map, o_id_map, o_op_map, o_htable} = build_old_tree_maps(old_tree)
    # build the tree message digest map for the new XTree
    {_n_tMD_map, n_id_map, n_op_map, n_htable, n_idtable} = build_new_tree_maps(new_tree)

    # Tuple to hold id maps for nodes
    id_maps = {n_id_map, o_id_map}
    # Tuple to hold operation maps for nodes
    op_maps = {n_op_map, o_op_map}

    # Step 1: Match identical subtrees with 1-to-1 correspondence
    # and match nodes with ID attributes
    {:ok, {op_maps, m_list}} =
      Algorithms.bft_traverse(
        old_tree,
        {op_maps, %{}},
        fn %{tMD: tMD} = o_node, {op_maps, m_list} = acc ->
          # Where [node N] is the root of a subtree in old tree
          # If any entry of O_Htable does NOT have
          # the same tMD value that the (old) [node] N has
          # o_htable stores only non-unique nodes by tMD
          # so if a tMD is not present in the o_htable
          # it means that the old node is unique in the old tree
          if Map.has_key?(o_htable, tMD) == false do
            # n_htable stores unique tMD nodes in the new tree
            # check to see if the old unique node has a unique tMD match
            # in the new tree
            case Map.get(n_htable, tMD) do
              nil ->
                # old unique subtree is not in the new tree
                # Continue visiting other nodes in old tree
                {:ok, acc}

              %{} = n_node ->
                # there is a unique node in the new tree that has the same tMD
                # as the unique node in the old tree

                # match the nodes with NOP
                op_maps = match_nodes(op_maps, o_node, n_node, :nop)

                # Add the pair to m_list
                m_list = Map.put(m_list, o_node, n_node)

                # Stop visiting all subtrees of old node N
                # Continue visiting other nodes in old tree
                {:skip, {op_maps, m_list}}
            end
          else
            # Continue visiting other nodes in old tree
            {:ok, acc}
          end
        end
      )

    # After completing the previous sub-step, traverse old tree
    # in breadth-first order, and for each unmatched node
    # if it has an ID attribute, lookup the N_IDHTable for
    # new nodes that have the same iMD value.
    # If lookup succeeds, match the old node with the new node as NOP.
    #
    # L.E. to optimize traversal, we can use the old op_map to
    # identify and check only unmatched nodes, instead of traversing
    # the entire tree.

    # NOTE: This does ALSO matches nodes that have the same iMD (label+ID attr)
    # and that have their attributes changed, or different contents
    # TODO: check for differences and set operation to UPD or change? if the case
    op_maps =
      elem(op_maps, 1)
      |> Enum.reduce(op_maps, fn
        {o_n_id, nil}, op_maps ->
          # node n_id has no operation set
          # Get node and check for ID attribute
          case Map.get(o_id_map, o_n_id) do
            %{iMD: iMD, nMD: nMD, index: index, id_attr?: true} = o_node ->
              # Note: if multiple elements have the same ID
              # then this will match with the last traversed node that has the same iMD
              # Possible workaround would be to support multiple nodes per iMD
              # in the N_IDHtable
              case Map.get(n_idtable, iMD) do
                nil ->
                  op_maps

                %{index: ^index, nMD: ^nMD} = n_node ->
                  # Node has the same iMD, the same index and no change in attributes (nMD)
                  match_nodes(op_maps, o_node, n_node, :nop)

                %{index: ^index} = n_node ->
                  # Node has the same iMD, the same index, but has attributes (nMD) changed
                  match_nodes(op_maps, o_node, n_node, :upd)

                %{} = n_node ->
                  # Node has the same iMD but different index
                  match_nodes(op_maps, o_node, n_node, :mov)
              end

            _ ->
              op_maps
          end

        _, op_maps ->
          op_maps
      end)

    # Step 2: Propagate matches upward to parent nodes
    op_maps = match_upwards(op_maps, m_list, id_maps)

    # Step 3: Match remaining nodes downwards
    {:ok, op_maps} =
      Algorithms.dft_traverse(
        old_tree,
        op_maps,
        &dft_match_remaining_nodes_downwards(&1, &2, id_maps)
      )

    # Step 4: Tune existing matches
    op_maps = tune_matches(old_tree, op_maps, id_maps)

    # Step 5: Match remaining identical subtree
    # with move and copy operations
    {n_op_map, o_op_map} = op_maps
    s_htable = step5_find_unmatched_nodes(o_op_map, old_tree)

    t_htable = step5_find_unmatched_nodes(n_op_map, new_tree)

    # Handle edge-cases:
    # 1. duplicate sub-tree over two trees
    #   1.1 the number of duplicate subtrees is equal
    #   1.2 the number of duplicate subtrees is not equal
    # 2. Extra or missing subtree

    # 5.1 match node with the same tMD
    op_maps =
      Enum.reduce(t_htable, op_maps, fn {tMD, n_nodes}, op_maps ->
        case Map.get(s_htable, tMD) do
          nil ->
            op_maps

          o_nodes ->
            len = Enum.min([Enum.count(o_nodes), Enum.count(n_nodes)])

            o_nodes
            |> Enum.take(len)
            |> Enum.zip(n_nodes)
            |> Enum.reduce(op_maps, fn {o_node, n_node}, op_maps ->
              op_maps
              |> match_update_ptr(o_node, n_node)
              |> match_subtree([o_node], [n_node], :nop)
              |> match_upwards([{o_node, n_node}], id_maps)
            end)
        end
      end)

    {_n_op_map, o_op_map} = op_maps
    # Find all subtrees with same parent and index, marked as UPD
    s_p_htable =
      s_htable
      |> Enum.reduce([], &Enum.concat(elem(&1, 1), &2))
      |> Enum.reduce(%{}, fn
        %{n_id: o_node_id, parent_ids: [parent_id | _]} = o_node, s_p_htable ->
          if Map.get(o_op_map, o_node_id) == nil do
            entries = Map.get(s_p_htable, parent_id, [])
            Map.put(s_p_htable, parent_id, [o_node | entries])
          else
            s_p_htable
          end

        _, acc ->
          acc
      end)

    op_maps =
      t_htable
      |> Enum.reduce([], &Enum.concat(elem(&1, 1), &2))
      |> Enum.reduce(op_maps, fn
        %{
          n_id: n_node_id,
          index: n_index,
          label: n_label,
          parent_ids: [n_parent_id | _]
        } = n_node,
        {n_op_map, _o_op_map} = op_maps ->
          if Map.get(n_op_map, n_node_id) == nil do
            case Map.get(n_op_map, n_parent_id) do
              {_, expect_p_node_id} ->
                case Map.get(s_p_htable, expect_p_node_id, nil) do
                  [_ | _] = old_children ->
                    Enum.reduce(
                      old_children,
                      op_maps,
                      fn
                        %{index: ^n_index} = o_node, op_maps ->
                          match_nodes(op_maps, o_node, n_node, :upd)

                        %{label: ^n_label} = o_node, op_maps ->
                          match_nodes(op_maps, o_node, n_node, :mov)

                        _, op_maps ->
                          op_maps
                      end
                    )

                  _ ->
                    op_maps
                end

              _ ->
                op_maps
            end
          else
            op_maps
          end

        _, acc ->
          acc
      end)

    u_op_maps =
      op_maps
      |> set_defaults()
      |> unfold_op_maps(id_maps)

    [u_op_maps, {new_tree, old_tree}]
  end

  def diff(nil, %Xtree{} = old_tree) do
    [{_, op_map}, {_, tree}] = diff(Xtree.build_empty(), old_tree)
    [{%{}, op_map}, {nil, tree}]
  end

  def diff(%Xtree{} = new_tree, nil) do
    [{op_map, _}, {tree, _}] = diff(new_tree, Xtree.build_empty())
    [{op_map, %{}}, {tree, nil}]
  end

  def diff(nil, nil) do
    [{%{}, %{}}, {nil, nil}]
  end

  def diff(new_tree, old_tree) do
    diff(Xtree.build(new_tree), Xtree.build(old_tree))
  end

  defp unfold_op_maps({n_op_map, o_op_map}, {n_id_map, o_id_map}) do
    {
      unfold_op_map(n_op_map, {n_id_map, o_id_map}),
      unfold_op_map(o_op_map, {o_id_map, n_id_map})
    }
  end

  defp unfold_op_map(%{} = op_map, {id_map, other_id_map}) do
    op_map
    |> Enum.reduce(%{}, &unfold_op_map_item(&1, {id_map, other_id_map}, &2))
  end

  defp unfold_op_map_item({node_id, {op, other_node_id}}, {id_map, other_id_map}, acc) do
    node = Map.get(id_map, node_id)
    other_node = Map.get(other_id_map, other_node_id)
    Map.put(acc, node, {op, other_node})
  end

  defp unfold_op_map_item({node_id, :ins}, {id_map, _}, acc) do
    # Handle inserts, and set reference node to the previous node in the same tree
    node = Map.get(id_map, node_id)

    op =
      case node do
        %{parent_ids: []} ->
          {:ins, nil, nil}

        %{parent_ids: [parent_id | _]} ->
          parent = Map.get(id_map, parent_id)

          prev_sibling =
            if node_id == parent_id + 1 do
              # Node is first child of parent
              # No previous sibling
              nil
            else
              Map.get(id_map, node_id - 1)
            end

          {:ins, parent, prev_sibling}
      end

    Map.put(acc, node, op)
  end

  defp unfold_op_map_item({node_id, op}, {id_map, _}, acc) when is_atom(op) do
    node = Map.get(id_map, node_id)
    Map.put(acc, node, op)
  end

  defp dft_match_remaining_nodes_downwards(
         %{n_id: o_node_id} = o_node,
         {_, o_op_map} = op_maps,
         {n_id_map, _} = _id_maps
       ) do
    case Map.get(o_op_map, o_node_id) do
      {_op, n_node_id} ->
        # o_node has been matched with an operation and another new node
        n_node = Map.get(n_id_map, n_node_id)

        # Iterate over unmatched children of new node
        step3_match_subtree(op_maps, o_node, n_node)

      nil ->
        op_maps
    end
  end

  defp step3_match_subtree(
         {n_op_map, o_op_map} = op_maps,
         %{children: o_children} = _o_node,
         n_node
       ) do
    # Find all unmatched children of old node
    case step3_reject_matched_children(o_op_map, o_children) do
      {[], _, _} ->
        op_maps

      {_, tMD_map, idx_label_map} ->
        # Iterate over unmatched children of the new node
        n_op_map
        |> step3_find_unmatched_children(n_node)
        |> Enum.reduce({op_maps, tMD_map, idx_label_map}, &step3_match_child/2)
        |> elem(0)
    end
  end

  defp step3_match_child(%{tMD: tMD} = n_child, {op_maps, tMD_map, idx_label_map} = acc) do
    case Enum.reverse(Map.get(tMD_map, tMD, [])) do
      [] ->
        step3_match_child_rest(n_child, acc)

      [o_child | o_children] ->
        {
          match_subtree(op_maps, [o_child], [n_child], :nop),
          Map.put(tMD_map, tMD, o_children),
          idx_label_map
        }
    end
  end

  defp step3_match_child_rest(
         %{idx_label: idx_label, type: type} = n_child,
         {op_maps, tMD_map, idx_label_map} = acc
       ) do
    case Enum.reverse(Map.get(idx_label_map, idx_label, [])) do
      [] ->
        acc

      [%{type: ^type} = o_child | o_children] when type == :text ->
        {
          match_nodes(op_maps, o_child, n_child, :upd),
          tMD_map,
          Map.put(idx_label_map, idx_label, o_children)
        }

      [o_child | o_children] ->
        op = if o_child.nMD == n_child.nMD, do: :nop, else: :upd

        {
          match_nodes(op_maps, o_child, n_child, op),
          tMD_map,
          Map.put(idx_label_map, idx_label, o_children)
        }
    end
  end

  defp step3_reject_matched_children(op_map, children) do
    {unmatched_children, tMD_map, idx_label_map} =
      children
      |> Enum.reduce(
        {[], %{}, %{}},
        fn %{n_id: child_id, tMD: tMD, idx_label: idx_label} = child,
           {nodes, tMD_map, idx_label_map} = acc ->
          if Map.get(op_map, child_id) == nil do
            {
              [child | nodes],
              Map.update(tMD_map, tMD, [child], &[child | &1]),
              Map.update(idx_label_map, idx_label, [child], &[child | &1])
            }
          else
            acc
          end
        end
      )

    {Enum.reverse(unmatched_children), tMD_map, idx_label_map}
  end

  defp step3_find_unmatched_children(op_map, %{children: children}) do
    children
    |> Enum.reduce(
      [],
      fn %{n_id: child_id} = child, acc ->
        if Map.get(op_map, child_id) == nil do
          [child | acc]
        else
          acc
        end
      end
    )
    |> Enum.reverse()
  end

  def step5_find_unmatched_nodes(op_map, tree) do
    {:ok, h_table} =
      Algorithms.bft_traverse(tree, %{}, fn %{n_id: n_id, tMD: tMD} = o_node, h_table ->
        if Map.get(op_map, n_id) == nil do
          nodes = Map.get(h_table, tMD, [])
          Map.put(h_table, tMD, [o_node | nodes])
        else
          h_table
        end
      end)

    h_table
  end

  def tune_matches(old_tree, op_maps, id_maps) do
    {:ok, op_maps} =
      Algorithms.bft_traverse(
        old_tree,
        op_maps,
        fn node, op_maps ->
          tune_match(node, op_maps, id_maps)
        end
      )

    op_maps
  end

  defp tune_match(
         %{n_id: node_id} = node,
         {n_op_map, o_op_map} = op_maps,
         {n_id_map, o_id_map} = _id_maps
       ) do
    with n_positive <- positive_qualifier(node, o_op_map, n_id_map),
         n_negative <- negative_qualifier(node, o_op_map, n_id_map),
         c when c < 0.5 <- consistency(n_positive, n_negative),
         %{n_id: alt_id} = node_ptr <- get_ptr(node_id, o_op_map, n_id_map),
         {degree, %{n_id: sup_node_id} = sup_node} <-
           alternative_matches(node, alt_id, o_op_map, n_id_map),
         sup_n_positive <- positive_qualifier(sup_node, n_op_map, o_id_map),
         %{} = sup_ptr <- get_ptr(sup_node_id, n_op_map, o_id_map) do
      if degree > n_positive + sup_n_positive do
        op_maps
        |> match_nodes(sup_ptr, node_ptr, :nop)
        |> match_nodes(node, sup_node, :nop)
      else
        op_maps
      end
    else
      _ -> op_maps
    end
  end

  defp match_upwards(op_maps, m_list, id_maps) do
    Enum.reduce(m_list, op_maps, fn {%{n_id: _, parent_ids: o_parent_ids},
                                     %{n_id: _, parent_ids: n_parent_ids}},
                                    op_maps ->
      propagate_parents_match_upwards(o_parent_ids, n_parent_ids, id_maps, op_maps)
    end)
  end

  defp propagate_parents_match_upwards([] = _o_parent_ids, _n_parent_ids, _id_maps, op_maps) do
    op_maps
  end

  defp propagate_parents_match_upwards(_o_parent_ids, [] = _n_parent_ids, _id_maps, op_maps) do
    op_maps
  end

  defp propagate_parents_match_upwards(
         [o_parent_id | o_parent_ids],
         [n_parent_id | n_parent_ids],
         {n_id_map, o_id_map} = id_maps,
         op_maps
       ) do
    o_parent = Map.get(o_id_map, o_parent_id)
    n_parent = Map.get(n_id_map, n_parent_id)

    if equal_label?(o_parent, n_parent) do
      op_maps =
        if o_parent.nMD == n_parent.nMD do
          # Parent nodes have diverged in attribute values
          match_nodes(op_maps, o_parent, n_parent, :nop)
        else
          match_nodes(op_maps, o_parent, n_parent, :upd)
        end

      propagate_parents_match_upwards(o_parent_ids, n_parent_ids, id_maps, op_maps)
    else
      op_maps
    end
  end

  defp equal_label?(%{label: label}, %{label: label}) do
    true
  end

  defp equal_label?(_, _) do
    false
  end

  defp match_subtree(op_maps, [], _, _op) do
    op_maps
  end

  defp match_subtree(op_maps, _, [], _op) do
    op_maps
  end

  defp match_subtree(
         op_maps,
         [%{children: o_children} = o_node | o_nodes],
         [%{children: n_children} = n_node | n_nodes],
         op
       ) do
    op_maps
    |> match_nodes(o_node, n_node, op)
    |> match_subtree(Enum.concat(o_nodes, o_children), Enum.concat(n_nodes, n_children), op)
  end

  defp match_nodes({n_op_map, o_op_map}, %{n_id: o_node_id}, %{n_id: n_node_id}, op) do
    {
      Map.put(n_op_map, n_node_id, {op, o_node_id}),
      Map.put(o_op_map, o_node_id, {op, n_node_id})
    }
  end

  defp match_update_ptr({n_op_map, o_op_map}, %{n_id: o_node_id}, %{n_id: n_node_id}) do
    {
      Map.update(n_op_map, n_node_id, nil, fn
        {op, _} -> {op, o_node_id}
        op -> op
      end),
      Map.update(o_op_map, o_node_id, nil, fn
        {op, _} -> {op, n_node_id}
        op -> op
      end)
    }
  end

  defp set_defaults({n_op_map, o_op_map}) do
    # {:ok, o_op_map} = Algorithms.bft_traverse(old_tree, o_op_map, &set_default_op(&1, &2, :del))
    # {:ok, n_op_map} = Algorithms.bft_traverse(new_tree, n_op_map, &set_default_op(&1, &2, :ins))

    # Instead of traversing the entire tree, just iterate over the operations map
    # and updated entries that have no operation

    o_op_map = Enum.reduce(o_op_map, o_op_map, &set_default_op(&1, &2, :del))
    n_op_map = Enum.reduce(n_op_map, n_op_map, &set_default_op(&1, &2, :ins))

    {n_op_map, o_op_map}
  end

  defp set_default_op({n_id, nil}, acc, default_op) do
    Map.put(acc, n_id, default_op)
  end

  defp set_default_op(_, acc, _) do
    acc
  end

  defp consistency(n_positive, n_negative) do
    sum = n_positive + n_negative

    cond do
      sum == 0 -> :infinity
      n_positive == 0 -> 0
      true -> n_positive / sum
    end
  end

  defp alternative_matches(%{children: children}, alt_id, op_map, other_id_map) do
    Enum.reduce(children, %{}, fn child, l_am ->
      case alternative_match(child, alt_id, op_map, other_id_map) do
        nil -> l_am
        am -> Map.update(l_am, am, 1, &(&1 + 1))
      end
    end)
    |> Enum.reduce({0, nil}, fn {node, value}, {degree, sup_node} ->
      if degree < value do
        {value, node}
      else
        {degree, sup_node}
      end
    end)
  end

  defp alternative_match(%{n_id: id, label: label}, alt_id, op_map, other_id_map) do
    with {_, m_id} <- Map.get(op_map, id),
         %{parent_ids: [m_parent_id | _]} when m_parent_id != alt_id <-
           Map.get(other_id_map, m_id),
         %{label: am_label} = am when am_label != label <- Map.get(other_id_map, m_parent_id) do
      am
    else
      _ -> nil
    end
  end

  defp positive_qualifier(node, op_map, other_id_map) do
    compute_qualifier(node, op_map, other_id_map, true)
  end

  defp negative_qualifier(node, op_map, other_id_map) do
    compute_qualifier(node, op_map, other_id_map, false)
  end

  defp compute_qualifier(%{children: children, n_id: id}, op_map, other_id_map, qualifier) do
    case Map.get(op_map, id) do
      {_, match_id} -> compute_qualifier(children, match_id, op_map, other_id_map, qualifier)
      _ -> 0
    end
  end

  defp compute_qualifier([], _parent_match_id, _op_map, _other_id_map, _qualifier) do
    0
  end

  defp compute_qualifier(
         [%{n_id: child_id} | children],
         parent_match_id,
         op_map,
         other_id_map,
         qualifier
       ) do
    value =
      if qualify_match?(child_id, parent_match_id, op_map, other_id_map, qualifier) do
        1
      else
        0
      end

    value + compute_qualifier(children, parent_match_id, op_map, other_id_map, qualifier)
  end

  defp qualify_match?(child_id, parent_match_id, op_map, other_id_map, qualifier) do
    case get_ptr(child_id, op_map, other_id_map) do
      %{parent_ids: [^parent_match_id | _]} -> qualifier
      _ -> not qualifier
    end
  end

  defp get_ptr(id, op_map, other_id_map) do
    case Map.get(op_map, id) do
      {_, match_id} -> Map.get(other_id_map, match_id)
      _ -> nil
    end
  end

  # def find_parents(%{children: children} = parent, search) do
  #   parent
  #   |> find_in_children(children, search)
  #   |> Enum.reverse()
  # end

  # def find_in_children(_parent, [], _search) do
  #   []
  # end

  # def find_in_children(parent, [%{n_id: n_id} | _], %{n_id: n_id}) do
  #   [parent]
  # end

  # def find_in_children(parent, [%{children: subchildren} = child | children], search) do
  #   case find_in_children(child, subchildren, search) do
  #     [] -> find_in_children(parent, children, search)
  #     path -> [parent | path]
  #   end
  # end
end
