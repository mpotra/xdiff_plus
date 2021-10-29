defmodule XdiffPlus do
  @moduledoc """
  X-tree Diff+: Efficient Change Detection Algorithm in XML Documents
  Suk Kyoon Lee°, Dong Ah Kim
  http://dl.ifip.org/db/conf/euc/euc2006/LeeK06.pdf
  """
  alias Xtree
  alias Xtree.Algorithms

  def diff(%Xtree{} = new_tree, %Xtree{} = old_tree) do
    # Step 1: match identical subtree with 1-to-1 correspondence

    # build the tree message digest map for the old XTree
    {:ok, o_tMD_map} = Algorithms.build_hash_map(old_tree)
    # build a map of non-unique tMDs of the old XTree (O_HTable)
    o_htable =
      Enum.reduce(o_tMD_map, %{}, fn
        {_tMD, 1}, acc -> acc
        {tMD, _}, acc -> Map.put(acc, tMD, 1)
      end)

    # Step 2: Generate maps of unique nodes and node IDs, out of the new X Tree

    # build the tree message digest map for the new XTree
    {:ok, n_tMD_map} = Algorithms.build_hash_map(new_tree)
    # build maps of unique nodes (N_Htable) and non-unique node IDs (iMD)
    {:ok, {n_htable, n_node_ids}} =
      Algorithms.dft_traverse(new_tree, {%{}, %{}}, fn %{iMD: iMD, tMD: tMD} = node,
                                                       {unique_nodes, node_ids} ->
        unique_nodes =
          if Map.get(n_tMD_map, tMD) == 1 do
            Map.put(unique_nodes, tMD, node)
          else
            unique_nodes
          end

        node_ids =
          if iMD != nil do
            Map.put(node_ids, iMD, node)
          else
            node_ids
          end

        {:ok, {unique_nodes, node_ids}}
      end)

    # try to match nodes with a same iMD values
    {:ok, m_list} =
      Algorithms.bft_traverse(old_tree, [], fn %{index: o_index, tMD: old_tMD} = old_node, acc ->
        if Map.has_key?(o_htable, old_tMD) == false do
          # any entry of O_HTable does NOT have the same tMD value that the node new_node has
          # new_node is unique

          # any entry of N_Htable has the same tMD value that the node new_node has
          case Map.get(n_htable, old_tMD) do
            nil ->
              {:continue, acc}

            %{index: n_index} = new_node ->
              # subtree node will set Op in step 3
              op =
                if n_index == o_index do
                  :nop
                else
                  :mov
                end

              # Match the nodes N and M using NOP

              old_node =
                old_node
                |> Map.put(:op, op)
                |> Map.put(:ptr, new_node)

              new_node =
                new_node
                |> Map.put(:op, op)
                |> Map.put(:ptr, old_node)

              # Add the pair (N, M) of nodes to M_List
              # Stop visiting all the subtrees of the node N, then go on to next node in  τ
              {:ok, [{new_node, old_node} | acc]}
          end
        else
          {:continue, acc}
        end
      end)
      |> IO.inspect(label: "BFT TRAVERSE NHTABLE")

    # # matches node with the same iMD
    # XTreeBFTraverse<S>(T_old, (oNode: XTree<S>) => {
    #   // unmatch node after preivuos sub-step
    #   if (!this.M_List.has(oNode)) {
    #     if (typeof oNode.iMD !== 'undefined') {
    #       if (this.N_IDHtable.has(oNode.iMD)) {
    #         const nNode = this.N_IDHtable.get(oNode.iMD)!;
    #         if (oNode.index === nNode.index) {
    #           this.matchNodesWith(nNode, oNode, EditOption.NOP);
    #         } else {
    #           this.matchNodesWith(nNode, oNode, EditOption.MOV);
    #         }
    #       }
    #     }
    #   }
    # });

    # # matches node with the same iMD
    # Algorithms.bft_traverse(old_tree, %{}, fn old_node, acc ->
    #   # unmatch node after preivuos sub-step
    #   if Map.has_key?()
    # end)
  end

  def diff(_, _) do
    # TODO
  end

  def build_tree_hash_map(node) do
    Algorithms.dft_traverse(node, %{}, fn %{tMD: tMD}, tMD_map ->
      tMD_map =
        case Map.get(tMD_map, tMD, nil) do
          nil -> Map.put(tMD_map, tMD, 1)
          value -> Map.put(tMD_map, tMD, value + 1)
        end

      {:ok, tMD_map}
    end)
  end
end
