defmodule DailyDigestTest do
  use ExUnit.Case
  doctest DailyDigest

  test "greets the world" do
    assert DailyDigest.hello() == :world
  end
end
