defmodule Jido.Browser.Release do
  @moduledoc false

  @repository_url "https://github.com/agentjido/jido_browser"
  @git_ops_switches [
    build: :string,
    force_patch: :boolean,
    initial: :boolean,
    no_major: :boolean,
    pre_release: :string,
    rc: :boolean,
    dry_run: :boolean,
    yes: :boolean,
    override: :string,
    output: :string
  ]
  @git_ops_aliases [
    i: :initial,
    p: :pre_release,
    b: :build,
    f: :force_patch,
    n: :no_major,
    d: :dry_run,
    y: :yes,
    o: :override
  ]
  @normalizer_switches Keyword.replace!(@git_ops_switches, :override, [:string, :keep])
  @string_options [:build, :pre_release, :override, :output]
  @option_names %{
    build: "build",
    force_patch: "force-patch",
    initial: "initial",
    no_major: "no-major",
    pre_release: "pre-release",
    rc: "rc",
    dry_run: "dry-run",
    yes: "yes",
    override: "override",
    output: "output"
  }

  @doc false
  @spec unreleased_link(String.t()) :: String.t()
  def unreleased_link(version) do
    version = String.trim_leading(version, "v")
    "[Unreleased]: #{@repository_url}/compare/v#{version}...HEAD"
  end

  @doc false
  @spec normalize_args([String.t()], String.t()) :: [String.t()]
  def normalize_args(args, prefix \\ "v") do
    {options, arguments, tail} = normalized_parts(args, prefix)

    Enum.flat_map(options, &canonical_option/1) ++ arguments ++ tail
  end

  @doc false
  @spec override_tag([String.t()], String.t()) :: String.t() | nil
  def override_tag(args, prefix \\ "v") do
    {options, _arguments, _tail} = normalized_parts(args, prefix)
    Keyword.get(options, :override)
  end

  @doc false
  @spec current_version!(String.t(), String.t()) :: String.t()
  def current_version!(repository_path, prefix \\ "v") do
    repository_path
    |> GitOps.Git.init!()
    |> GitOps.Git.tags()
    |> GitOps.Version.last_valid_version(prefix)
    |> case do
      nil -> nil
      tag -> String.trim_leading(tag, prefix)
    end
    |> case do
      nil -> Mix.raise("No current release tag was found.")
      version -> version
    end
  end

  @doc false
  @spec ensure_unreleased_link!(String.t(), String.t()) :: :ok
  def ensure_unreleased_link!(changelog_path, current_version) do
    contents = File.read!(changelog_path)
    expected_link = unreleased_link(current_version)
    lines = String.split(contents, ~r/\r?\n/)

    exact_link_count = Enum.count(lines, &(&1 == expected_link))

    unreleased_link_count =
      Enum.count(lines, &Regex.match?(~r/^\s*\[Unreleased\]\s*:/, &1))

    heading_count = Regex.scan(~r/^## \[Unreleased\][^\r\n]*$/m, contents) |> length()

    section_link_count =
      case Regex.named_captures(
             ~r/^## \[Unreleased\][^\r\n]*\r?\n(?<body>.*?)(?=^## \[|^<!-- changelog -->|\z)/ms,
             contents
           ) do
        %{"body" => body} ->
          body
          |> String.split(~r/\r?\n/)
          |> Enum.count(&(&1 == expected_link))

        nil ->
          0
      end

    if exact_link_count == 1 and unreleased_link_count == 1 and heading_count == 1 and
         section_link_count == 1 do
      :ok
    else
      Mix.raise("Expected exactly one current Unreleased link in #{changelog_path}: #{expected_link}")
    end
  end

  @doc false
  @spec ensure_override_is_new!([String.t()], String.t(), String.t()) :: :ok
  def ensure_override_is_new!(args, repository_path, prefix \\ "v") do
    case override_tag(args, prefix) do
      nil ->
        :ok

      tag ->
        case System.cmd("git", ["rev-parse", "--verify", "--quiet", "refs/tags/#{tag}"],
               cd: repository_path,
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            Mix.raise("Release tag #{tag} already exists; refusing to create a duplicate release section.")

          {_, _} ->
            :ok
        end
    end
  end

  defp normalized_parts(args, prefix) do
    {option_segment, tail} = Enum.split_while(args, &(&1 != "--"))

    option_segment = rewrite_prefixed_compact_overrides(option_segment, prefix)
    {options, arguments} = parse_options!(option_segment)
    options = normalize_override_options!(options, prefix)

    {options, arguments, tail}
  end

  defp rewrite_prefixed_compact_overrides(arguments, ""), do: arguments

  defp rewrite_prefixed_compact_overrides(arguments, prefix) do
    Enum.map(arguments, &rewrite_prefixed_compact_override(&1, prefix))
  end

  defp rewrite_prefixed_compact_override("--" <> _rest = argument, _prefix), do: argument

  defp rewrite_prefixed_compact_override("-" <> _rest = argument, prefix) do
    pattern = Regex.compile!("^(-[ifndy]*o)#{Regex.escape(prefix)}(?=[0-9])")
    candidate = Regex.replace(pattern, argument, "\\1", global: false)

    if candidate != argument and compact_override_group?(candidate), do: candidate, else: argument
  end

  defp rewrite_prefixed_compact_override(argument, _prefix), do: argument

  defp compact_override_group?(argument) do
    case OptionParser.parse([argument], strict: @git_ops_switches, aliases: @git_ops_aliases) do
      {options, [], []} -> Keyword.has_key?(options, :override)
      {_options, _arguments, _invalid} -> false
    end
  end

  defp parse_options!(arguments) do
    {_git_ops_options, positional} =
      OptionParser.parse!(arguments, strict: @git_ops_switches, aliases: @git_ops_aliases)

    {options, ^positional, []} =
      OptionParser.parse(arguments, strict: @normalizer_switches, aliases: @git_ops_aliases)

    {options, positional}
  rescue
    error in OptionParser.ParseError -> Mix.raise(Exception.message(error))
  end

  defp normalize_override_options!(options, prefix) do
    case Keyword.get_values(options, :override) do
      [] ->
        options

      [version] ->
        Enum.map(options, fn
          {:override, ^version} -> {:override, normalize_override!("--override", version, prefix)}
          option -> option
        end)

      _versions ->
        Mix.raise("Provide --override only once.")
    end
  end

  defp normalize_override!(option, version, prefix) do
    if version == "" or String.starts_with?(version, "-") do
      Mix.raise("#{option} requires a semantic version value.")
    end

    bare_version =
      if prefix != "" and String.starts_with?(version, prefix) do
        String.replace_prefix(version, prefix, "")
      else
        version
      end

    case Version.parse(bare_version) do
      {:ok, _version} -> add_prefix(bare_version, prefix)
      :error when bare_version == "" -> Mix.raise("#{option} requires a semantic version value.")
      :error -> Mix.raise("Invalid release version for #{option}: #{inspect(version)}")
    end
  end

  defp canonical_option({option, value}) when option in @string_options do
    ["--#{Map.fetch!(@option_names, option)}=#{value}"]
  end

  defp canonical_option({option, true}), do: ["--#{Map.fetch!(@option_names, option)}"]
  defp canonical_option({option, false}), do: ["--no-#{Map.fetch!(@option_names, option)}"]

  defp add_prefix(version, ""), do: version

  defp add_prefix(version, prefix) do
    if String.starts_with?(version, prefix), do: version, else: prefix <> version
  end
end
