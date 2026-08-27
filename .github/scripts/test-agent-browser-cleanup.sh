#!/usr/bin/env bash

set -euo pipefail

if [[ ! -r /proc/self/stat ]]; then
  echo "Forced cleanup harness requires Linux /proc; skipping on this host."
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cleanup_script="$script_dir/cleanup-agent-browser.sh"
official_binary="${AGENT_BROWSER_BINARY:-}"
real_chromium_binary="${AGENT_BROWSER_CHROMIUM_BINARY:-}"
chromium_executables="${AGENT_BROWSER_CHROMIUM_EXECUTABLES:-}"
harness_runner_temp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/jido-cleanup.XXXXXX")"
job_root="$(mktemp -d "$harness_runner_temp/jido-ab.XXXXXX")"
socket_dir="$job_root/socket"
profile_dir="$job_root/tmp/agent-browser-chrome-harness"
orphan_pid_path="$harness_runner_temp/orphan.pid"
orphan_launcher_pid_path="$harness_runner_temp/orphan-launcher.pid"
tail_path="$(readlink -f "$(command -v tail)")"
fake_chrome_dir="$harness_runner_temp/jido-fake-bin"
fake_chrome_path="$fake_chrome_dir/chrome"
control_pid=""
prefix_control_pid=""
fake_chrome_pid=""
crashed_daemon_pid=""
live_daemon_pid=""
identity_probe_pid=""
orphan_chrome_pid=""

read_process_start_time() {
  local process_pid="$1"
  local stat_line
  local stat_rest
  local stat_fields

  IFS= read -r stat_line < "/proc/$process_pid/stat"
  stat_rest="${stat_line##*) }"
  read -r -a stat_fields <<< "$stat_rest"
  printf '%s\n' "${stat_fields[19]}"
}

process_is_running() {
  local process_pid="$1"
  local process_state

  kill -0 "$process_pid" 2>/dev/null || return 1
  process_state="$(ps -o stat= -p "$process_pid" 2>/dev/null || true)"
  [[ -n "$process_state" && "$process_state" != Z* ]]
}

process_uses_trusted_chromium_identity() {
  local process_pid="$1"
  local process_executable_id
  local executable_path
  local configured_executable_id

  process_executable_id="$(stat -Lc '%d:%i' -- "/proc/$process_pid/exe" 2>/dev/null)" || return 1
  IFS=: read -r -a configured_executables <<< "$chromium_executables"

  for executable_path in "${configured_executables[@]}"; do
    configured_executable_id="$(stat -Lc '%d:%i' -- "$executable_path" 2>/dev/null || true)"

    if [[ -n "$configured_executable_id" &&
          "$process_executable_id" == "$configured_executable_id" ]]; then
      return 0
    fi
  done

  return 1
}

finish() {
  local exit_status="$?"
  local process_pid

  trap - EXIT

  if [[ -f "$job_root/.jido-browser-agent-browser-root" ]]; then
    RUNNER_TEMP="$harness_runner_temp" \
    AGENT_BROWSER_JOB_ROOT="$job_root" \
    AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
    AGENT_BROWSER_BINARY="$official_binary" \
    AGENT_BROWSER_CHROMIUM_EXECUTABLES="$chromium_executables" \
    AGENT_BROWSER_CLEANUP_TEST_EXECUTABLES="$tail_path" \
      bash "$cleanup_script" >/dev/null 2>&1 || true
  fi

  for process_pid in \
    "$control_pid" \
    "$prefix_control_pid" \
    "$fake_chrome_pid" \
    "$crashed_daemon_pid" \
    "$live_daemon_pid" \
    "$identity_probe_pid" \
    "$orphan_chrome_pid"; do
    if [[ -n "$process_pid" ]]; then
      kill -KILL "$process_pid" 2>/dev/null || true
      wait "$process_pid" 2>/dev/null || true
    fi
  done

  rm -rf -- "$harness_runner_temp"
  exit "$exit_status"
}

trap finish EXIT

if [[ ! -x "$official_binary" ]]; then
  echo "The official AgentBrowser binary is required by the cleanup harness." >&2
  exit 1
fi

detected_version="$("$official_binary" --version)"

if [[ "$detected_version" != "agent-browser 0.35.1" ]]; then
  echo "Expected official AgentBrowser 0.35.1, got: $detected_version" >&2
  exit 1
fi

if [[ ! -x "$real_chromium_binary" || -z "$chromium_executables" ]]; then
  echo "A trusted real Chromium binary and executable identity list are required." >&2
  exit 1
fi

real_chromium_version="$($real_chromium_binary --version)"

case "$real_chromium_version" in
  *Chrome*|*Chromium*) ;;
  *)
    echo "Expected a real Chromium executable, got: $real_chromium_version" >&2
    exit 1
    ;;
esac

mkdir -p "$socket_dir" "$profile_dir/Default" "$fake_chrome_dir"
printf '%s\n' "$job_root" > "$job_root/.jido-browser-agent-browser-root"

