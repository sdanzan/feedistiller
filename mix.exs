defmodule Feedistiller.Mixfile do
  use Mix.Project

  @description "Download RSS/Atom feeds enclosures."

  def project do
    [app: :feedistiller,
     version: "3.2.0",
     description: @description,
     package: package(),
     elixir: ">= 1.11.0",
     escript: escript_config(),
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: [coveralls: :test],
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:crypto, :logger, :tzdata, :httpoison, :timex, :alambic, :feeder],
     extra_applications: [:wx, :gen_stage],
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
      {:alambic, "~> 1.1.0"},
      {:gen_stage, "~> 1.0.0"},
      {:httpoison, "~> 1.8.0"},
      {:feeder, "~> 2.3.2"},
      {:timex, "~> 3.6.3"},
      {:yaml_elixir, "~> 2.5.0"},
      # Uncomment following line if you want to build the escript
      # {:tzdata, "== 0.1.8", override: true},
      {:earmark, "~> 1.4.12", only: :docs},
      {:ex_doc, "~> 0.23.0", only: :docs},
      {:mock, "~> 0.3.6", only: :test},
      {:excoveralls, "~> 0.13.4", only: :test}
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
