defmodule Ankh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ankh,
      version: "0.0.1",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      package: package,
      deps: deps
    ]
  end

  defp package do
    [
      maintainers: ["Luca Corti"],
      licenses: ["MIT"],
      links: %{ "GitHub": "https://github.com/lucacorti/ankh" }
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger, :ssl]]
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
    [{:hpack, "~> 1.0.2"}]
  end
end
