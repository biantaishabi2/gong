defmodule Gong.HeaderProfileTest do
  use ExUnit.Case, async: true

  alias Gong.HeaderProfile

  describe "resolve/1" do
    test "default 返回空 map" do
      assert HeaderProfile.resolve(:default) == %{}
    end

    test "opencode 返回三个指纹头" do
      headers = HeaderProfile.resolve(:opencode)

      assert headers == %{
               "User-Agent" => "OpenCode/1.0",
               "X-Client-Name" => "opencode",
               "Accept" => "application/json"
             }
    end

    test "未知 profile 回退到 default" do
      assert HeaderProfile.resolve(:unknown) == %{}
      assert HeaderProfile.resolve(:foobar) == %{}
    end
  end
end
