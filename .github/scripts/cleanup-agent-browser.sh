#!/usr/bin/env bash

set -uo pipefail

job_root="${AGENT_BROWSER_JOB_ROOT:-}"
socket_dir="${AGENT_BROWSER_SOCKET_DIR:-}"
agent_browser_binary="${AGENT_BROWSER_BINARY:-}"
chromium_executables="${AGENT_BROWSER_CHROMIUM_EXECUTABLES:-}"
runner_temp="${RUNNER_TEMP:-}"
test_executables="${AGENT_BROWSER_CLEANUP_TEST_EXECUTABLES:-}"
cleanup_failed=0

if [[ -z "$job_root" ]]; then
  echo "AgentBrowser runtime root was not prepared; there is nothing to clean."
  exit 0
fi

case "$job_root" in
  /*/jido-ab.*) ;;
  *)
    echo "Refusing to clean an invalid AgentBrowser runtime root: $job_root" >&2
    exit 1
    ;;
esac

if [[ -z "$runner_temp" || "$job_root" != "$runner_temp"/* ]]; then
  echo "AgentBrowser runtime root is not under RUNNER_TEMP: $job_root" >&2
  exit 1
fi

if [[ "$socket_dir" != "$job_root/socket" ]]; then
  echo "AgentBrowser socket directory is outside the runtime root: $socket_dir" >&2
  exit 1
fi

if [[ ! -r /proc/self/stat ]]; then
  echo "Exact AgentBrowser process cleanup requires Linux /proc." >&2
  exit 1
fi

marker_path="$job_root/.jido-browser-agent-browser-root"
marker_valid=0

if [[ -f "$marker_path" ]]; then
  IFS= read -r marker_root < "$marker_path" || true

  if [[ "${marker_root:-}" == "$job_root" ]]; then
    marker_valid=1
  fi
elif [[ ! -e "$job_root" && ! -L "$job_root" ]]; then
  marker_valid=1
fi

if [[ "$marker_valid" -ne 1 ]]; then
  echo "AgentBrowser runtime root has no valid cleanup marker: $job_root" >&2
  cleanup_failed=1
fi

read_process_stat_field() {
  local process_pid="$1"
  local field="$2"
  local stat_line
  local stat_rest
  local stat_fields

  IFS= read -r stat_line 2>/dev/null < "/proc/$process_pid/stat" || return 1
  stat_rest="${stat_line##*) }"
  read -r -a stat_fields <<< "$stat_rest"

  case "$field" in
    ppid)
      [[ "${#stat_fields[@]}" -ge 2 ]] || return 1
      printf '%s\n' "${stat_fields[1]}"
      ;;
    start_time)
      [[ "${#stat_fields[@]}" -ge 20 ]] || return 1
      printf '%s\n' "${stat_fields[19]}"
      ;;
    *)
      return 1
      ;;
  esac
}

excluded_records=()
ancestor_pid="$$"

while [[ "$ancestor_pid" =~ ^[0-9]+$ && "$ancestor_pid" -gt 0 ]]; do
  ancestor_start="$(read_process_stat_field "$ancestor_pid" start_time 2>/dev/null || true)"

  if [[ -n "$ancestor_start" ]]; then
    excluded_records+=("$ancestor_pid:$ancestor_start")
  fi

  ancestor_pid="$(read_process_stat_field "$ancestor_pid" ppid 2>/dev/null || true)"
done

is_excluded_record() {
  local candidate_record="$1"
  local excluded_record

  for excluded_record in "${excluded_records[@]}"; do
    if [[ "$candidate_record" == "$excluded_record" ]]; then
      return 0
    fi
  done

  return 1
}

agent_browser_executable_id=""
chromium_executable_ids=()
test_executable_ids=()

executable_id_for_path() {
  local executable_path="$1"

  [[ -n "$executable_path" && -x "$executable_path" ]] || return 1
  stat -Lc '%d:%i' -- "$executable_path" 2>/dev/null
}

add_unique_executable_id() {
  local executable_id="$1"
  local array_name="$2"
  local existing_id

  declare -n executable_ids_ref="$array_name"

  for existing_id in "${executable_ids_ref[@]}"; do
    if [[ "$existing_id" == "$executable_id" ]]; then
      return 0
    fi
  done

  executable_ids_ref+=("$executable_id")
}

agent_browser_executable_id="$(executable_id_for_path "$agent_browser_binary" 2>/dev/null || true)"

if [[ -n "$chromium_executables" ]]; then
  IFS=: read -r -a configured_chromium_executables <<< "$chromium_executables"

  for chromium_executable in "${configured_chromium_executables[@]}"; do
    chromium_executable_id="$(executable_id_for_path "$chromium_executable" 2>/dev/null || true)"

    if [[ -n "$chromium_executable_id" ]]; then
      add_unique_executable_id "$chromium_executable_id" chromium_executable_ids
    fi
  done
fi

if [[ -n "$test_executables" ]]; then
  IFS=: read -r -a extra_executables <<< "$test_executables"

  for extra_executable in "${extra_executables[@]}"; do
    extra_executable_id="$(executable_id_for_path "$extra_executable" 2>/dev/null || true)"

    if [[ -n "$extra_executable_id" ]]; then
      add_unique_executable_id "$extra_executable_id" test_executable_ids
    fi
  done
fi

path_is_inside_job_root() {
  local candidate_path="$1"

  [[ "$candidate_path" == "$job_root" || "$candidate_path" == "$job_root/"* ]]
}

process_has_exact_job_root_environment() {
  local process_pid="$1"
  local entry

  if [[ -r "/proc/$process_pid/environ" ]]; then
    while IFS= read -r -d '' entry; do
      if [[ "$entry" == "AGENT_BROWSER_JOB_ROOT=$job_root" ]]; then
        return 0
      fi
    done 2>/dev/null < "/proc/$process_pid/environ" || true
  fi

  return 1
}

process_has_job_root_profile_argument() {
  local process_pid="$1"
  local entry
  local option_value
  local next_entry_is_profile=0

  if [[ -r "/proc/$process_pid/cmdline" ]]; then
    while IFS= read -r -d '' entry; do
      if [[ "$next_entry_is_profile" -eq 1 ]]; then
        path_is_inside_job_root "$entry"
        return
      fi

      case "$entry" in
        --user-data-dir)
          next_entry_is_profile=1
          ;;
        --user-data-dir=*)
          option_value="${entry#--user-data-dir=}"

          if path_is_inside_job_root "$option_value"; then
            return 0
          fi
          ;;
      esac
    done 2>/dev/null < "/proc/$process_pid/cmdline" || true
  fi

  return 1
}

validated_executable_kind=""

process_has_trusted_executable() {
  local process_pid="$1"
  local executable_id
  local allowed_id

  validated_executable_kind=""
  executable_id="$(stat -Lc '%d:%i' -- "/proc/$process_pid/exe" 2>/dev/null)" || return 1

  if [[ -n "$agent_browser_executable_id" &&
        "$executable_id" == "$agent_browser_executable_id" ]]; then
    validated_executable_kind="agent_browser"
    return 0
  fi

  for allowed_id in "${chromium_executable_ids[@]}"; do
    if [[ "$executable_id" == "$allowed_id" ]]; then
      validated_executable_kind="chromium"
      return 0
    fi
  done

  for allowed_id in "${test_executable_ids[@]}"; do
    if [[ "$executable_id" == "$allowed_id" ]]; then
      validated_executable_kind="test"
      return 0
    fi
  done

  return 1
}

validated_start_time=""

process_identity_is_owned() {
  local process_pid="$1"
  local expected_start_time="$2"
  local start_time_before
  local start_time_after

  validated_start_time=""
  start_time_before="$(read_process_stat_field "$process_pid" start_time 2>/dev/null)" || return 1

  if [[ -n "$expected_start_time" && "$start_time_before" != "$expected_start_time" ]]; then
    return 1
  fi

  process_has_exact_job_root_environment "$process_pid" || return 1
  process_has_trusted_executable "$process_pid" || return 1

  if [[ "$validated_executable_kind" == "chromium" ]]; then
    process_has_job_root_profile_argument "$process_pid" || return 1
  fi

  start_time_after="$(read_process_stat_field "$process_pid" start_time 2>/dev/null)" || return 1

  if [[ "$start_time_before" != "$start_time_after" ]]; then
    return 1
  fi

  validated_start_time="$start_time_after"
  return 0
}

owned_records=()

discover_owned_processes() {
  local process_path
  local process_pid
  local process_start_time
  local process_record

  owned_records=()

  for process_path in /proc/[0-9]*; do
    process_pid="${process_path#/proc/}"
    process_start_time="$(read_process_stat_field "$process_pid" start_time 2>/dev/null || true)"

    if [[ -z "$process_start_time" ]]; then
      continue
    fi

    process_record="$process_pid:$process_start_time"

    if is_excluded_record "$process_record"; then
      continue
    fi

    if process_identity_is_owned "$process_pid" "$process_start_time"; then
      owned_records+=("$process_pid:$validated_start_time")
    fi
  done
}

signal_owned_record() {
  local process_record="$1"
  local signal_name="$2"
  local process_pid="${process_record%%:*}"
  local expected_start_time="${process_record#*:}"
  if is_excluded_record "$process_record"; then
    return 1
  fi

  if ! process_identity_is_owned "$process_pid" "$expected_start_time"; then
    return 1
  fi

  kill -s "$signal_name" "$process_pid" 2>/dev/null
}

signal_owned_processes() {
  local signal_name="$1"
  local process_record
  local signaled_records=()

  for process_record in "${owned_records[@]}"; do
    if signal_owned_record "$process_record" "$signal_name"; then
      signaled_records+=("$process_record")
    fi
  done

  if [[ "${#signaled_records[@]}" -gt 0 ]]; then
    echo "Sent $signal_name to verified job-owned processes: ${signaled_records[*]}"
  fi
}

wait_for_owned_processes_to_exit() {
  local wait_seconds="$1"
  local deadline=$((SECONDS + wait_seconds))

  while ((SECONDS < deadline)); do
    discover_owned_processes

    if [[ "${#owned_records[@]}" -eq 0 ]]; then
      return 0
    fi

    sleep 0.1
  done

  discover_owned_processes
  [[ "${#owned_records[@]}" -eq 0 ]]
}

cleanup_agent_browser() {
  discover_owned_processes
  signal_owned_processes TERM

  if ! wait_for_owned_processes_to_exit 3; then
    echo "Verified job-owned processes did not exit during the bounded TERM wait."
  fi

  discover_owned_processes
  signal_owned_processes KILL

  if ! wait_for_owned_processes_to_exit 2; then
    echo "Verified job-owned processes remain after the bounded KILL wait." >&2
    cleanup_failed=1
  fi

  if [[ "$marker_valid" -eq 1 && ( -e "$job_root" || -L "$job_root" ) ]]; then
    rm -rf -- "$job_root" || cleanup_failed=1
  fi

  discover_owned_processes

  if [[ "${#owned_records[@]}" -gt 0 ]]; then
    echo "Verified job-owned processes remain: ${owned_records[*]}" >&2
    cleanup_failed=1
  fi

  if [[ -e "$job_root" || -L "$job_root" ]]; then
    echo "AgentBrowser runtime artifacts remain under: $job_root" >&2
    cleanup_failed=1
  fi

  if [[ "$cleanup_failed" -eq 0 ]]; then
    echo "Verified AgentBrowser processes and runtime artifacts were removed."
  fi

  return "$cleanup_failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cleanup_agent_browser
  exit $?
fi
