defmodule XdiffPlus.Support.XML do
  alias XdiffPlus.Support.XML.{Element, TextNode}

  @char_space 0x20
  @char_lf 0x0A
  @char_tab 0x09
  @char_ff 0x0C

  defguard is_whitespace(s) when s in [@char_space, @char_lf, @char_tab, @char_ff]

  def parse_string(str, opts \\ []) when is_binary(str) do
    case Saxy.SimpleForm.parse_string(str) do
      {:ok, node} -> build_tree(node, opts)
      error -> error
    end
  end

  def build_tree({tag_name, attrs, children}, opts) do
    children =
      children
      |> Enum.map(&build_tree(&1, opts))
      |> Enum.reject(&(&1 == nil))

    %Element{
      name: tag_name,
      attrs: attrs,
      children: children
    }
  end

  def build_tree(str, _) when is_binary(str) do
    unless whitespace?(str) do
      %TextNode{value: str}
    end
  end

  defp whitespace?(<<>>) do
    true
  end

  defp whitespace?(<<c, rest::binary>>) when is_whitespace(c) do
    whitespace?(rest)
  end

  defp whitespace?(_) do
    false
  end
end
