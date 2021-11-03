defmodule XdiffPlusTest do
  use ExUnit.Case
  alias XdiffPlus.Support.XML
  alias Xtree
  alias XdiffPlus

  doctest XdiffPlus

  setup do
    old_xml_str = """
    <menu name="some_menu">
      <item onclick="edit">Open</item>
      <hr/>
      <item onclick="toggle:1">Item 1</item>
      <item onclick="toggle:2">Item 2</item>
      <item onclick="toggle:3" disabled="disabled">Item 3</item>
      <item onclick="toggle:4">Item 4</item>
      <hr/>
      <hr/>
      <menu id="6" label="View">
        <item id="7" onclick="browser">Open Browser</item>
        <item id="8" onclick="view:default">Show Default Layout</item>
        <item id="9" onclick="view:android" disabled="disabled">Show Android Layout</item>
        <item id="10" onclick="view:ios">Show iOS Layout</item>
        <menu id="66" label="View">
          <item onclick="browser">Open Browser</item>
          <item id="68" onclick="view:default">Show Default Layout</item>
          <item id="69" onclick="view:android" disabled="disabled">Show Android Layout</item>
          <item id="70" onclick="view:ios">Show iOS Layout</item>
        </menu>
      </menu>
      <item onclick="quit">Quit</item>
    </menu>
    """

    new_xml_str = """
    <menu name="some_menu">
      <item onclick="edit">Open</item>
      <hr/>
      <item onclick="toggle:1">Item 1</item>
      <item onclick="toggle:2">Item 2</item>
      <item onclick="toggle:3" disabled="disabled">Item 3</item>
      <item onclick="toggle:5">Item 4</item>
      <hr/>
      <a href="x"></a>
      <menu id="6" label="View">
        <item id="7" onclick="browser">Open Browser</item>
        <item id="89" onclick="view:default">Show Default Layout (x)</item>
        <item id="9" onclick="view:android" disabled="disabled">Show Android Layout</item>
        <item id="10" onclick="view:ios">Show iOS Layout</item>
        <menu id="66" label="View">
          <item onclick="browser3">Open Browser</item>
          <item id="68" onclick="view:default">Show Default Layout</item>
          <item id="69" onclick="view:android" disabled="disabled">Show Android Layout</item>
          <item id="70" onclick="view:ios">Show iOS Layout</item>
        </menu>
      </menu>
      <item onclick="quits">Quit2</item>
    </menu>
    """

    old_xml = XML.parse_string(old_xml_str, ignore_whitespace: true)
    new_xml = XML.parse_string(new_xml_str, ignore_whitespace: true)

    old_tree = Xtree.build(old_xml)
    new_tree = Xtree.build(new_xml)

    {:ok, new_tree_count} = Xtree.Algorithms.dft_traverse(new_tree, 0, fn _, acc -> acc + 1 end)
    {:ok, old_tree_count} = Xtree.Algorithms.dft_traverse(old_tree, 0, fn _, acc -> acc + 1 end)

    {:ok,
     %{
       new: new_tree,
       new_count: new_tree_count,
       old_count: old_tree_count,
       old: old_tree
     }}
  end

  test "diff with empty old tree", %{new: new_tree, new_count: new_count} do
    assert [{new_op_map, old_op_map}, {^new_tree, nil}] = XdiffPlus.diff(new_tree, nil)
    assert old_op_map == %{}
    assert new_op_map != %{}
    assert new_count == Enum.count(Map.keys(new_op_map))
    assert Enum.all?(new_op_map, fn {_node, op} -> elem(op, 0) == :ins end)
  end

  test "diff with empty new tree", %{old: old_tree, old_count: old_count} do
    assert [{new_op_map, old_op_map}, {nil, ^old_tree}] = XdiffPlus.diff(nil, old_tree)
    assert new_op_map == %{}
    assert old_op_map != %{}
    assert old_count == Enum.count(Map.keys(old_op_map))
    assert Enum.all?(old_op_map, fn {_node, op} -> op == :del end)
  end

  test "diff", %{new: new_tree, old: old_tree, new_count: new_count, old_count: old_count} do
    # IO.inspect(simple_form(new_tree), label: "new tree")
    # IO.inspect(simple_form(old_tree), label: "old tree")

    assert [{new_op_map, old_op_map}, {^new_tree, ^old_tree}] = XdiffPlus.diff(new_tree, old_tree)
    assert new_op_map != %{}
    assert new_count == Enum.count(Map.keys(new_op_map))
    assert old_op_map != %{}
    assert old_count == Enum.count(Map.keys(old_op_map))

    new_ops =
      new_op_map
      |> to_list()
      |> group_ops()

    assert Map.get(new_ops, :ins) == [{"<a href=\"x\"/>", "<menu name=\"some_menu\"/>", "<hr/>"}]
    assert Map.get(new_ops, :del) == nil

    assert Map.get(new_ops, :upd) == [
             {"<item id=\"89\" onclick=\"view:default\"/>",
              "<item id=\"8\" onclick=\"view:default\"/>"},
             {"<item onclick=\"browser3\"/>", "<item onclick=\"browser\"/>"},
             {"<item onclick=\"quits\"/>", "<item onclick=\"quit\"/>"},
             {"<item onclick=\"toggle:5\"/>", "<item onclick=\"toggle:4\"/>"},
             {"Quit2", "Quit"},
             {"Show Default Layout (x)", "Show Default Layout"}
           ]

    old_ops =
      old_op_map
      |> to_list()
      |> group_ops()

    assert Map.get(old_ops, :ins) == nil
    assert Map.get(old_ops, :del) == [{"<hr/>", ""}]

    assert Map.get(old_ops, :upd) == [
             {"<item id=\"8\" onclick=\"view:default\"/>",
              "<item id=\"89\" onclick=\"view:default\"/>"},
             {"<item onclick=\"browser\"/>", "<item onclick=\"browser3\"/>"},
             {"<item onclick=\"quit\"/>", "<item onclick=\"quits\"/>"},
             {"<item onclick=\"toggle:4\"/>", "<item onclick=\"toggle:5\"/>"},
             {"Quit", "Quit2"},
             {"Show Default Layout", "Show Default Layout (x)"}
           ]
  end

  defp to_list(op_map) do
    Enum.reduce(op_map, [], fn
      {node, {:ins, parent_node, prev_node}}, acc ->
        [{:ins, encode!(node), encode!(parent_node), encode!(prev_node)} | acc]

      {node, {op, match_node}}, acc ->
        [{op, encode!(node), encode!(match_node)} | acc]

      {node, op}, acc when is_atom(op) ->
        [{op, encode!(node), ""} | acc]

      _, acc ->
        acc
    end)
  end

  defp group_ops(op_list) do
    op_list
    |> Enum.reduce(%{}, fn
      {op, a, b}, acc ->
        Map.update(acc, op, [{a, b}], &[{a, b} | &1])

      {:ins, node, parent, prev}, acc ->
        Map.update(acc, :ins, [{node, parent, prev}], &[{node, parent, prev} | &1])
    end)
    |> Enum.reduce(%{}, fn {key, pairs}, acc ->
      sorted_pairs = Enum.sort(pairs, &sort_pair/2)

      Map.put(acc, key, sorted_pairs)
    end)
  end

  defp sort_pair({a1, a2}, {a1, b2}) do
    a2 < b2
  end

  defp sort_pair({a1, _}, {b1, _}) do
    a1 < b1
  end

  defp encode!(%Xtree{ref: xml_node}) do
    XML.encode!(xml_node, skip_children: true)
  end

  defp encode!(nil) do
    nil
  end

  # defp simple_form(%{tMD: tMD, type: :element, n_id: n_id, label: label, children: children}) do
  #   {label, n_id, tMD, Enum.map(children, &simple_form/1)}
  # end

  # defp simple_form(%{type: :text, tMD: tMD, n_id: n_id, value: value}) do
  #   {:text, tMD, n_id, value}
  # end
end
