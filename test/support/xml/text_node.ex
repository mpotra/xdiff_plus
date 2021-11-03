defmodule XdiffPlus.Support.XML.TextNode do
  defstruct value: ""

  @type t() :: %__MODULE__{
          value: String.t()
        }

  defimpl Xtree.Protocol do
    def type(_) do
      :text
    end

    def name(_) do
      "#TEXT"
    end

    def value(%{value: value}) do
      value
    end

    def id(_) do
      nil
    end

    def children(_) do
      []
    end
  end

  defimpl XdiffPlus.Support.XML.Protocol do
    def encode!(%{value: value}) do
      value
    end
  end
end
