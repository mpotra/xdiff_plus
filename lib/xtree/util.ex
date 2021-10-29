defmodule Xtree.Util do
  def hash(str) when is_binary(str) do
    :crypto.hash(:md5, str) |> Base.encode16()
  end
end