for suffix in version sock stream engine provider extensions; do
  printf 'remaining session artifact\n' > "$socket_dir/forced-cleanup.$suffix"
done

printf 'remaining Chrome profile\n' > "$profile_dir/Default/Preferences"
printf 'unrelated input\n' > "$job_root/unrelated-input"

cp -- "$tail_path" "$fake_chrome_path"
chmod 700 "$fake_chrome_path"

env -u AGENT_BROWSER_JOB_ROOT -u AGENT_BROWSER_SOCKET_DIR sleep 300 &
control_pid="$!"
printf '%s\n' "$control_pid" > "$socket_dir/stale.pid"

# shellcheck disable=SC2016
env -u AGENT_BROWSER_JOB_ROOT -u AGENT_BROWSER_SOCKET_DIR \
  bash -c 'exec -a "$1/chrome --user-data-dir=$1/profile" sleep 300' _ "${job_root}-other" &
prefix_control_pid="$!"

env -u AGENT_BROWSER_JOB_ROOT -u AGENT_BROWSER_SOCKET_DIR \
  "$fake_chrome_path" -f "$job_root/unrelated-input" >/dev/null &
fake_chrome_pid="$!"

env \
  AGENT_BROWSER_JOB_ROOT="$job_root" \
  AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
  bash -c 'exec -a agent-browser-crashed tail -f /dev/null' &
crashed_daemon_pid="$!"
printf '%s\n' "$crashed_daemon_pid" > "$socket_dir/crashed.pid"
kill -KILL "$crashed_daemon_pid"
wait "$crashed_daemon_pid" 2>/dev/null || true

env \
  AGENT_BROWSER_JOB_ROOT="$job_root" \
  AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
  AGENT_BROWSER_SESSION="cleanup-harness" \
  AGENT_BROWSER_DAEMON=1 \
  "$official_binary" >"$job_root/official-daemon.log" 2>&1 &
live_daemon_pid="$!"

for _attempt in {1..100}; do
  if [[ -S "$socket_dir/cleanup-harness.sock" ]]; then
    break
  fi

  kill -0 "$live_daemon_pid" 2>/dev/null || break
  sleep 0.02
done

if [[ ! -S "$socket_dir/cleanup-harness.sock" ]]; then
  echo "Official AgentBrowser daemon did not become ready." >&2
  sed -n '1,120p' "$job_root/official-daemon.log" >&2
  exit 1
fi

env \
  AGENT_BROWSER_JOB_ROOT="$job_root" \
  AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
  bash -c 'exec -a identity-record-probe tail -f /dev/null' &
identity_probe_pid="$!"
identity_probe_start_time="$(read_process_start_time "$identity_probe_pid")"
wrong_identity_probe_start_time="$((identity_probe_start_time + 1))"

RUNNER_TEMP="$harness_runner_temp" \
AGENT_BROWSER_JOB_ROOT="$job_root" \
AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
AGENT_BROWSER_BINARY="$official_binary" \
AGENT_BROWSER_CHROMIUM_EXECUTABLES="$chromium_executables" \
AGENT_BROWSER_CLEANUP_TEST_EXECUTABLES="$tail_path" \
  bash -c '
    source "$1"

    if signal_owned_record "$2:$3" TERM; then
      echo "A stale PID:start_time record was accepted." >&2
      exit 1
    fi

    kill -0 "$2"
    signal_owned_record "$2:$4" TERM
  ' _ "$cleanup_script" "$identity_probe_pid" \
    "$wrong_identity_probe_start_time" "$identity_probe_start_time"

wait "$identity_probe_pid" 2>/dev/null || true

if kill -0 "$identity_probe_pid" 2>/dev/null; then
  echo "The correct PID:start_time record was not handled." >&2
  exit 1
fi

identity_probe_pid=""

# shellcheck disable=SC2016
env \
  AGENT_BROWSER_JOB_ROOT="$job_root" \
  AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
  CHROMIUM_BINARY="$real_chromium_binary" \
  PROFILE_DIR="$profile_dir" \
  ORPHAN_PID_PATH="$orphan_pid_path" \
  ORPHAN_LAUNCHER_PID_PATH="$orphan_launcher_pid_path" \
  bash -c '
    printf "%s\n" "$$" > "$ORPHAN_LAUNCHER_PID_PATH"
    "$CHROMIUM_BINARY" \
      --headless=new \
      --no-sandbox \
      --disable-background-networking \
      --disable-dev-shm-usage \
      --disable-gpu \
      --no-first-run \
      --remote-debugging-port=0 \
      "--user-data-dir=$PROFILE_DIR" \
      about:blank >"$PROFILE_DIR/chromium.log" 2>&1 &
    printf "%s\n" "$!" > "$ORPHAN_PID_PATH"
  '

for _attempt in {1..50}; do
  if [[ -s "$orphan_pid_path" ]]; then
    break
  fi

  sleep 0.02
