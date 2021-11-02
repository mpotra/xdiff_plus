defmodule XdiffPlusTest do
  use ExUnit.Case
  alias XdiffPlus.Support.XML
  alias Xtree
  alias XdiffPlus

  doctest XdiffPlus

  test "builds a XTree" do
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

    assert %Xtree{} = Xtree.build(root)
  end

  test "diff" do
    old_xml_str = """
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

    new_xml_str = """
    <menu>
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
      <item id="11" onclick="quits">Quit2</item>
    </menu>
    """

    old_xml = XML.parse_string(old_xml_str, ignore_whitespace: true)
    new_xml = XML.parse_string(new_xml_str, ignore_whitespace: true)

    old_tree = Xtree.build(old_xml)
    new_tree = Xtree.build(new_xml)

    IO.inspect(simple_form(new_tree), label: "new tree")
    IO.inspect(simple_form(old_tree), label: "old tree")

    XdiffPlus.diff(new_tree, old_tree)
  end

  def simple_form(%{tMD: tMD, type: :element, n_id: n_id, label: label, children: children}) do
    {label, n_id, tMD, Enum.map(children, &simple_form/1)}
  end

  def simple_form(%{type: :text, n_id: n_id, value: value}) do
    {:text, n_id, value}
  end
end
