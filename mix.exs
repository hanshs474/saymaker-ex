defmodule SayMaker.MixProject do
  use Mix.Project

  def project do
    [
      app: :saymaker,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Generate images and video from Elixir on SayMaker: Veo 3.1, Kling 3.0, Seedance 2.0, Nano Banana 2 and more with one API key.",
      package: package(),
      docs: [main: "readme", extras: ["README.md"]],
      source_url: "https://github.com/hanshs474/saymaker-ex",
      homepage_url: "https://saymaker.ai/?utm_source=hex&utm_medium=package"
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl, :public_key, :crypto]]
  end

  defp deps do
    [{:ex_doc, "~> 0.34", only: :dev, runtime: false}]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "Website" => "https://saymaker.ai/?utm_source=hex&utm_medium=package",
        "GitHub" => "https://github.com/hanshs474/saymaker-ex"
      },
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end
end
