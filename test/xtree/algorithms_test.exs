defmodule Xtree.AlgorithmsTest do
  use ExUnit.Case
  alias XdiffPlus.Support.XML
  alias Xtree
  alias Xtree.Algorithms

  setup do
    xml_str = """
    <menu>
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
          <item id="7" onclick="browser">Open Browser</item>
          <item id="8" onclick="view:default">Show Default Layout</item>
          <item id="9" onclick="view:android" disabled="disabled">Show Android Layout</item>
          <item id="10" onclick="view:ios">Show iOS Layout</item>
        </menu>
      </menu>
      <item id="11" onclick="quit">Quit</item>
    </menu>
    """

    root = XML.parse_string(xml_str, ignore_whitespace: true)

    tree = Xtree.build(root)

    {:ok, %{tree: tree}}
  end

  test "dft_traverse/3", %{tree: tree} do
    assert {:ok, ids} =
             Algorithms.dft_traverse(tree, [], fn %{n_id: n_id}, acc ->
               {:ok, [n_id | acc]}
             end)

    assert ids == Enum.to_list(33..0)

    assert {:halt, ids} =
             Algorithms.dft_traverse(tree, [], fn %{n_id: n_id}, acc ->
               if n_id == 18 do
                 {:halt, [n_id | acc]}
               else
                 {:ok, [n_id | acc]}
               end
             end)

    assert ids == Enum.to_list(18..0)
  end

  test "bft_traverse/3", %{tree: tree} do
    assert {:ok, ids} =
             Algorithms.bft_traverse(tree, [], fn %{n_id: n_id}, acc ->
               {:ok, [n_id | acc]}
             end)

    assert ids == [
             31,
             29,
             27,
             25,
             30,
             28,
             26,
             24,
             22,
             20,
             18,
             16,
             33,
             23,
             21,
             19,
             17,
             15,
             11,
             9,
             7,
             5,
             2,
             32,
             14,
             13,
             12,
             10,
             8,
             6,
             4,
             3,
             1,
             0
           ]

    assert {:halt, ids} =
             Algorithms.bft_traverse(tree, [], fn %{n_id: n_id}, acc ->
               if n_id == 18 do
                 {:halt, [n_id | acc]}
               else
                 {:ok, [n_id | acc]}
               end
             end)

    assert ids == [
             18,
             16,
             33,
             23,
             21,
             19,
             17,
             15,
             11,
             9,
             7,
             5,
             2,
             32,
             14,
             13,
             12,
             10,
             8,
             6,
             4,
             3,
             1,
             0
           ]

    assert {:ok, ids} =
             Algorithms.bft_traverse(tree, [], fn %{n_id: n_id}, acc ->
               if n_id == 10 do
                 {:skip, [n_id | acc]}
               else
                 {:ok, [n_id | acc]}
               end
             end)

    assert ids == [
             31,
             29,
             27,
             25,
             30,
             28,
             26,
             24,
             22,
             20,
             18,
             16,
             33,
             23,
             21,
             19,
             17,
             15,
             9,
             7,
             5,
             2,
             32,
             14,
             13,
             12,
             10,
             8,
             6,
             4,
             3,
             1,
             0
           ]

    assert {:ok, ids} =
             Algorithms.bft_traverse(tree, [], fn %{n_id: n_id}, acc ->
               if n_id == 23 do
                 {:skip, [n_id | acc]}
               else
                 {:ok, [n_id | acc]}
               end
             end)

    assert ids == [
             22,
             20,
             18,
             16,
             33,
             23,
             21,
             19,
             17,
             15,
             11,
             9,
             7,
             5,
             2,
             32,
             14,
             13,
             12,
             10,
             8,
             6,
             4,
             3,
             1,
             0
           ]
  end

  # def simple_form(%{type: :element, n_id: n_id, label: label, children: children}) do
  #   {label, n_id, Enum.map(children, &simple_form/1)}
  # end

  # def simple_form(%{type: :text, n_id: n_id, value: value}) do
  #   {:text, n_id, value}
  # end
end
