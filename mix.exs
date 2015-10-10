defmodule Feedistiller.Mixfile do
  use Mix.Project

  @description "Download RSS/Atom feeds enclosures."

  def project do
    [app: :feedistiller,
     version: "0.0.2",
     description: @description,
     package: package,
     elixir: "~> 1.1",
     escript: escript_config,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :tzdata, :httpoison, :feeder_ex],
     mod: {Feedistiller.Supervisor, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:alambic, "~> 0.0.1"},
      {:httpoison, "~> 0.7.2"},
      {:feeder_ex, "~> 0.0.2"},
      {:timex, "~> 0.19.5"}
    ]
  end

  # Main
  defp escript_config do
    [main_module: Feedistiller.CLI]
  end

  # Package
  defp package do
    [maintainers: ["Serge Danzanvilliers"],
     licenses: ["Apache 2.0"],
     links: %{"Github" => "https://github.com/sdanzan/feedistiller"}]
  end
end