done

IFS= read -r orphan_chrome_pid < "$orphan_pid_path"
IFS= read -r orphan_launcher_pid < "$orphan_launcher_pid_path"

for _attempt in {1..100}; do
  if kill -0 "$orphan_chrome_pid" 2>/dev/null &&
      process_uses_trusted_chromium_identity "$orphan_chrome_pid"; then
    break
  fi

  sleep 0.02
done

if ! process_uses_trusted_chromium_identity "$orphan_chrome_pid"; then
  echo "Real Chromium did not start with a configured trusted identity." >&2
  sed -n '1,120p' "$profile_dir/chromium.log" >&2
  exit 1
fi

kill -STOP "$orphan_chrome_pid"
orphan_chrome_start_time="$(read_process_start_time "$orphan_chrome_pid")"
orphan_chrome_record="$orphan_chrome_pid:$orphan_chrome_start_time"

for _attempt in {1..50}; do
  orphan_state="$(ps -o stat= -p "$orphan_chrome_pid" 2>/dev/null || true)"

  if [[ "$orphan_state" == T* ]]; then
    break
  fi

  sleep 0.02
done

kill -0 "$live_daemon_pid"
kill -0 "$orphan_chrome_pid"
kill -0 "$control_pid"
kill -0 "$prefix_control_pid"
kill -0 "$fake_chrome_pid"

orphan_parent_pid="$(ps -o ppid= -p "$orphan_chrome_pid")"
orphan_parent_pid="${orphan_parent_pid//[[:space:]]/}"

if [[ "$orphan_parent_pid" == "$orphan_launcher_pid" || "$orphan_state" != T* ]]; then
  echo "Chrome harness process was not stopped and reparented." >&2
  exit 1
fi

cleanup_shell_parent_pid="$$"
cleanup_started_ns="$(date +%s%N)"
cleanup_status=0

cleanup_output="$(
  RUNNER_TEMP="$harness_runner_temp" \
  AGENT_BROWSER_JOB_ROOT="$job_root" \
  AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
  AGENT_BROWSER_BINARY="$official_binary" \
  AGENT_BROWSER_CHROMIUM_EXECUTABLES="$chromium_executables" \
  AGENT_BROWSER_CLEANUP_TEST_EXECUTABLES="$tail_path" \
    bash "$cleanup_script"
)" || cleanup_status=$?

cleanup_finished_ns="$(date +%s%N)"
cleanup_elapsed_ms="$(((cleanup_finished_ns - cleanup_started_ns) / 1000000))"
printf '%s\n' "$cleanup_output"

if [[ "$cleanup_status" -ne 0 ]]; then
  echo "Forced cleanup returned status $cleanup_status." >&2
  exit 1
fi

if [[ "$cleanup_output" != *"Sent KILL to verified job-owned processes"* ]]; then
  echo "TERM-resistant owned process did not reach verified KILL." >&2
  exit 1
fi

if [[ "$cleanup_output" != *"Sent KILL to verified job-owned processes:"*"$orphan_chrome_record"* ]]; then
  echo "The real stopped Chromium record did not reach verified KILL." >&2
  exit 1
fi

wait "$live_daemon_pid" 2>/dev/null || true

if kill -0 "$live_daemon_pid" 2>/dev/null; then
  echo "Live job-owned daemon remains after cleanup." >&2
  exit 1
fi

if process_is_running "$orphan_chrome_pid"; then
  echo "Reparented job-owned Chrome remains after cleanup." >&2
  exit 1
fi

if ! kill -0 "$cleanup_shell_parent_pid" 2>/dev/null; then
  echo "Cleanup terminated its calling shell." >&2
  exit 1
fi

if ! kill -0 "$control_pid" 2>/dev/null; then
  echo "Official AgentBrowser stale PID handling terminated an unrelated process." >&2
  exit 1
fi

if ! kill -0 "$prefix_control_pid" 2>/dev/null; then
  echo "Root-prefix matching terminated an unrelated process." >&2
  exit 1
fi

if ! kill -0 "$fake_chrome_pid" 2>/dev/null; then
  echo "A filename-only fake Chrome process was terminated." >&2
  exit 1
fi

if [[ -e "$job_root" || -L "$job_root" ]]; then
  echo "Runtime artifacts remain after cleanup." >&2
  exit 1
fi

if [[ "$cleanup_elapsed_ms" -gt 12000 ]]; then
  echo "Forced KILL cleanup exceeded its measured bound: ${cleanup_elapsed_ms}ms" >&2
  exit 1
fi

echo "Forced cleanup harness passed in ${cleanup_elapsed_ms}ms."
echo "Official 0.35.1 stale PID, root-prefix, fake Chrome, cleanup shell, and control processes survived."
echo "Wrong PID:start_time was rejected; the correct record was handled."
echo "Trusted real reparented Chromium reached KILL; sidecars, profile, and runtime root were removed."
