defmodule MyBench do
  def while(fun) do
    if fun.() do
      while(fun)
    end
  end
end
