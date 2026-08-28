defmodule Jido.Browser.GeneratedReleaseValidatorTest do
  use ExUnit.Case, async: true

  @repository_url "https://github.com/agentjido/jido_browser"
  @release_date "2026-08-28"

  test "accepts the exact generated release output" do
    fixture = release_fixture()

    assert {output, 0} = run_validator(fixture)
    assert output =~ "Validated exact generated release output for v2.4.0 from v2.3.0."
  end

  test "rejects a manual changelog entry" do
    fixture = release_fixture(entry: "fetch: manually written text (#1)")

    assert {output, status} = run_validator(fixture)
    assert status != 0
    assert output =~ "does not contain one generated entry"
  end

  test "rejects an extra generated path" do
    fixture = release_fixture(extra_path: true)

    assert {output, status} = run_validator(fixture)
    assert status != 0
    assert output =~ "changed unexpected paths"
  end

  defp release_fixture(options \\ []) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "jido_browser_generated_release_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(directory) end)
    File.mkdir_p!(directory)

    File.write!(Path.join(directory, "mix.exs"), mix_project("2.3.0"))
    File.write!(Path.join(directory, "CHANGELOG.md"), parent_changelog())

    git!(directory, ["init", "--initial-branch=main"])
    git!(directory, ["config", "user.name", "Release Test"])
    git!(directory, ["config", "user.email", "release-test@example.com"])
    git!(directory, ["add", "CHANGELOG.md", "mix.exs"])
    git!(directory, ["commit", "-m", "chore: release fixture"])
    git!(directory, ["tag", "-a", "v2.3.0", "-m", "v2.3.0"])
    git!(directory, ["commit", "--allow-empty", "-m", "refactor(fetch): split retrieval (#1)"])

    parent = git!(directory, ["rev-parse", "HEAD"])
    entry = Keyword.get(options, :entry, "fetch: split retrieval (#1)")

    File.write!(Path.join(directory, "mix.exs"), mix_project("2.4.0"))
    File.write!(Path.join(directory, "CHANGELOG.md"), release_changelog(entry))

    if Keyword.get(options, :extra_path, false) do
      File.write!(Path.join(directory, "unexpected.txt"), "unexpected\n")
    end

    git!(directory, ["add", "--all"])

    git!(
      directory,
      ["commit", "-m", "chore: release version v2.4.0"],
      env: [
        {"GIT_AUTHOR_DATE", "#{@release_date}T12:00:00Z"},
        {"GIT_COMMITTER_DATE", "#{@release_date}T12:00:00Z"}
      ]
    )

    release = git!(directory, ["rev-parse", "HEAD"])

    %{
      directory: directory,
      parent: parent,
      release: release,
      tree: git!(directory, ["rev-parse", "#{release}^{tree}"]),
      old_changelog: git!(directory, ["rev-parse", "#{parent}:CHANGELOG.md"]),
      new_changelog: git!(directory, ["rev-parse", "#{release}:CHANGELOG.md"])
    }
  end

  defp run_validator(fixture) do
    script = Path.expand(".github/scripts/validate-generated-release.sh", File.cwd!())

    System.cmd(script, [],
      cd: fixture.directory,
      env: [
        {"RELEASE_PARENT_SHA", fixture.parent},
        {"RELEASE_SHA", fixture.release},
        {"RELEASE_TREE_SHA", fixture.tree},
        {"RELEASE_TAG", "v2.4.0"},
        {"RELEASE_CHANGELOG_BEFORE_SHA", fixture.old_changelog},
        {"RELEASE_CHANGELOG_AFTER_SHA", fixture.new_changelog}
      ],
      stderr_to_stdout: true
    )
  end

  defp git!(directory, arguments, options \\ []) do
    command_options = Keyword.merge([cd: directory, stderr_to_stdout: true], options)

    case System.cmd("git", arguments, command_options) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git failed with #{status}: #{output}"
    end
  end

  defp mix_project(version) do
    """
    defmodule ReleaseFixture.MixProject do
      @version "#{version}"
      def project, do: [version: @version]
    end
    """
  end

  defp parent_changelog do
    """
    # Changelog

    ## [Unreleased]

    [Unreleased]: #{@repository_url}/compare/v2.3.0...HEAD

    <!-- changelog -->

    ## [v2.3.0](#{@repository_url}/compare/v2.2.0...v2.3.0) (2026-08-27)

    ### Refactoring:

    * previous release entry by Release Test
    """
  end

  defp release_changelog(entry) do
    """
    # Changelog

    ## [Unreleased]

    [Unreleased]: #{@repository_url}/compare/v2.4.0...HEAD

    <!-- changelog -->

    ## [v2.4.0](#{@repository_url}/compare/v2.3.0...v2.4.0) (#{@release_date})

    ### Refactoring:

    * #{entry} by Release Test

    ## [v2.3.0](#{@repository_url}/compare/v2.2.0...v2.3.0) (2026-08-27)

    ### Refactoring:

    * previous release entry by Release Test
    """
  end
end
