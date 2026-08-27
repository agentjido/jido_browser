# AgentBrowser Version and Transport Compatibility

Research date: 2026-08-27.

## Decision

Use AgentBrowser 0.35.1 as the preferred supported version for Jido Browser 2.x.

Keep the current local daemon transport for Jido Browser 2.x. AgentBrowser
0.35.1 still accepts newline-delimited JSON on a Unix socket or local Windows
TCP port. The response envelope also stays compatible. One command payload is
not compatible: tab selection changed from a zero-based `index` to a `tabId`
such as `t1`.

Do not replace the daemon transport with MCP in the 2.x maintenance line.
AgentBrowser MCP is a valid upstream interface, but it adds an MCP and CLI layer
and still uses the AgentBrowser daemon. Its `core` profile does not contain all
operations that the Jido Browser adapter supports. The adapter would need the
152-tool `all` profile.

The required implementation work is in
[#96](https://github.com/agentjido/jido_browser/issues/96). That
issue must finish before
[#66](https://github.com/agentjido/jido_browser/issues/66). Binary selection,
installer failure handling, and CI changes stay in their existing issues.

## Primary sources

- AgentBrowser [0.20.2 release](https://github.com/vercel-labs/agent-browser/releases/tag/v0.20.2)
  and [0.35.1 release](https://github.com/vercel-labs/agent-browser/releases/tag/v0.35.1).
- The 0.20.2 daemon creates the session socket and enables idle cleanup only
  when the environment variable has a positive value:
  [daemon startup](https://github.com/vercel-labs/agent-browser/blob/v0.20.2/cli/src/native/daemon.rs#L18-L68).
- The 0.20.2 daemon reads one JSON command per line and writes one JSON response
  per line:
  [socket handler](https://github.com/vercel-labs/agent-browser/blob/v0.20.2/cli/src/native/daemon.rs#L226-L281).
- The 0.35.1 daemon keeps the same socket and JSON line model:
  [socket setup](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/native/daemon.rs#L220-L270)
  and [socket handler](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/native/daemon.rs#L506-L568).
- AgentBrowser 0.20.2 selects tabs with `index`:
  [0.20.2 command parser](https://github.com/vercel-labs/agent-browser/blob/v0.20.2/cli/src/commands.rs#L931-L943)
  and [0.20.2 action handler](https://github.com/vercel-labs/agent-browser/blob/v0.20.2/cli/src/native/actions.rs#L2450-L2467).
- AgentBrowser 0.35.1 selects tabs with `tabId`:
  [0.35.1 command parser](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/commands.rs#L1533-L1547)
  and [0.35.1 action handler](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/native/actions.rs#L6438-L6455).
- The 0.35.1 MCP server uses newline-delimited JSON-RPC. It delegates tool calls
  to the current binary in JSON mode and uses the same daemon:
  [MCP implementation](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/mcp.rs#L1-L21).
- The 0.35.1 MCP profile definitions are in the
  [MCP source](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/mcp.rs#L208-L320).
  The exact profile tool lists are also in the
  [MCP source](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/mcp.rs#L328-L488).
- MCP maps `allowedDomains` and `idleTimeout` to the matching CLI options:
  [tool schema](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/mcp.rs#L1895-L1923)
  and [argument mapping](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/cli/src/mcp.rs#L3539-L3597).
- The upstream 0.35.1 documentation defines
  [session isolation](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/README.md#L631-L665),
  [domain containment](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/README.md#L779-L789),
  and the [one-hour default idle cleanup](https://github.com/vercel-labs/agent-browser/blob/v0.35.1/README.md#L1575-L1584).

## Test environment

The tests ran on macOS ARM64. They used the published Darwin ARM64 binaries and
local fixture pages only. The 0.35.1 release was the latest upstream release on
the research date.

| Version | Published | SHA-256 | `--version` result |
| --- | --- | --- | --- |
| 0.20.2 | 2026-03-14 | `6b8617f4222b06ef160aafe5740e89af53b7704286a0a1ba4a81d81d23e64f45` | `agent-browser 0.20.2` |
| 0.35.1 | 2026-08-26 | `12be3313ec6d878d8fda62ca5c62b7013c1b6931bf57dd2678788654b01ffe95` | `agent-browser 0.35.1` |

Use these commands from the Jido Browser repository root:

```sh
research_dir="$(mktemp -d)"
mkdir -p "$research_dir/0.20.2" "$research_dir/0.35.1"

gh release download v0.20.2 \
  --repo vercel-labs/agent-browser \
  --pattern agent-browser-darwin-arm64 \
  --output "$research_dir/0.20.2/agent-browser"

gh release download v0.35.1 \
  --repo vercel-labs/agent-browser \
  --pattern agent-browser-darwin-arm64 \
  --output "$research_dir/0.35.1/agent-browser"

chmod 755 "$research_dir/0.20.2/agent-browser" \
  "$research_dir/0.35.1/agent-browser"
shasum -a 256 "$research_dir/0.20.2/agent-browser" \
  "$research_dir/0.35.1/agent-browser"
"$research_dir/0.20.2/agent-browser" --version
"$research_dir/0.35.1/agent-browser" --version
```

For another platform, use the release asset for that platform and verify its
digest on the release page.

## Current adapter test

The existing integration test starts
`Jido.Browser.TestSupport.IntegrationTestServer` on `127.0.0.1`. It covers
snapshot references, waits, state save and load, tabs, console and page errors,
queries, attributes, and content extraction.

Run the pinned version:

```sh
PATH="$research_dir/0.20.2:$PATH" \
  mix test test/jido_browser/adapters/agent_browser_integration_test.exs \
  --include integration
```

Result: `10 passed`.

The current version check rejects 0.35.1 before a browser test can run:

```sh
PATH="$research_dir/0.35.1:$PATH" \
  mix test test/jido_browser/adapters/agent_browser_integration_test.exs \
  --include integration
```

Result: `0 tests, 10 skipped`.

The following test-only wrapper changes only the reported version. All other
commands run the real 0.35.1 binary. This makes it possible to test the current
daemon client without a production code change.

```sh
mkdir -p "$research_dir/0.35.1-current-gate"
cat >"$research_dir/0.35.1-current-gate/agent-browser" <<'SH'
#!/bin/sh
if [ "$1" = "--version" ]; then
  printf 'agent-browser 0.20.2\n'
  exit 0
fi
exec "$(dirname "$0")/../0.35.1/agent-browser" "$@"
SH
chmod 755 "$research_dir/0.35.1-current-gate/agent-browser"

PATH="$research_dir/0.35.1-current-gate:$PATH" \
  mix test test/jido_browser/adapters/agent_browser_integration_test.exs \
  --include integration
```

Result: `9/10 passed`. The tab test failed with this exact daemon error:

```text
Missing 'tabId' parameter (expected `t<N>` or a label)
payload: %{"action" => "tab_switch", "index" => 0}
```

The 0.35.1 CLI confirmed the new payload model. `tab list` returned `t1` and
`t2`, and `tab t1` selected the first tab.

## Local security and lifecycle probes

The raw CLI probes used this local page:

```sh
mkdir -p "$research_dir/fixture"
printf '%s\n' \
  '<!doctype html><title>AgentBrowser compatibility fixture</title>' \
  '<h1>AgentBrowser compatibility fixture</h1>' \
  '<p id="status">local fixture ready</p>' \
  >"$research_dir/fixture/index.html"
printf '{}\n' >"$research_dir/empty-config.json"
python3 -m http.server 43174 --bind 127.0.0.1 \
  --directory "$research_dir/fixture"
```

The probes set `AGENT_BROWSER_CONFIG` to the empty file. Thus, user and project
configuration did not change the results.

### `allowedDomains`

For 0.20.2, run:

```sh
AGENT_BROWSER_SOCKET_DIR="$PWD/.d1" \
AGENT_BROWSER_CONFIG="$research_dir/empty-config.json" \
  "$research_dir/0.20.2/agent-browser" --session d1 \
  --allowed-domains 127.0.0.1 --json open http://127.0.0.1:43174/

AGENT_BROWSER_SOCKET_DIR="$PWD/.d1" \
AGENT_BROWSER_CONFIG="$research_dir/empty-config.json" \
  "$research_dir/0.20.2/agent-browser" --session d1 \
  --json open http://localhost:43174/
```

Run the same commands for 0.35.1 with a different short socket directory and
session name. Both versions returned success for `127.0.0.1`. Both versions
rejected `localhost` with this result and exit status 1:

```json
{"success":false,"data":null,"error":"Domain 'localhost' is not in the allowed domains list"}
```

### Session isolation

For each version, two sessions opened the same local origin. Session A set a
local storage value. Session B then read that key:

```sh
agent_browser="$research_dir/0.20.2/agent-browser"
export AGENT_BROWSER_SOCKET_DIR="$PWD/.i1"
export AGENT_BROWSER_CONFIG="$research_dir/empty-config.json"

"$agent_browser" --session a1 --json open http://127.0.0.1:43174/
"$agent_browser" --session a1 --json eval \
  'localStorage.setItem("owner", "session-a"); localStorage.getItem("owner")'
"$agent_browser" --session b1 --json open http://127.0.0.1:43174/
"$agent_browser" --session b1 --json eval 'localStorage.getItem("owner")'
```

Run the same commands with 0.35.1 and new session names. Both versions returned
`"session-a"` in session A and `null` in session B. This local probe confirmed
local storage isolation only. The broader session isolation guarantees come
from the upstream documentation. This probe did not test cookies, browser
history, or tabs.

### Idle cleanup

For each version, the probe set a one-second idle timeout. It opened the local
page, read the daemon PID, and checked the PID and socket after two seconds:

```sh
export AGENT_BROWSER_IDLE_TIMEOUT_MS=1000
"$agent_browser" --session t1 --json open http://127.0.0.1:43174/
daemon_pid="$(cat "$AGENT_BROWSER_SOCKET_DIR/t1.pid")"
kill -0 "$daemon_pid"
test -S "$AGENT_BROWSER_SOCKET_DIR/t1.sock"
sleep 2
kill -0 "$daemon_pid"
test -S "$AGENT_BROWSER_SOCKET_DIR/t1.sock"
```

The first PID and socket checks passed for both versions. After two seconds,
the PID did not exist and the socket was absent for both versions.

Version 0.20.2 disables idle cleanup when
`AGENT_BROWSER_IDLE_TIMEOUT_MS` is absent or zero. Version 0.35.1 changes the
absent value to a one-hour default. A value of zero still disables cleanup.
Jido Browser does not set this variable, so 0.35.1 adds a leak backstop for a
Jido process that stops before it sends `close`.

## MCP stdio probe

AgentBrowser 0.20.2 returned `Unknown command: mcp` with exit status 1.

AgentBrowser 0.35.1 started MCP with this command:

```sh
"$research_dir/0.35.1/agent-browser" mcp --tools core
```

The client sent `initialize` with MCP protocol `2025-11-25`, sent
`notifications/initialized`, and read every `tools/list` page. The server
accepted the protocol. The client repeated this sequence for each profile:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"jido-browser-compat","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
```

When a `tools/list` result contained `nextCursor`, the next request used
`{"cursor":"<nextCursor>"}`. The profile results were:

| Profile | Tool count | First tool | Last tool |
| --- | ---: | --- | --- |
| `core` | 29 | `agent_browser_tools_profiles` | `agent_browser_tab_close` |
| `network` | 9 | `agent_browser_set_offline` | `agent_browser_network_har_stop` |
| `state` | 27 | `agent_browser_storage_get` | `agent_browser_skills_path` |
| `debug` | 40 | `agent_browser_upload` | `agent_browser_chat` |
| `tabs` | 13 | `agent_browser_back` | `agent_browser_dialog_dismiss` |
| `react` | 8 | `agent_browser_react_tree` | `agent_browser_remove_init_script` |
| `mobile` | 15 | `agent_browser_keydown` | `agent_browser_device` |
| `all` | 152 | `agent_browser_tools_profiles` | `agent_browser_chat` |

The `core` profile includes navigation, common interaction, waits, screenshots,
basic reads, JavaScript evaluation, and basic tab operations. It does not
include state save and load, console and page errors, attributes, counts, HTML,
focus, hover, or visibility checks. The `all` profile contains these tools and
is the only single profile that covers the current adapter.

The MCP client also sent these local fixture calls to the `core` profile:

```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"agent_browser_open","arguments":{"session":"ma","url":"http://127.0.0.1:43174/","allowedDomains":["127.0.0.1"]}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"agent_browser_open","arguments":{"session":"mb","url":"http://localhost:43174/","allowedDomains":["127.0.0.1"]}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"agent_browser_eval","arguments":{"session":"ma","script":"localStorage.setItem('owner','session-a'); localStorage.getItem('owner')"}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"agent_browser_open","arguments":{"session":"mc","url":"http://127.0.0.1:43174/","allowedDomains":["127.0.0.1"]}}}
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"agent_browser_eval","arguments":{"session":"mc","script":"localStorage.getItem('owner')"}}}
```

The first open call succeeded. The second open call returned an MCP tool error
with `Domain 'localhost' is not in the allowed domains list`. Session `ma`
returned `"session-a"`, and session `mc` returned `null`.

## Command and result matrix

| Check | AgentBrowser 0.20.2 | AgentBrowser 0.35.1 | Decision evidence |
| --- | --- | --- | --- |
| Published binary | Digest matched | Digest matched | The tested files are release assets. |
| Jido version check | Accepted | Rejected | The selected version needs a follow-up change. |
| Current daemon integration | 10/10 passed | 9/10 passed with the test-only version wrapper | The daemon transport remains supportable. |
| JSON line request and response | Passed | Passed | The transport envelope did not change. |
| Tab selection | Zero-based `index` | `tabId` such as `t1` | The follow-up must keep the public zero-based Jido API and map it to `tabId`. |
| MCP stdio | Not present | Protocol `2025-11-25` accepted | MCP requires the selected version. |
| MCP profiles | Not present | All eight profiles loaded | `all` is required for current adapter parity. |
| `allowedDomains` | Allowed the listed host and blocked the other host | Same result through CLI and MCP | Both transports keep the domain rule. |
| Session isolation | Session B read `null` | Session B read `null` through CLI and MCP | Local storage stayed isolated. |
| Explicit one-second idle cleanup | PID and socket removed | PID and socket removed | Both versions support configured cleanup. |
| Default idle cleanup | Disabled | One hour | 0.35.1 prevents an unlimited headless daemon leak by default. |

## Follow-up boundary

The linked follow-up must:

- update the existing supported and download version values to 0.35.1;
- change tab switch and tab close daemon payloads to the 0.35.1 `tabId` model;
- keep the public Jido Browser zero-based tab index API;
- keep the current supervised daemon transport; and
- make the local AgentBrowser integration test pass all 10 tests with the real
  0.35.1 binary.

It must not implement deterministic binary selection, broad installer changes,
or CI changes. Those changes belong to #66, #64, and #65.
