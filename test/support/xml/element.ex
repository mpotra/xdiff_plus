defmodule XdiffPlus.Support.XML.Element do
  alias XdiffPlus.Support.XML.TextNode

  defstruct name: "",
            attrs: [],
            children: []

  @type t() :: %__MODULE__{
          name: String.t(),
          attrs: list(),
          children: list(t() | TextNode.t())
        }

  defimpl Xtree.Protocol do
    def type(_) do
      :element
    end

    def name(%{name: name}) do
      name
    end

    def value(%{attrs: attrs}) do
      attrs
      |> Enum.map(fn {name, value} -> "#{name}=#{value}" end)
      |> Enum.join(";")
    end

    def id(%{attrs: attrs}) do
      case find_id_attr(attrs) do
        nil -> nil
        {_, value} -> value
      end
    end

    def children(%{children: children}) do
      children
    end

    defp find_id_attr(attrs) do
      Enum.find(attrs, fn
        {"id", _} -> true
        _ -> false
      end)
    end
  end
end
