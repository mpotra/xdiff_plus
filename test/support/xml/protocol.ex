defprotocol XdiffPlus.Support.XML.Protocol do
  @spec encode!(t(), opts :: keyword()) :: String.t()
  def encode!(node, opts)
end
