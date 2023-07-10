defmodule Ankh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ankh,
      version: "0.17.0",
      elixir: "~> 1.12",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Pure Elixir HTTP/2 implementation",
      package: package(),
      deps: deps(),
      docs: docs(),
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
      extra_applications: [:crypto, :inets, :logger, :ssl]
    ]
  end

  defp deps do
    [
      {:castore, "~> 1.0"},
      {:hpax, "~> 0.2"},
      {:plug, "~> 1.0"},
      {:credo, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.30.1", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end

  defp docs do
    [
      groups_for_modules: [
        HTTP1: [~r/^Ankh\.Protocol\.HTTP1\.*/],
        HTTP2: [~r/^Ankh\.Protocol\.HTTP2\.*/],
        Internals: [~r/^Ankh\.Protocol$/, ~r/^Ankh\.Transport$/],
        Transports: [~r/Ankh\.Transport\.*/]
      ]
    ]
  end
end
