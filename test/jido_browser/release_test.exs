defmodule Jido.Browser.ReleaseTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Browser.Release
  alias Mix.Tasks.JidoBrowser.Release, as: ReleaseTask

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
  @boolean_aliases ~w(i f n d y)

  @visible_commits [
    "fix(installer): stop on all browser installation failures (#106)",
    "fix(agent_browser): make binary selection deterministic (#104)",
    "fix(agent_browser): support AgentBrowser 0.35.1 daemon payloads (#100)",
    "refactor(session): derive the struct contract from Zoi (#101)",
    "refactor(plugin): define actions and routes once (#99)",
    "deprecate(adapters): publish support tiers and warnings (#108)",
    "security(web_fetch): cap response bytes during transport (#109)",
    "security(web_fetch): enforce destination and redirect policy (#105)"
  ]

  @hidden_commits [
    "ci(agent_browser): require the supported smoke suite",
    "test(coverage): enforce the current coverage baseline",
    "chore(deps): update release dependencies",
    "docs(agent_browser): record transport compatibility"
  ]

  setup do
    original_config = Application.get_all_env(:git_ops)

    directory =
      Path.join(System.tmp_dir!(), "jido_browser_release_#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)

    on_exit(fn ->
      restore_git_ops_config(original_config)
      File.rm_rf!(directory)
    end)

    fixture = initialize_fixture(directory)
    configure_git_ops(fixture)

    {:ok, fixture: fixture}
  end

  test "normalizes bare and prefixed overrides" do
    assert Release.normalize_args(["--override", "2.3.0", "--dry-run"]) ==
             ["--override=v2.3.0", "--dry-run"]

    assert Release.normalize_args(["--override", "v2.3.0", "--dry-run"]) ==
             ["--override=v2.3.0", "--dry-run"]

    assert Release.normalize_args(["--override=v2.4.0", "--yes"]) ==
             ["--override=v2.4.0", "--yes"]

    assert Release.normalize_args(["-o", "2.5.0"]) == ["--override=v2.5.0"]

    assert Release.normalize_args(["-o2.6.0", "--dry-run"]) ==
             ["--override=v2.6.0", "--dry-run"]

    assert Release.normalize_args(["-ov2.7.0", "--dry-run"]) ==
             ["--override=v2.7.0", "--dry-run"]

    assert Release.normalize_args(["-o2.8.0+fooov2", "--dry-run"]) ==
             ["--override=v2.8.0+fooov2", "--dry-run"]

    assert Release.normalize_args(["-do2.8.0+fooov2"]) ==
             ["--dry-run", "--override=v2.8.0+fooov2"]

    assert Release.override_tag(["-o2.6.0"]) == "v2.6.0"
    assert Release.override_tag(["-ov2.7.0"]) == "v2.7.0"

    assert Release.normalize_args(["--dry-run", "--build", "build.1"]) ==
             ["--dry-run", "--build=build.1"]

    assert Release.normalize_args(["-dy", "argument-o2.3.0"]) ==
             ["--dry-run", "--yes", "argument-o2.3.0"]

    assert Release.normalize_args(["-d", "--", "-o2.3.0", "--override=2.4.0"]) ==
             ["--dry-run", "--", "-o2.3.0", "--override=2.4.0"]

    assert_raise Mix.Error, ~r/Unknown option/, fn ->
      Release.normalize_args(["-other"])
    end
  end

  test "normalizer matches GitOps for the generated grouped short-option matrix" do
    for aliases <- short_alias_sequences(@boolean_aliases), aliases != [] do
      argument = "-#{Enum.join(aliases)}o2.3.0"
      {git_ops_options, []} = parse_git_ops!([argument])
      normalized_args = Release.normalize_args([argument])
      {normalized_options, []} = parse_git_ops!(normalized_args)

      expected_options =
        Enum.map(git_ops_options, fn
          {:override, "2.3.0"} -> {:override, "v2.3.0"}
          option -> option
        end)

      assert normalized_options == expected_options
      assert Enum.count(normalized_args, &String.starts_with?(&1, "--override=")) == 1
    end
  end

  test "preserves supported options, arguments, and the separator tail" do
    args = [
      "-dy",
      "--build",
      "build.1",
      "-p=rc.1",
      "--no-force-patch",
      "--rc",
      "--output=release-output",
      "argument",
      "--",
      "-o2.3.0",
      "--unknown"
    ]

    assert Release.normalize_args(args) == [
             "--dry-run",
             "--yes",
             "--build=build.1",
             "--pre-release=rc.1",
             "--no-force-patch",
             "--rc",
             "--output=release-output",
             "argument",
             "--",
             "-o2.3.0",
             "--unknown"
           ]

    assert Release.normalize_args(["-db", "build.1", "-p", "rc.1", "-o2.3.0"]) == [
             "--dry-run",
             "--build=build.1",
             "--pre-release=rc.1",
             "--override=v2.3.0"
           ]

    valid_string_aliases = [
      ["-b2.3.0", "-o2.3.0"],
      ["-p2.3.0", "-o2.3.0"],
      ["-db", "build.1", "-o2.3.0"],
      ["-dp", "rc.1", "-o2.3.0"],
      ["-b=build.1", "-p=rc.1", "-o=2.3.0"],
      ["-o2.3.0", "-b2.3.0"]
    ]

    for string_aliases <- valid_string_aliases do
      {git_ops_options, []} = parse_git_ops!(string_aliases)
      {normalized_options, []} = string_aliases |> Release.normalize_args() |> parse_git_ops!()

      assert normalized_options ==
               Enum.map(git_ops_options, fn
                 {:override, "2.3.0"} -> {:override, "v2.3.0"}
                 option -> option
               end)
    end

    for args <- [["-bo2.3.0"], ["-po2.3.0"], ["-ob2.3.0"], ["-op2.3.0"]] do
      assert_raise OptionParser.ParseError, fn -> parse_git_ops!(args) end
      assert_raise Mix.Error, fn -> Release.normalize_args(args) end
    end
  end

  test "grouped compact overrides run through the repository task and stay clean", %{
    fixture: fixture
  } do
    compact_overrides = [
      "-o2.3.0",
      "-ov2.3.0",
      "-fo2.3.0",
      "-no2.3.0",
      "-do2.3.0",
      "-yo2.3.0",
      "-fndyo2.3.0",
      "-ydnfo2.3.0",
      "-fndyov2.3.0"
    ]

    Enum.each(compact_overrides, fn compact_override ->
      before_dry_run = repository_state(fixture)
      output = run_release([compact_override, "--dry-run"])

      assert repository_state(fixture) == before_dry_run
      assert output =~ release_heading("v2.3.0", "v2.2.0")
      assert output =~ Release.unreleased_link("2.3.0")
    end)

    for initial_group <- ["-io2.3.0", "-ifndyo2.3.0"] do
      normalized_args = Release.normalize_args([initial_group, "--dry-run"])
      assert Enum.count(normalized_args, &String.starts_with?(&1, "--override=")) == 1
      before_initial = repository_state(fixture)

      assert_raise RuntimeError, ~r/File already exists/, fn ->
        run_release([initial_group, "--dry-run"])
      end

      assert repository_state(fixture) == before_initial
    end

    before_automatic_dry_run = repository_state(fixture)
    output = run_release(["-dy", "argument-o2.3.0", "--", "-o2.3.0"])

    assert repository_state(fixture) == before_automatic_dry_run
    assert output =~ release_heading("v2.2.1", "v2.2.0")
  end

  test "supported override and string option forms run through the repository task", %{
    fixture: fixture
  } do
    argument_forms = [
      ["--override=2.3.0", "--dry-run"],
      ["-o", "2.3.0", "-d"],
      ["-o=2.3.0", "-d"],
      ["-db", "build.1", "-p", "rc.1", "-o2.3.0"]
    ]

    Enum.each(argument_forms, fn args ->
      before_dry_run = repository_state(fixture)
      output = run_release(args)

      assert repository_state(fixture) == before_dry_run
      assert output =~ release_heading("v2.3.0", "v2.2.0")
      assert output =~ Release.unreleased_link("2.3.0")
    end)
  end

  test "rejects missing and malformed overrides before any change", %{fixture: fixture} do
    invalid_overrides = [
      {["--override"], ~r/(Missing argument of type string|requires a semantic version value)/},
      {["--override", "--dry-run"], ~r/(Missing argument of type string|requires a semantic version value)/},
      {["--override="], ~r/(Missing argument of type string|requires a semantic version value)/},
      {["-o"], ~r/(Missing argument of type string|requires a semantic version value)/},
      {["--override", "2.3"], ~r/Invalid release version/},
      {["--override=v2.3.0.1"], ~r/Invalid release version/},
      {["-o", "vv2.3.0"], ~r/Invalid release version/},
      {["-ov"], ~r/Missing argument of type string/},
      {["-ovv2.3.0"], ~r/Missing argument of type string/},
      {["-o2.3"], ~r/Invalid release version/},
      {["-o2.3.0.1"], ~r/Invalid release version/},
      {["-o02.3.0"], ~r/Invalid release version/},
      {["-fo2.3"], ~r/Invalid release version/},
      {["-dov"], ~r/Missing argument of type string/},
      {["-dovv2.3.0"], ~r/Missing argument of type string/},
      {["-do2.3.0.1"], ~r/Invalid release version/},
      {["-bo2.3.0"], ~r/Missing argument of type string/},
      {["-po2.3.0"], ~r/Missing argument of type string/},
      {["-ob2.3.0"], ~r/Missing argument of type string/},
      {["-op2.3.0"], ~r/Missing argument of type string/},
      {["-other"], ~r/Unknown option/}
    ]

    Enum.each(invalid_overrides, fn {args, message} ->
      before_failure = repository_state(fixture)

      assert_raise Mix.Error, message, fn ->
        run_release(args)
      end

      assert repository_state(fixture) == before_failure
    end)

    before_prefixed_dry_run = repository_state(fixture)
    output = run_release(["--override", "v2.3.0", "--dry-run"])

    assert repository_state(fixture) == before_prefixed_dry_run
    assert output =~ release_heading("v2.3.0", "v2.2.0")
  end

  test "rejects compact overrides combined with another override before any change", %{
    fixture: fixture
  } do
    duplicate_overrides = [
      ["-o2.3.0", "--override", "2.4.0", "--dry-run"],
      ["-ov2.3.0", "--override=2.4.0", "--dry-run"],
      ["-o2.3.0", "-o=2.4.0", "--dry-run"],
      ["-ov2.3.0", "-o", "2.4.0", "--dry-run"],
      ["-do2.3.0", "--override=2.4.0", "--dry-run"],
      ["-fndyov2.3.0", "-o2.4.0", "--dry-run"]
    ]

    Enum.each(duplicate_overrides, fn args ->
      before_failure = repository_state(fixture)

      assert_raise Mix.Error, ~r/Provide --override only once/, fn ->
        run_release(args)
      end

      assert repository_state(fixture) == before_failure
    end)
  end

  test "fails cleanly when the current Unreleased link is missing", %{fixture: fixture} do
    contents = File.read!(fixture.changelog)
    expected_link = Release.unreleased_link("2.2.0")
    File.write!(fixture.changelog, String.replace(contents, expected_link <> "\n", ""))

    assert_link_guard_failure(fixture)
  end

  test "fails cleanly when the current Unreleased link is malformed", %{fixture: fixture} do
    contents = File.read!(fixture.changelog)
    expected_link = Release.unreleased_link("2.2.0")
    malformed_link = String.replace(expected_link, "v2.2.0...HEAD", "2.2.0...HEAD")
    File.write!(fixture.changelog, String.replace(contents, expected_link, malformed_link))

    assert_link_guard_failure(fixture)
  end

  test "fails cleanly when the current Unreleased link is duplicated", %{fixture: fixture} do
    contents = File.read!(fixture.changelog)
    expected_link = Release.unreleased_link("2.2.0")
    duplicate_links = Enum.join([expected_link, expected_link], "\n")
    File.write!(fixture.changelog, String.replace(contents, expected_link, duplicate_links))

    assert_link_guard_failure(fixture)
  end

  test "does not replace a current link in changelog history", %{fixture: fixture} do
    contents = File.read!(fixture.changelog)
    expected_link = Release.unreleased_link("2.2.0")

    historical_link = "<!-- changelog -->\n\n#{expected_link}"

    contents =
      contents
      |> String.replace(expected_link <> "\n\n<!-- changelog -->", historical_link)

    File.write!(fixture.changelog, contents)

    assert_link_guard_failure(fixture)
  end

  test "dry run is clean and a real release keeps complete version links", %{fixture: fixture} do
    before_dry_run = repository_state(fixture)
    dry_run_output = run_release(["--override", "2.3.0", "--dry-run"])

    assert repository_state(fixture) == before_dry_run
    assert dry_run_output =~ release_heading("v2.3.0", "v2.2.0")
    assert dry_run_output =~ Release.unreleased_link("2.3.0")
    assert_visible_entries(dry_run_output)
    refute_hidden_entries(dry_run_output)

    head_before_release = git!(fixture.directory, ["rev-parse", "HEAD"])
    run_release(["--override", "2.3.0", "--yes"])

    assert git!(fixture.directory, ["rev-list", "--count", "#{head_before_release}..HEAD"]) == "1"

    assert git!(fixture.directory, ["log", "-1", "--pretty=%s"]) ==
             "chore: release version v2.3.0"

    assert git!(fixture.directory, ["cat-file", "-t", "v2.3.0"]) == "tag"

    assert git!(fixture.directory, ["rev-list", "-n", "1", "v2.3.0"]) ==
             git!(fixture.directory, ["rev-parse", "HEAD"])

    assert git!(fixture.directory, ["status", "--porcelain"]) == ""

    changelog = File.read!(fixture.changelog)
    assert changelog =~ Release.unreleased_link("2.3.0")
    assert changelog =~ release_heading("v2.3.0", "v2.2.0")
    assert heading_count(changelog, "v2.3.0") == 1
    assert release_entry_count(changelog, "v2.3.0") == 8
    assert_visible_entries(changelog)
    refute_hidden_entries(changelog)
    assert File.read!(fixture.mix_project) =~ ~s(@version "2.3.0")
    assert File.read!(fixture.readme) =~ ~s({:jido_browser, "~> 2.3.0"})

    released_state = repository_state(fixture)

    assert_raise Mix.Error, ~r/Release tag v2\.3\.0 already exists/, fn ->
      run_release(["--override", "2.3.0", "--dry-run"])
    end

    assert repository_state(fixture) == released_state
    assert heading_count(File.read!(fixture.changelog), "v2.3.0") == 1
  end

  test "the same source releases a later version", %{fixture: fixture} do
    later_fixture =
      fixture.directory
      |> Path.join("later")
      |> initialize_fixture(
        current_version: "2.3.0",
        previous_version: "2.2.0",
        commits: ["fix(release_fixture): prove later release"]
      )

    configure_git_ops(later_fixture)

    before_dry_run = repository_state(later_fixture)
    dry_run_output = run_release(["--override", "2.4.0", "--dry-run"])

    assert repository_state(later_fixture) == before_dry_run
    assert dry_run_output =~ release_heading("v2.4.0", "v2.3.0")
    assert dry_run_output =~ Release.unreleased_link("2.4.0")

    run_release(["--override", "2.4.0", "--yes"])

    later_changelog = File.read!(later_fixture.changelog)
    assert later_changelog =~ Release.unreleased_link("2.4.0")
    assert later_changelog =~ release_heading("v2.4.0", "v2.3.0")
    assert heading_count(later_changelog, "v2.4.0") == 1
    assert heading_count(later_changelog, "v2.3.0") == 1
    assert git!(later_fixture.directory, ["cat-file", "-t", "v2.4.0"]) == "tag"
    assert File.read!(later_fixture.mix_project) =~ ~s(@version "2.4.0")
    assert File.read!(later_fixture.readme) =~ ~s({:jido_browser, "~> 2.4.0"})

    released_state = repository_state(later_fixture)

    assert_raise Mix.Error, ~r/Release tag v2\.4\.0 already exists/, fn ->
      run_release(["--override", "2.4.0", "--dry-run"])
    end

    assert repository_state(later_fixture) == released_state
    assert heading_count(File.read!(later_fixture.changelog), "v2.4.0") == 1
  end

  defp initialize_fixture(directory, opts \\ []) do
    current_version = Keyword.get(opts, :current_version, "2.2.0")
    previous_version = Keyword.get(opts, :previous_version, "2.1.0")
    commits = Keyword.get(opts, :commits, @visible_commits ++ @hidden_commits)

    File.mkdir_p!(directory)

    changelog = Path.join(directory, "CHANGELOG.md")
    mix_project = Path.join(directory, "mix.exs")
    readme = Path.join(directory, "README.md")
    module = Module.concat(__MODULE__, "MixProject#{System.unique_integer([:positive])}")

    File.write!(changelog, initial_changelog(current_version, previous_version))

    File.write!(
      mix_project,
      """
      defmodule #{inspect(module)} do
        @version "#{current_version}"
        def project, do: [version: @version]
      end
      """
    )

    File.write!(readme, ~s({:jido_browser, "~> #{current_version}"}\n))

    git!(directory, ["init", "--initial-branch=main"])
    git!(directory, ["config", "user.name", "Release Test"])
    git!(directory, ["config", "user.email", "release-test@example.com"])
    git!(directory, ["add", "CHANGELOG.md", "mix.exs", "README.md"])
    git!(directory, ["commit", "-m", "chore: initial release fixture"])
    git!(directory, ["tag", "-a", "v#{current_version}", "-m", "release v#{current_version}"])

    Enum.each(commits, &commit!(directory, &1))

    Code.compile_file(mix_project)

    %{
      directory: directory,
      changelog: changelog,
      mix_project: mix_project,
      readme: readme,
      module: module
    }
  end

  defp configure_git_ops(fixture) do
    Application.put_all_env(
      git_ops: [
        mix_project: fixture.module,
        changelog_file: fixture.changelog,
        repository_url: @repository_url,
        repository_path: fixture.directory,
        manage_mix_version?: true,
        manage_readme_version: fixture.readme,
        managed_files: [
          {fixture.changelog, fn version -> Release.unreleased_link(version) end,
           fn version -> Release.unreleased_link(version) end}
        ],
        version_tag_prefix: "v",
        version_source: :tags,
        github_handle_lookup?: false,
        types: [
          feat: [header: "Features"],
          fix: [header: "Bug Fixes"],
          perf: [header: "Performance"],
          refactor: [header: "Refactoring"],
          security: [header: "Security"],
          deprecate: [header: "Deprecated"],
          deps: [hidden?: true],
          docs: [hidden?: true],
          test: [hidden?: true],
          chore: [hidden?: true],
          ci: [hidden?: true]
        ]
      ]
    )
  end

  defp restore_git_ops_config(config) do
    :git_ops
    |> Application.get_all_env()
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(:git_ops, &1))

    Enum.each(config, fn {key, value} -> Application.put_env(:git_ops, key, value) end)
  end

  defp run_release(args) do
    Mix.Task.reenable("git_ops.release")
    capture_io(fn -> ReleaseTask.run(args) end)
  end

  defp parse_git_ops!(args) do
    OptionParser.parse!(args, strict: @git_ops_switches, aliases: @git_ops_aliases)
  end

  defp short_alias_sequences([]), do: [[]]

  defp short_alias_sequences(aliases) do
    [
      []
      | for(
          short <- aliases,
          rest <- short_alias_sequences(List.delete(aliases, short)),
          do: [short | rest]
        )
    ]
  end

  defp repository_state(fixture) do
    %{
      head: git!(fixture.directory, ["rev-parse", "HEAD"]),
      status: git!(fixture.directory, ["status", "--porcelain"]),
      tags: git!(fixture.directory, ["tag", "--list", "--sort=refname"]),
      changelog: File.read!(fixture.changelog),
      mix_project: File.read!(fixture.mix_project),
      readme: File.read!(fixture.readme)
    }
  end

  defp assert_link_guard_failure(fixture) do
    before_failure = repository_state(fixture)

    assert_raise Mix.Error, ~r/Expected exactly one current Unreleased link/, fn ->
      run_release(["--override", "2.3.0", "--yes"])
    end

    assert repository_state(fixture) == before_failure
  end

  defp commit!(directory, message) do
    git!(directory, ["commit", "--allow-empty", "-m", message])
  end

  defp git!(directory, args) do
    case System.cmd("git", args, cd: directory, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{Enum.join(args, " ")} failed with #{status}: #{output}"
    end
  end

  defp release_heading(version, previous_version) do
    "## [#{version}](#{@repository_url}/compare/#{previous_version}...#{version})"
  end

  defp heading_count(changelog, version) do
    Regex.scan(~r/^## \[#{Regex.escape(version)}\]/m, changelog) |> length()
  end

  defp release_entry_count(changelog, version) do
    changelog
    |> String.split(~r/^## \[#{Regex.escape(version)}\].*$/m, parts: 2)
    |> List.last()
    |> String.split(~r/^## \[/m, parts: 2)
    |> List.first()
    |> then(&Regex.scan(~r/^\* /m, &1))
    |> length()
  end

  defp assert_visible_entries(contents) do
    Enum.each(@visible_commits, fn commit ->
      [type_and_scope, message] = String.split(commit, ": ", parts: 2)
      scope = type_and_scope |> String.split("(", parts: 2) |> List.last() |> String.trim_trailing(")")
      assert contents =~ "* #{scope}: #{message} by Release Test"
    end)
  end

  defp refute_hidden_entries(contents) do
    Enum.each(@hidden_commits, fn commit ->
      [_type_and_scope, message] = String.split(commit, ": ", parts: 2)
      refute contents =~ message
    end)
  end

  defp initial_changelog(current_version, previous_version) do
    """
    # Changelog

    ## [Unreleased]

    #{Release.unreleased_link(current_version)}

    <!-- changelog -->

    ## [v#{current_version}](#{@repository_url}/compare/v#{previous_version}...v#{current_version}) (2026-08-10)

    ### Bug Fixes:

    * previous release fixture by Release Test
    """
  end
end
