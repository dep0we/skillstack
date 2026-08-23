#!/bin/bash
# The tool must refuse to guess. Taking every skill is how one project ended up
# with 165 of its 194 tracked files being skill copies, so "all of them" has to
# be unreachable, not merely discouraged.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
run_lay "$out" --pack "$PACK" "$t"
rc=$?

check_eq "exits 1 when --skills is absent" 1 "$rc"
check "says it is refusing to guess" grep -q "Refusing to guess" "$out"
check "lists the skills so the caller can choose" grep -q "brainstorming" "$out"
check "no manifest was written" test ! -f "$t/.vendored-skills.json"
check "no skill directory was created" test ! -d "$t/.claude"

# The refusal must not be reachable by an empty value either.
run_lay "$out" --pack "$PACK" --skills "" "$t"
check_eq "exits 1 on an empty --skills" 1 "$?"
check "still no manifest" test ! -f "$t/.vendored-skills.json"

rm -rf "$t"
finish
