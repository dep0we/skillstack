#!/usr/bin/env bash
# Stop the brainstorm server and clean up
# Usage: stop-server.sh <session_dir>
#
# Kills the server process. Only deletes session directory if it's
# under /tmp (ephemeral). Persistent directories (.superpowers/) are
# kept so mockups can be reviewed later.

SESSION_DIR="$1"

if [[ -z "$SESSION_DIR" ]]; then
  echo '{"error": "Usage: stop-server.sh <session_dir>"}'
  exit 1
fi

# Refuse a symbolic link before anything else. This has to happen here, at
# the top, rather than beside the delete further down: every path below is
# built from this one, so a link accepted here means the process that gets
# signalled and the state files that get removed are another session's, even
# when the delete itself is later refused.
#
# Strip trailing slashes first. "-L link/" and "-L link/." both follow the
# link and report that it is not one, so either spelling walked past a check
# that tested the argument as given.
trimmed_session="$SESSION_DIR"
while [[ "${trimmed_session%/}" != "$trimmed_session" && -n "${trimmed_session%/}" ]]; do
  trimmed_session="${trimmed_session%/}"
done
session_leaf="${trimmed_session##*/}"
case "$session_leaf" in
  ""|"."|"..")
    echo '{"error": "Refusing a session directory named \".\", \"..\" or empty."}'
    exit 1
    ;;
esac
if [[ -L "$trimmed_session" ]]; then
  echo '{"error": "Refusing a session directory that is a symbolic link. Pass the directory itself."}'
  exit 1
