defmodule MixErllambda.MixProject do
  use Mix.Project

  def project do
    [
      app: :mix_erllambda,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      description: "Elixir OTP release packaging for AWS Lambda",
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [
    ]
  end

  defp deps do
    [
      {:distillery, "~> 2.0"}
    ]
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/alertlogic/mix_erllambda"}
    ]
  end
end
