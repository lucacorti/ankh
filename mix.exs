defmodule Ankh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ankh,
      version: "0.4.5",
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Pure Elixir HTTP/2 implementation",
      package: package(),
      deps: deps(),
      dialyzer: [
        plt_add_deps: :project,
        ignore_warnings: ".dialyzer.ignore-warnings"
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Luca Corti"],
      licenses: ["MIT"],
      links: %{GitHub: "https://github.com/lucacorti/ankh"}
    ]
  end

  def application do
    [applications: [:logger, :ssl], mod: {Ankh, []}]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 0.5.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:hpack, "~> 1.1.0"},
      {:certifi, "~> 2.0"},
      {:ssl_verify_fun, "~> 1.1"}
    ]
  end
end
