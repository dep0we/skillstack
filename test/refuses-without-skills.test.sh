#!/bin/bash
# The tool must refuse to guess. Taking every skill is how one project ended up
# with 165 of its 194 tracked files being skill copies, so "all of them" has to
# be unreachable, not merely discouraged.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
run_lay "$out" "$t"
rc=$?

check_eq "exits 1 when neither --skills nor --rules is given" 1 "$rc"
check "says it is refusing to guess" grep -q "Refusing to guess" "$out"
check "lists the skills so the caller can choose" grep -q "brainstorming" "$out"
check_fails "the unlisted folder is not offered" grep -q "hidden" "$out"
check "no manifest was written" test ! -f "$t/.vendored-skills.json"
check "no skill directory was created" test ! -d "$t/.claude"

# The refusal must not be reachable by an empty value either.
run_lay "$out" --skills "" "$t"
check_eq "exits 1 on an empty --skills" 1 "$?"
check "still no manifest" test ! -f "$t/.vendored-skills.json"

# And there is no word for "all".
run_lay "$out" --skills "all" "$t"
check_eq "'all' is a skill name, not a wildcard, and is not listed" 1 "$?"
check "nothing was laid for it" test ! -d "$t/.claude"

rm -rf "$t" "$out"
finish
