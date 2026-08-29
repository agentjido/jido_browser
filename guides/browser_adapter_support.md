# Browser Adapter Support

Policy date: 2026-08-27.

This guide is the canonical support policy for Jido Browser browser adapters.
AgentBrowser is the supported default.

## Support matrix

| Adapter or runtime | Tested upstream version | CI level | Maintenance promise | Support conditions |
| --- | --- | --- | --- | --- |
| AgentBrowser | [0.35.1](https://github.com/vercel-labs/agent-browser/releases/tag/v0.35.1) | Required unit, quality, and Linux real-runtime smoke tests on each PR | Supported default for 2.x. Version or daemon protocol failures block a release. The project maintains the current public API and fixes compatibility and security defects. | Use AgentBrowser 0.35.1 and the supervised local daemon transport. The runtime rejects other AgentBrowser versions. The required smoke lane covers start, navigate, snapshot, click, type, read, and close. |
| Lightpanda | [0.3.0](https://github.com/lightpanda-io/browser/releases/tag/0.3.0) | Required fake-runtime unit tests; opt-in real-runtime integration test | Limited support for the listed base operations and warm pools. The project fixes defects in those operations, but does not promise AgentBrowser feature parity. | Add `light_cdp ~> 0.2.1` and `lightpanda_ex ~> 0.1.0`. Use the 0.3.0 binary baseline. Support includes session lifecycle, navigation, click, type, PNG screenshots, content extraction, JavaScript evaluation, and warm pools. AgentBrowser refs, state persistence, tab management, and console capture are not supported. |
| Vibium | [26.3.11](https://github.com/VibiumDev/vibium/releases/tag/v26.3.11) | Required installer and facade tests; opt-in real-runtime integration test | Compatibility support in 2.x. The adapter is feature-frozen. The project fixes critical compatibility and security defects in its current operations. | Use Vibium 26.3.11. Support is for unpooled sessions and the current navigation, click, type, PNG screenshot, content extraction, and JavaScript evaluation operations. Markdown extraction uses Vibium plain text. Newer Vibium releases are not part of this support promise. |

"Required" means that the check runs in the normal pull-request CI. "Opt-in"
means that the test has the `:integration` tag and the normal test command
excludes it. An opt-in test does not make an upstream runtime part of the
required CI promise.

## Evidence

The AgentBrowser decision comes from
[issue #74](https://github.com/agentjido/jido_browser/issues/74) and the
[version and transport research](agent_browser_compatibility.md). That research
tested the published 0.35.1 runtime with local fixtures. The required
[AgentBrowser smoke workflow](https://github.com/agentjido/jido_browser/blob/main/.github/workflows/ci.yml)
was added by [issue #65](https://github.com/agentjido/jido_browser/issues/65)
and [PR #107](https://github.com/agentjido/jido_browser/pull/107).

The other CI levels come from the current test configuration and adapter tests:

- [`test/test_helper.exs`](https://github.com/agentjido/jido_browser/blob/main/test/test_helper.exs)
  excludes all integration tests from the normal test command.
- The Lightpanda
  [unit](https://github.com/agentjido/jido_browser/blob/main/test/jido_browser/adapters/lightpanda_test.exs)
  and
  [integration](https://github.com/agentjido/jido_browser/blob/main/test/jido_browser/adapters/lightpanda_integration_test.exs)
  tests define its verified operations. The adapter module defines its optional
  dependency and feature conditions.
- The Vibium installer pins 26.3.11. Its local-fixture integration test covers
  the operations in the matrix.

## Migration

Jido Browser 3.0 removes the Web adapter and its installer target.

| Removed use | Replacement |
| --- | --- |
| Stateful browser sessions, rendered pages, JavaScript, or warm pools | Select `Jido.Browser.Adapters.AgentBrowser` and install the supported AgentBrowser runtime. |
| Stateless HTTP retrieval | Use `Jido.Browser.web_fetch/2` with `:req` or `Jido.Browser.WebFetch.Backends.Req`. |
| `:browsey`, `Jido.Browser.WebFetch.Backends.Browsey`, or `browsey:` configuration | Use Req for stateless HTTP retrieval. Use AgentBrowser when the page needs JavaScript or browser rendering. |
