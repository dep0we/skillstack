#!/bin/bash
# Skills that are not committed never reach a cloud agent, which is the entire
# reason this tool copies files instead of installing a plugin.
source "$(dirname "$0")/helpers.sh"

d="$(mktemp -d "${TMPDIR:-/tmp}/skillstack-test.XXXXXX")"
d="$(cd "$d" && pwd)"
out="$(new_out)"

run_lay "$out" --pack "$PACK" --skills "brainstorming" "$d"
check_eq "exits 1 when the target is not a git repository" 1 "$?"
check "says why" grep -qi "not a git repository" "$out"
check "wrote nothing" test ! -f "$d/.vendored-skills.json"
check "created no skill directory" test ! -d "$d/.claude"

rm -rf "$d"
finish
