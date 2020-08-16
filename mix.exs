defmodule Ankh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ankh,
      version: "0.8.11",
      elixir: "~> 1.7",
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
    [extra_applications: [:crypto, :logger, :ssl], mod: {Ankh, []}]
  end

  defp deps do
    [
      {:hpack, "~> 2.0.0"},
      {:castore, "~> 0.1.0"},
      {:credo, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.22.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0.0", only: [:dev], runtime: false}
    ]
  end
end
