defmodule MixErllambdaTest do
  use ExUnit.Case
  doctest MixErllambda

  test "greets the world" do
    assert MixErllambda.hello() == :world
  end
end
