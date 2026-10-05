defmodule SayMakerTest do
  use ExUnit.Case

  defp fake(pid, final) do
    fn url, body, _key ->
      send(pid, {:body, body})
      if String.ends_with?(url, "/api/ai/generate"),
        do: {:ok, %{"code" => 0, "data" => %{"id" => "row1"}}},
        else: {:ok, %{"code" => 0, "data" => final}}
    end
  end

  test "image prefers the clean file" do
    t = fake(self(), %{"images" => ["m"], "cleanImages" => ["c"]})
    assert {:ok, "c"} = SayMaker.generate("x", api_key: "sk", poll_ms: 0, transport: t)
    assert_received {:body, %{"model" => "saymaker-image-v1"}}
    assert_received {:body, %{"taskId" => "row1"}}
  end

  test "video routes by model" do
    t = fake(self(), %{"videos" => ["v"]})
    assert {:ok, "v"} = SayMaker.generate_video("x", api_key: "sk", duration: 6, poll_ms: 0, transport: t)
    assert_received {:body, %{"provider" => "vgenv", "options" => %{"duration" => 6}}}
  end

  test "classify" do
    assert SayMaker.classify("insufficient credits") == :quota
    assert SayMaker.classify("Your current run is rendering. Plans on the pricing page") == :busy
    assert {:error, :auth, _} = SayMaker.generate("x", api_key: "")
  end
end
