# Release Preparation

Jido Browser V3 is prepared on `release/v3`. The package version is
`3.0.0-beta.1`, but the Browser package is not published to Hex. V2 remains
on `main`.

## Dependency and runtime baseline

Use the published versions in the [migration guide](migration_3_0.md#update-the-jido-ecosystem):
Jido `3.0.0-beta.1`, Jido Action `3.0.0-beta.12`, Jido Signal
`3.0.0-beta.4`, and Zoi `0.18.8`. The normal dependency set contains no
Git or path sources. ExtractousEx remains optional for host applications.

The runtime baseline is Elixir `~> 1.18` and Erlang/OTP 27 or later. Required
CI checks the supported version matrix and the AgentBrowser `0.35.1` runtime
on Linux.

## Checks that do not publish

Run these commands from this repository:

```sh
git status --short --branch
mix deps.get
MIX_ENV=prod mix compile --warnings-as-errors
mix q
mix coveralls
mix docs -f html -f markdown
mix hex.audit
mix deps.unlock --check-unused
mix hex.build -o /tmp/jido-browser-v3.tar
HEX_API_KEY=dry-run mix hex.publish --dry-run --yes
```

Coverage must meet the threshold in `coveralls.json`. The package build must
include the migration guide and must accept all required dependencies.
The `--dry-run` flag prevents Hex publication.

Install the supported browser runtime and run the required smoke test:

```sh
mix jido_browser.install agent_browser --if-missing
JIDO_BROWSER_REQUIRE_AGENT_BROWSER=true \
  mix test test/jido_browser/adapters/agent_browser_smoke_test.exs \
  --include integration --only agent_browser_smoke --trace
```

The smoke test checks session start, navigation, snapshot, typing, clicking,
text reading, and session close with a local fixture. Other adapter integration
tests are optional, as defined in [Browser Adapter Support](browser_adapter_support.md).

Run the release task only in dry-run mode during preparation:

```sh
mix jido_browser.release --override 3.0.0-beta.1 --dry-run
```

This checks the generated release plan without a release commit or tag. The
release workflow targets `release/v3`. Do not run its publish operation or
push a release tag as part of preparation.

## Later publication

A maintainer must authorize publication separately. At that time, recheck the
dependency set, the version, the migration examples, and all required CI jobs.
Let the release task generate `CHANGELOG.md`; do not edit release notes by hand.
After publication, replace the documented Git installation with the published
Hex requirement.
