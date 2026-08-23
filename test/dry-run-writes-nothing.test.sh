#!/bin/bash
# A dry run has to be a dry run. Reporting what would happen while quietly
# doing half of it is worse than not offering the flag.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"

run_lay "$out" --pack "$PACK" --skills "executing-plans" --dry-run "$t"
check_eq "dry run exits 0" 0 "$?"
check "labels its output" grep -q "\[dry-run\]" "$out"
check "says the manifest was not updated" grep -q "was not updated" "$out"
check "wrote no manifest" test ! -f "$t/.vendored-skills.json"
check "created no .claude directory" test ! -d "$t/.claude"
check "created no .agents directory" test ! -d "$t/.agents"
check_eq "the target holds only what it started with" "1" \
  "$(git -C "$t" ls-files | wc -l | tr -d ' ')"
check_eq "and nothing untracked appeared" "0" \
  "$(git -C "$t" status --porcelain | grep -c '^??' | tr -d ' ')"

# A dry run over an already-laid tree must also change nothing.
run_lay "$out" --pack "$PACK" --skills "executing-plans" "$t"
m="$t/.vendored-skills.json"
before="$(shasum -a 256 "$m" | awk '{print $1}')"
run_lay "$out" --pack "$PACK" --skills "executing-plans" --dry-run "$t"
after="$(shasum -a 256 "$m" | awk '{print $1}')"
check_eq "a dry run over an existing install leaves the manifest byte-identical" "$before" "$after"

rm -rf "$t"
finish
