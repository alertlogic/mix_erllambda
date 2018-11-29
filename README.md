# MixErllambda

Elixir OTP release packaging for AWS Lambda.

## Installation

The package can be installed by adding `mix_erllambda` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mix_erllambda, "~> 1.0"}
  ]
end
```

## Usage

Just add as a mix dependency and use `mix erllambda.release`.

### erllambda.release

Build a release package suitable for AWS Lambda deployment.

This task heavily utilises distillery to build application. Once release is
built, task applies additional overlays that are necessary to bootstrap
release as AWS Lambda environment. At the end it creates a zip package
suitable for AWS lambda deployment with a provided environment.

Follow distillery release usage examples to init release for the project:

    # init release
    mix release.init

To create package run erllambda.release with MIX_ENV set to the Mix
environment you are targeting:

    # Builds a release package with MIX_ENV=dev (the default)
    mix erllambda.release

    # Builds a release package with MIX_ENV=prod
    MIX_ENV=prod mix erllambda.release

    # Builds a release package for a specific release environment
    MIX_ENV=prod mix erllambda.release --env=dev

### Details

Task is built on top of distillery release and has the same command line
interface. Please note that some of use cases (such as release upgrades) are
not supported as they don't make sense in AWS lambda universe.

For full list of available options please read release documentation:

    # mix help release

See [Elixir example](https://github.com/alertlogic/erllambda_elixir_example) for details.
