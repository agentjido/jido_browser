#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import os
import re
import subprocess
import sys


REPOSITORY_URL = "https://github.com/agentjido/jido_browser"
VISIBLE_TYPES = {
    "feat": "Features",
    "fix": "Bug Fixes",
    "perf": "Performance",
    "refactor": "Refactoring",
    "security": "Security",
    "deprecate": "Deprecated",
}
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
TAG_RE = re.compile(
    r"^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?"
    r"(?:\+[0-9A-Za-z][0-9A-Za-z.-]*)?$"
)
SUBJECT_RE = re.compile(
    r"^(feat|fix|perf|refactor|security|deprecate)"
    r"(?:\(([^)\r\n]+)\))?!?: (.+)$"
)


def fail(message):
    print(f"Generated release validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def required_environment(name, pattern=None):
    value = os.environ.get(name, "")
    if not value or (pattern is not None and not pattern.fullmatch(value)):
        fail(f"{name} is missing or invalid")
    return value


def git(*arguments, binary=False, strip=True):
    result = subprocess.run(
        ["git", *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=not binary,
    )
    if result.returncode != 0:
        error = result.stderr if not binary else result.stderr.decode("utf-8", "replace")
        fail(error.strip() or f"git {' '.join(arguments)} failed")
    return result.stdout if binary or not strip else result.stdout.strip()


parent = required_environment("RELEASE_PARENT_SHA", SHA_RE)
release = required_environment("RELEASE_SHA", SHA_RE)
tree = required_environment("RELEASE_TREE_SHA", SHA_RE)
tag = required_environment("RELEASE_TAG", TAG_RE)
old_changelog_sha = required_environment("RELEASE_CHANGELOG_BEFORE_SHA", SHA_RE)
new_changelog_sha = required_environment("RELEASE_CHANGELOG_AFTER_SHA", SHA_RE)

if git("rev-parse", "HEAD") != release:
    fail("HEAD is not the recorded release commit")
if git("rev-list", "--parents", "-n", "1", release).split() != [release, parent]:
    fail("the release is not one commit from the recorded parent")
if git("rev-parse", f"{release}^{{tree}}") != tree:
    fail("the release tree does not match the recorded tree")
if git("rev-parse", f"{parent}:CHANGELOG.md") != old_changelog_sha:
    fail("the parent changelog does not match the recorded blob")
if git("rev-parse", f"{release}:CHANGELOG.md") != new_changelog_sha:
    fail("the release changelog does not match the recorded blob")
if git("show", "-s", "--format=%s", release) != f"chore: release version {tag}":
    fail("the release commit subject is not the expected GitOps subject")

changed = git("diff", "--name-only", "-z", parent, release, binary=True)
changed_paths = sorted(path.decode("utf-8") for path in changed.split(b"\0") if path)
if changed_paths != ["CHANGELOG.md", "mix.exs"]:
    fail(f"the release changed unexpected paths: {changed_paths}")

previous_tag = git("describe", "--tags", "--abbrev=0", parent)
if not TAG_RE.fullmatch(previous_tag):
    fail("the parent has no valid previous release tag")
previous_version = previous_tag.removeprefix("v")
version = tag.removeprefix("v")

old_mix = git("show", f"{parent}:mix.exs", strip=False)
new_mix = git("show", f"{release}:mix.exs", strip=False)
old_version_literal = f'@version "{previous_version}"'
if old_mix.count(old_version_literal) != 1:
    fail("the parent mix.exs does not have one previous version literal")
expected_mix = old_mix.replace(old_version_literal, f'@version "{version}"')
if new_mix != expected_mix:
    fail("mix.exs changed by more than the exact version replacement")

old_changelog = git("show", f"{parent}:CHANGELOG.md", strip=False)
new_changelog = git("show", f"{release}:CHANGELOG.md", strip=False)
old_unreleased = f"[Unreleased]: {REPOSITORY_URL}/compare/{previous_tag}...HEAD"
new_unreleased = f"[Unreleased]: {REPOSITORY_URL}/compare/{tag}...HEAD"
if old_changelog.splitlines().count(old_unreleased) != 1:
    fail("the parent changelog does not have one expected Unreleased link")
if new_changelog.splitlines().count(new_unreleased) != 1:
    fail("the release changelog does not have one expected Unreleased link")

release_date = git("show", "-s", "--format=%cs", release)
release_heading = (
    f"## [{tag}]({REPOSITORY_URL}/compare/{previous_tag}...{tag}) ({release_date})"
)
if new_changelog.splitlines().count(release_heading) != 1:
    fail("the release changelog does not have one exact version heading")

history_heading = f"## [{previous_tag}]"
old_history_index = old_changelog.find(history_heading)
new_history_index = new_changelog.find(history_heading)
release_index = new_changelog.find(release_heading)
marker_index = new_changelog.find("<!-- changelog -->")
if min(old_history_index, new_history_index, release_index, marker_index) < 0:
    fail("the changelog section markers are incomplete")
if not marker_index < release_index < new_history_index:
    fail("the generated release section is in the wrong location")
if old_changelog[old_history_index:] != new_changelog[new_history_index:]:
    fail("the generated release changed historical changelog content")

release_section = new_changelog[release_index:new_history_index]
subjects = git("log", "--format=%s", f"{previous_tag}..{parent}").splitlines()
expected_entries = []
expected_headers = set()
for subject in subjects:
    match = SUBJECT_RE.fullmatch(subject)
    if not match:
        continue
    change_type, scope, description = match.groups()
    expected_headers.add(VISIBLE_TYPES[change_type])
    expected_entries.append(f"{scope}: {description}" if scope else description)

if not expected_entries:
    fail("the release range has no visible conventional changes")

actual_entries = [
    line.removeprefix("* ")
    for line in release_section.splitlines()
    if line.startswith("* ")
]
if len(actual_entries) != len(expected_entries):
    fail("the release entry count does not match visible conventional commits")
for expected in expected_entries:
    matches = [entry for entry in actual_entries if entry.startswith(f"{expected} by ")]
    if len(matches) != 1:
        fail(f"the release section does not contain one generated entry for: {expected}")

actual_headers = {
    match.group(1)
    for line in release_section.splitlines()
    if (match := re.fullmatch(r"### ([^:]+):", line))
}
if actual_headers != expected_headers:
    fail("the release section headings do not match the visible change types")

print(f"Validated exact generated release output for {tag} from {previous_tag}.")
PY
