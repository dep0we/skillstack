#!/bin/bash
# Shared helpers for the skillstack test suite. Sourced, never run. The shebang
# is here to tell shellcheck which shell these are written for; nothing
# executes this file.
#
# Every test builds its own scratch target repository and never touches the
# repository it is testing. The one exception is the dirty-pack test, which
# mutates a tracked file on purpose and restores it BY FILE COPY rather than
# with git checkout, because a checkout restores to the index and would discard
# any uncommitted work in the tree it ran against.

set -uo pipefail

SKILLSTACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAY="$SKILLSTACK_ROOT/bin/lay-pack.sh"
FAILURES=0
CHECKS=0

pass() { CHECKS=$((CHECKS+1)); printf '    ok   %s\n' "$1"; }
fail() { CHECKS=$((CHECKS+1)); FAILURES=$((FAILURES+1)); printf '    FAIL %s\n' "$1"; }

check() {  # check <description> <condition-as-command...>
  local desc="$1"; shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}

check_eq() {  # check_eq <description> <expected> <actual>
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$desc"
  else
    fail "$desc (expected '$expected', got '$actual')"
  fi
}

# A test scratch directory that is a real git repository, since the tool
# refuses a target that is not one.
new_target() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/skillstack-test.XXXXXX")" || return 1
  d="$(cd "$d" && pwd)" || return 1
  git -C "$d" init --quiet
  git -C "$d" config user.email test@example.invalid
  git -C "$d" config user.name test
  printf '# scratch\n' > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" commit --quiet -m scratch
  printf '%s' "$d"
}

# Run the tool and capture status WITHOUT a pipe. Piping replaces the exit
# status with the pipe's, which has hidden real failures in the neighbouring
# repository more than once.
run_lay() {  # run_lay <outfile> <args...>
  local out="$1" rc
  shift
  "$LAY" "$@" > "$out" 2>&1
  rc=$?
  # Bash resolves a function name when the call runs, not when the file is
  # parsed, so a call sitting above its own definition is not a syntax error.
  # The name resolves to nothing, the shell says so on stderr, the call is
  # SKIPPED, and the status is 127, which nothing in the tool reads. A caller
  # then sees a command that finished cleanly and checked nothing. Every run
  # in this suite is a detector for that shape, because it costs one line here
  # and no list of function names could be kept complete.
  if grep -q 'command not found' "$out"; then
    fail "a command in the tool resolved to nothing: $(grep -m1 'command not found' "$out")"
  fi
  return "$rc"
}

finish() {
  [ -n "${FIXTURE_DIR:-}" ] && rm -rf "$FIXTURE_DIR"
  printf '  %d checks, %d failed\n' "$CHECKS" "$FAILURES"
  [ "$FAILURES" -eq 0 ] || exit 1
  exit 0
}

# check_fails <description> <command...> -- passes when the command FAILS.
# Written as its own helper because the alternative spellings people reach for
# ("test -z $(grep -c ...)") are easy to make vacuously true, and a vacuous
# check reports ok forever without ever exercising anything.
check_fails() {
  local desc="$1"; shift
  if "$@"; then fail "$desc (command unexpectedly succeeded)"; else pass "$desc"; fi
}

# A scratch file for captured output, OUTSIDE any target repository. Writing it
# inside the target makes the target's own untracked-file count wrong, which
# silently breaks any test asserting that a run created nothing.
new_out() { mktemp "${TMPDIR:-/tmp}/skillstack-out.XXXXXX"; }

# ------------------------------------------------------------ the skills source
#
# Tests never read the real dep0we/skills clone. Sourcing this file builds a
# throwaway git repository shaped like it (a primary-set.txt, skills spread
# over three folders, one folder deliberately unlisted), commits it, then
# commits a SECOND change and leaves an uncommitted edit in the working tree.
# The pin points at the first commit, so a tool that read the head commit or
# the working tree would lay the wrong bytes, and the tests can tell.
#
# SKILLS_REPO and SKILLS_LOCK_FILE are exported, so every run_lay in a test
# file reads this fixture and cannot reach the real clone by accident.

FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/skillstack-fixture.XXXXXX")" || exit 1
FIXTURE_DIR="$(cd "$FIXTURE_DIR" && pwd)"
FIXTURE_REPO="$FIXTURE_DIR/skills"
mkdir -p "$FIXTURE_REPO"
git -C "$FIXTURE_REPO" init --quiet
git -C "$FIXTURE_REPO" config user.email test@example.invalid
git -C "$FIXTURE_REPO" config user.name test

fixture_file() {  # fixture_file <path in repo> <content>
  mkdir -p "$FIXTURE_REPO/$(dirname "$1")"
  printf '%s\n' "$2" > "$FIXTURE_REPO/$1"
}

printf '%s\n' \
  '# fixture install manifest' \
  '' \
  'skills/executing-plans' \
  'vendor/superpowers/brainstorming' \
  'vendor/superpowers/subagent-driven-development' \
  'carried/writing-plans' > "$FIXTURE_REPO/primary-set.txt"
fixture_file skills/executing-plans/SKILL.md "executing-plans COMMIT ONE"
fixture_file skills/executing-plans/scripts/run.sh "#!/bin/sh"
chmod +x "$FIXTURE_REPO/skills/executing-plans/scripts/run.sh"
fixture_file vendor/superpowers/brainstorming/SKILL.md "brainstorming COMMIT ONE"
fixture_file vendor/superpowers/brainstorming/visual-companion.md "companion notes"
fixture_file vendor/superpowers/subagent-driven-development/SKILL.md "sdd COMMIT ONE"
fixture_file carried/writing-plans/SKILL.md "writing-plans COMMIT ONE"
fixture_file skills/hidden/SKILL.md "a folder primary-set.txt does not list"
git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" commit --quiet -m "fixture one"
# shellcheck disable=SC2034  # read by the files that source this one
FIXTURE_PIN="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"

fixture_file skills/executing-plans/SKILL.md "executing-plans COMMIT TWO"
git -C "$FIXTURE_REPO" add -A
git -C "$FIXTURE_REPO" commit --quiet -m "fixture two"
# shellcheck disable=SC2034  # read by the files that source this one
FIXTURE_HEAD="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
fixture_file skills/executing-plans/SKILL.md "executing-plans WORKING TREE EDIT"

FIXTURE_LOCK="$FIXTURE_DIR/source.lock"
printf '# fixture pin\n%s\n' "$FIXTURE_PIN" > "$FIXTURE_LOCK"

export SKILLS_REPO="$FIXTURE_REPO"
export SKILLS_LOCK_FILE="$FIXTURE_LOCK"