fi
# A link anywhere in the path counts, not only at the end. Testing the last
# component alone let a link one level up through, and everything below was
# then built from it: another session's process was signalled and its state
# files removed, while only the final delete was refused.
#
# Compare the physical path against the one given. They differ exactly when
# some component was a link. The one allowance is the platform's own
# temporary directory, which is itself a link on some systems.
# ...and a link anywhere in the path, not only at the end. Sessions live
# under the temporary directory and under a project directory, and both
# cases matter: a link one level up let another session's process be
# stopped and its state removed while only the final delete was refused.
#
# The path has to be the real one already. The single allowance is the
# platform's own temporary root, which is itself a link on some systems.
if [[ -d "$trimmed_session" ]]; then
  physical_tmp="$(cd /tmp 2>/dev/null && pwd -P)"
  physical_session="$(cd "$trimmed_session" 2>/dev/null && pwd -P)"
  expected_session="$trimmed_session"
  case "$trimmed_session" in
    /tmp/*) expected_session="${physical_tmp}${trimmed_session#/tmp}" ;;
  esac
  if [[ -z "$physical_session" ]] ||
     { [[ "$physical_session" != "$trimmed_session" ]] &&
       [[ "$physical_session" != "$expected_session" ]]; }; then
    echo '{"error": "Refusing a session directory reached through a symbolic link. Pass the real path."}'
    exit 1
  fi
fi
SESSION_DIR="$trimmed_session"

STATE_DIR="${SESSION_DIR}/state"
PID_FILE="${STATE_DIR}/server.pid"
SERVER_ID_FILE="${STATE_DIR}/server-instance-id"

mark_stopped() {
  local reason="$1"
  rm -f "${STATE_DIR}/server-info"
  printf '{"reason":"%s","timestamp":%s}\n' "$reason" "$(date +%s)" > "${STATE_DIR}/server-stopped"
}

read_expected_server_id() {
  [[ -f "$SERVER_ID_FILE" ]] || return 1
  local id
  id="$(tr -d '\r\n' < "$SERVER_ID_FILE" 2>/dev/null || true)"
  [[ "$id" =~ ^[A-Za-z0-9_-]{32,64}$ ]] || return 1
  printf '%s\n' "$id"
}

command_line_for_pid() {
  local pid="$1"
  if [[ -r "/proc/$pid/cmdline" ]]; then
    tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null || true
    return 0
  fi
  ps -ww -p "$pid" -o command= 2>/dev/null || ps -f -p "$pid" 2>/dev/null | sed '1d' || true
}

command_has_server_id() {
  local pid="$1"
  local expected="$2"
  local expected_arg="--brainstorm-server-id=$expected"
  if [[ -r "/proc/$pid/cmdline" ]]; then
    local arg
    while IFS= read -r -d '' arg || [[ -n "$arg" ]]; do
      [[ "$arg" == "$expected_arg" ]] && return 0
    done < "/proc/$pid/cmdline"
    return 1
  fi
  local command_line
  command_line="$(command_line_for_pid "$pid")"
  [[ -n "$command_line" ]] || return 1
  case " $command_line " in
    *" $expected_arg "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Confirm a PID has this session's per-start instance id, not just a familiar
# process name. Ambiguous or legacy metadata fails closed as stale_pid.
is_brainstorm_server() {
  kill -0 "$1" 2>/dev/null || return 1
  local expected_id
  expected_id="$(read_expected_server_id)" || return 1
  command_has_server_id "$1" "$expected_id" || return 1
  return 0
}

if [[ -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE")

  # Refuse to signal a PID we can't prove is our server. A stale pid file may
  # point at an unrelated process after a reboot/PID wraparound.
  if ! is_brainstorm_server "$pid"; then
    rm -f "$PID_FILE" "$SERVER_ID_FILE"
    mark_stopped "stale_pid"
    echo '{"status": "stale_pid"}'
    exit 0
  fi

  # Try to stop gracefully, fallback to force if still alive
  kill "$pid" 2>/dev/null || true

  # Wait for graceful shutdown (up to ~2s)
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done

  # If still running, escalate to SIGKILL
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true

    # Give SIGKILL a moment to take effect
    sleep 0.1
  fi

  if kill -0 "$pid" 2>/dev/null; then
    echo '{"status": "failed", "error": "process still running"}'
    exit 1
  fi

  rm -f "$PID_FILE" "$SERVER_ID_FILE" "${STATE_DIR}/server.log"
  mark_stopped "stop-server.sh"

  # Only delete ephemeral /tmp directories.
  #
  # The rule is not "the path starts with /tmp": that is a text comparison,
  # and "/tmp/../else" satisfies it while resolving somewhere else. Nor is
  # it enough to reject a link at the end of the path, because the spelling
  # of the path decides whether a link is visible to that test at all.
  #
  # The rule is: this must be one directory, named directly under the real
  # temporary directory, which is what this script creates and the only
  # thing it may remove. More than one component under it, anything reached
  # through a link, and anything whose resolved name is not the name asked
  # for, are all refused. That covers every spelling at once rather than one
  # at a time, which is how the earlier versions of this check kept failing.
  #
  # It still cannot be airtight in a shell. Between the check and the delete
  # another process could swap a component for a link. This narrows that
  # window; it does not close it.
  resolved_tmp="$(cd /tmp 2>/dev/null && pwd -P)"
  may_delete=""
  if [ -n "$resolved_tmp" ] && [ -d "$SESSION_DIR" ] && [ ! -L "$SESSION_DIR" ]; then
    case "$SESSION_DIR" in
      "/tmp/"*/*|"$resolved_tmp/"*/*) ;;
      "/tmp/"?*|"$resolved_tmp/"?*)
        resolved_session="$(cd "$SESSION_DIR" 2>/dev/null && pwd -P)"
        if [ -n "$resolved_session" ] && [ "$resolved_session" = "$resolved_tmp/$session_leaf" ]; then
          may_delete="$resolved_session"
        fi
        ;;
    esac
  fi
  if [ -n "$may_delete" ]; then
    rm -rf -- "$may_delete"
  fi

  echo '{"status": "stopped"}'
else
  echo '{"status": "not_running"}'
fi
