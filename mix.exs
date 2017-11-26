defmodule Ankh.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ankh,
      version: "0.4.0",
      elixir: "~> 1.5",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      description: "Pure Elixir HTTP/2 implementation",
      package: package(),
      deps: deps()
    ]
  end

  defp package do
    [
      maintainers: ["Luca Corti"],
      licenses: ["MIT"],
      links: %{ "GitHub": "https://github.com/lucacorti/ankh" }
    ]
  end

  def application do
    [applications: [:logger, :ssl],
    mod: {Ankh, []}]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:credo, ">= 0.0.0", only: :dev},
      {:dialyxir, ">= 0.0.0", only: :dev},
      {:hpack, "~> 1.0.3", only: :test},
      {:certifi, "~> 2.0"},
      {:ssl_verify_fun, "~> 1.1"}
    ]
  end
end
