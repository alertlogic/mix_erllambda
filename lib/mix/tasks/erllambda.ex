defmodule Mix.Tasks.Erllambda.Release do
  use Mix.Task

  @shortdoc "Build lambda release of project"
  @moduledoc """
  Build a release package suitable for AWS Lambda deployment.

  This task heavily utilises distillery to build application. Once release is
  built, task applies additional overlays that are necessary to bootstrap
  release as AWS Lambda environment. At the end it creates a zip package
  suitable for AWS lambda deployment with a provided environment.

  ## Usage

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

  ## Details

  Task is built on top of distillery release and has the same command line
  interface. Please note that some of use cases (such as release upgrades) are
  not supported as they don't make sense in AWS lambda universe.

  For full list of available options please read release documentation:

      # mix help release
  """
  alias Mix.Releases.{Release, Config, Assembler, Overlays, Shell, Utils, Errors}

  def run(args) do
    # parse options
    opts = Mix.Tasks.Release.parse_args(args)
    verbosity = Keyword.get(opts, :verbosity)
    Shell.configure(verbosity)

    # make sure we've compiled latest
    Mix.Task.run("compile", [])
    # make sure loadpaths are updated
    Mix.Task.run("loadpaths", [])

    # load release configuration
    Shell.debug("Loading configuration..")

    case Config.get(opts) do
      {:error, {:config, :not_found}} ->
        Shell.error("You are missing a release config file. Run the release.init task first")
        System.halt(1)

      {:error, {:config, reason}} ->
        Shell.error("Failed to load config:\n    #{reason}")
        System.halt(1)

      {:ok, config} ->
        do_release(config)
    end
  end

  defp do_release(config) do
    with {:ok, release} <- assemble(config),
         {:ok, release} <- apply_overlays(release),
         {:ok, _release} <- package(release) do
      :ok
    else
      {:error, _reason} = error ->
        Shell.error(format_error(error))
        System.halt(1)
    end
  rescue
    e ->
      Shell.error(
        "Release failed: #{Exception.message(e)}\n" <>
          Exception.format_stacktrace(System.stacktrace())
      )

      System.halt(1)
  end

  @spec assemble(Config.t()) :: {:ok, Release.t()} | {:error, term}
  defp assemble(config) do
    Shell.info("Assembling release..")
    Assembler.assemble(config)
  end

  @spec apply_overlays(Release.t()) :: {:ok, Release.t()} | {:error, term}
  defp apply_overlays(release) do
    Shell.info("Applying lambda specific overlays..")

    lambda_overlays =
      [{:template, template_path("bootstrap"), "bootstrap"}]

    overlays = lambda_overlays ++ release.profile.overlays
    output_dir = release.profile.output_dir
    overlay_vars = release.profile.overlay_vars

    with {:ok, _paths} <- Overlays.apply(output_dir, overlays, overlay_vars),
         # distillery overlays do not preserve files flags
         :ok <- make_executable(Path.join(output_dir, "bootstrap")),
      do: {:ok, release}
  end

  defp make_executable(path) do
    case File.chmod(path, 0o755) do
      :ok ->
        :ok
      {:error, reason} ->
        {:error, {:chmod, path, reason}}
    end
  end

  @spec package(Release.t()) :: {:ok, Release.t()} | {:error, term}
  defp package(release) do
    Shell.info("Packaging release..")
    with {:ok, tmpdir} <- Utils.insecure_mkdir_temp(),
         tmp_package_path = package_path(release, tmpdir),
         :ok <- make_package(release, tmp_package_path),
         :ok <- file_cp(tmp_package_path, package_path(release)),
         _ <- File.rm_rf(tmpdir),
      do: {:ok, release}
  end

  defp file_cp(src, dst) do
    case File.cp(src, dst) do
      :ok ->
        :ok
      {:error, reason} ->
        {:error, {:file_copy, {src, dst}, reason}}
    end
  end

  defp make_package(release, zip_path) do
    release_dir = Path.expand(release.profile.output_dir)
    targets = targets(release)
    exclusions =
      archive_paths(release)
      |> Enum.map(&(Path.relative_to(&1, release_dir)))

    case make_zip(zip_path, release_dir, targets, exclusions) do
      :ok ->
        Shell.debug("Successfully built zip package: #{zip_path}")
      {:error, reason} ->
        {:error, {:make_zip, reason}}
    end
  end

  defp make_zip(zip_path, cwd, targets, exclusions) do
    args = ["-q", "-r", zip_path] ++ targets ++ ["-x" | exclusions]
    command = "zip #{args |> Enum.join(" ")}"
    Shell.debug("$ #{command}")
    case System.cmd("zip", args, cd: cwd) do
      {_output, 0} ->
        :ok
      {output, exit_code} ->
        {:error, {command, exit_code, output}}
    end
  end

  defp targets(release), do: [
    "erts-#{release.profile.erts_version}",
    "bin",
    "lib",
    "releases",
    "bootstrap"
  ]

  defp archive_paths(release), do: [
    Path.join(Release.version_path(release), "*.tar.gz"),
    Path.join(Release.version_path(release), "*.zip"),
    Path.join(Release.bin_path(release), "*.run")
  ]

  @spec package_path(Release.t()) :: String.t()
  defp package_path(release), do: package_path(release, Release.version_path(release))

  defp package_path(release, base_dir), do: Path.join(base_dir, package_name(release))

  defp package_name(release), do: "#{release.name}.zip"

  defp priv_file(path), do: Path.join("#{:code.priv_dir(:mix_erllambda)}", path)

  defp template_path(name), do: priv_file(Path.join("templates", name))

  @spec format_error(term()) :: String.t()
  defp format_error(error)

  defp format_error({:error, {:chmod, path, reason}}) do
    "Failed to change mode of a file #{path}\n    #{:file.format_error(reason)}"
  end

  defp format_error({:error, {:file_copy, {src, dst}, reason}}) do
    "Failed to copy file: #{:file.format_error(reason)}\n" <>
      "    source: #{src}\n" <>
      "    destination: #{dst}"
  end

  defp format_error({:error, {:make_zip, {command, exit_code, output}}}) do
    "Zip packaging exited with code #{exit_code}:\n" <>
      "    $ #{command}\n" <>
      "    " <> String.trim(output)
  end

  defp format_error(err), do: Errors.format_error(err)
end
