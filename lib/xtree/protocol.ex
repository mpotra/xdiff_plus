defprotocol Xtree.Protocol do
  @spec name(t()) :: String.t()
  def name(node)

  @spec children(t()) :: list(t())
  def children(node)

  @spec type(t()) :: :element | :text
  def type(node)

  @spec value(t()) :: String.t()
  def value(node)

  @spec id(t()) :: String.t() | nil
  def id(node)
end
