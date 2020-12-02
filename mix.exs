defmodule Ankh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ankh,
      version: "0.12.0",
      elixir: "~> 1.8",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Pure Elixir HTTP/2 implementation",
      package: package(),
      deps: deps(),
      dialyzer: [
        plt_add_deps: :apps_direct,
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
    [
      mod: {Ankh, []},
      extra_applications: [:crypto, :inets, :logger, :ssl]
    ]
  end

  defp deps do
    [
      {:castore, "~> 0.1.0"},
      {:hpack, "~> 3.0.0"},
      {:plug, "~> 1.0"},
      {:credo, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.23.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0.0", only: [:dev], runtime: false}
    ]
  end
end
