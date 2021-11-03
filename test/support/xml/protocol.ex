defprotocol XdiffPlus.Support.XML.Protocol do
  @spec encode!(t()) :: String.t()
  def encode!(node)
end
