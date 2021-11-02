defmodule XdiffPlus do
  @moduledoc """
  X-tree Diff+: Efficient Change Detection Algorithm in XML Documents
  Suk Kyoon Lee°, Dong Ah Kim
  http://dl.ifip.org/db/conf/euc/euc2006/LeeK06.pdf

  Reference: https://github.com/yidafu/x-tree-diff-plus/blob/master/src/XTreeDiffPlus.ts
  """
  alias Xtree
  alias Xtree.Algorithms

  def diff(%Xtree{} = new_tree, %Xtree{} = old_tree) do
    # build the tree message digest map for the old XTree
    {o_tMD_map, o_id_map, o_op_map} = Algorithms.build_tree_maps(old_tree)
    # build the tree message digest map for the new XTree
    {n_tMD_map, n_id_map, n_op_map} = Algorithms.build_tree_maps(new_tree)

    # Tuple to hold id maps for nodes
    id_maps = {o_id_map, n_id_map}
    # Tuple to hold operation maps for nodes
    op_maps = {n_op_map, o_op_map}

    # build a map of non-unique tMDs of the old XTree (O_HTable)
    o_htable =
      Enum.reduce(o_tMD_map, %{}, fn
        {_tMD, 1}, acc -> acc
        {tMD, _}, acc -> Map.put(acc, tMD, 1)
      end)

    # build maps of unique nodes (N_Htable) and non-unique node IDs (iMD),
    # out of the new X Tree
    {:ok, {n_htable, n_idtable}} =
      Algorithms.dft_traverse(
        new_tree,
        {%{}, %{}},
        fn %{iMD: iMD, id_attr?: id_attr?, tMD: tMD} = node, {n_htable, n_idtable} ->
          n_htable =
            if Map.get(n_tMD_map, tMD) == 1 do
              Map.put(n_htable, tMD, node)
            else
              n_htable
            end

          n_idtable =
            if iMD != nil and id_attr? == true do
              Map.put(n_idtable, iMD, node)
            else
              n_idtable
            end

          {:ok, {n_htable, n_idtable}}
        end
      )

    # try to match nodes with a same iMD values
    {:ok, {m_list, op_maps}} =
      Algorithms.bft_traverse(
        old_tree,
        {%{}, op_maps},
        fn %{
             index: o_index,
             tMD: old_tMD
           } = old_node,
           {m_list, op_maps} = acc ->
          # any entry of O_HTable does NOT have the same tMD value that the node new_node has

          if Map.has_key?(o_htable, old_tMD) == false do
            # old_node is unique in tree

            # some entry of N_Htable has the same tMD value that the node new_node has
            case Map.get(n_htable, old_tMD) do
              nil ->
                # Go on to next node in τ
                {:ok, acc}

              %{index: n_index} = new_node ->
                # subtree node will set Op in step 3
                op =
                  if n_index == o_index do
                    :nop
                  else
                    :mov
                  end

                # Match the nodes N and M using NOP
                op_maps = match_nodes(op_maps, old_node, new_node, op)

                # Add the pair (N, M) of nodes to M_List
                # Stop visiting all the subtrees of the node N,
                # then go on to next node in τ
                {:skip, {Map.put(m_list, old_node, new_node), op_maps}}
            end
          else
            # Go on to next node in τ
            {:ok, acc}
          end
        end
      )

    # matches node with the same iMD
    {:ok, op_maps} =
      Algorithms.bft_traverse(
        old_tree,
        op_maps,
        fn %{iMD: iMD, index: o_index, id_attr?: id_attr?} = old_node, op_maps ->
          # unmatch node after previous sub-step
          if false == Map.has_key?(m_list, old_node) && id_attr? == true do
            case Map.get(n_idtable, iMD, nil) do
              nil ->
                op_maps

              %{index: n_index} = new_node ->
                op = if o_index == n_index, do: :nop, else: :mov

                match_nodes(op_maps, old_node, new_node, op)
            end
          else
            op_maps
          end
        end
      )

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
      |> Enum.reduce(%{}, fn %{n_id: o_node_id, parent_ids: [parent_id | _]} = o_node,
                             s_p_htable ->
        if Map.get(o_op_map, o_node_id) == nil do
          entries = Map.get(s_p_htable, parent_id, [])
          Map.put(s_p_htable, parent_id, [o_node | entries])
        else
          s_p_htable
        end
      end)

    op_maps =
      t_htable
      |> Enum.reduce([], &Enum.concat(elem(&1, 1), &2))
      |> Enum.reduce(op_maps, fn %{
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
      end)

    op_maps
    |> set_defaults({new_tree, old_tree})
    |> dump({new_tree, old_tree})
    |> IO.inspect(label: "FINISHED OP MAPS")
  end

  def diff(_, _) do
    # TODO
  end

  defp dump({n_op_map, o_op_map}, {new_tree, old_tree}) do
    [dump(new_tree, n_op_map), dump(old_tree, o_op_map)]
  end

  defp dump(%{} = tree, %{} = op_map) do
    # {:ok, tree} = Algorithms.walk(tree, fn %{n_id: id, ref: ref} ->
    #   op = Map.get(op_map, id)
    #   {op, ref}
    #   case Map.get(op_map, id) do
    #     {:nop, _id} -> {:nop, ref}
    #     :ins ->
    #   end
    # end)
    op_map
  end

  defp dft_match_remaining_nodes_downwards(
         %{n_id: o_node_id} = o_node,
         {_, o_op_map} = op_maps,
         {_, n_id_map} = _id_maps
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
         {o_id_map, n_id_map} = _id_maps
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
         {o_id_map, n_id_map} = id_maps,
         op_maps
       ) do
    o_parent = Map.get(o_id_map, o_parent_id)
    n_parent = Map.get(n_id_map, n_parent_id)

    if equal_label?(o_parent, n_parent) do
      op_maps = match_nodes(op_maps, o_parent, n_parent, :nop)
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

  defp set_defaults({n_op_map, o_op_map}, {new_tree, old_tree}) do
    {:ok, o_op_map} = Algorithms.bft_traverse(old_tree, o_op_map, &set_default_op(&1, &2, :del))
    {:ok, n_op_map} = Algorithms.bft_traverse(new_tree, n_op_map, &set_default_op(&1, &2, :ins))
    {n_op_map, o_op_map}
  end

  defp set_default_op(%{n_id: id}, op_map, default_op) do
    case Map.get(op_map, id) do
      nil -> Map.put(op_map, id, default_op)
      _ -> op_map
    end
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
