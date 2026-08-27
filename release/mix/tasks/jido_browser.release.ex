defmodule Mix.Tasks.JidoBrowser.Release do
  use Mix.Task

  @shortdoc "Prepare a GitOps release with repository version-link policy"

  @moduledoc """
  Prepares a release through GitOps after applying the repository version-link policy.

      mix jido_browser.release --override 2.3.0 --dry-run

  All GitOps release options are accepted. A bare version override is normalized to the
  repository's v-prefixed tag format before GitOps creates the changelog heading and tag.
  """

  alias Jido.Browser.Release

  @impl Mix.Task
  def run(args) do
    prefix = Application.get_env(:git_ops, :version_tag_prefix, "v")
    repository_path = Application.get_env(:git_ops, :repository_path, File.cwd!())
    changelog_path = Application.get_env(:git_ops, :changelog_file, "CHANGELOG.md")
    changelog_path = Path.expand(changelog_path, repository_path)
    normalized_args = Release.normalize_args(args, prefix)
    current_version = Release.current_version!(repository_path, prefix)

    Release.ensure_override_is_new!(normalized_args, repository_path, prefix)
    Release.ensure_unreleased_link!(changelog_path, current_version)
    Mix.Task.run("git_ops.release", normalized_args)
  end
end
