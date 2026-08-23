#!/bin/bash
# --skills names the full set for a pack. A skill the manifest records and this
# run did not name is reported and KEPT, never silently dropped: dropping it
# leaves its files on disk and unrecorded, which is the exact state every
# future run skips and --forget exists to dig people out of.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"

run_lay "$out" --pack "$PACK" --skills "executing-plans" "$t"
check_eq "first lay-down clean" 0 "$?"

run_lay "$out" --pack "$PACK" --skills "brainstorming" "$t"
check_eq "narrowing the selection exits 2" 2 "$?"
check "reports the recorded-but-unselected skill" grep -q "NOT named in --skills" "$out"
check "names it" grep -q "executing-plans" "$out"

check_eq "it is still recorded in skills" "brainstorming,executing-plans" \
  "$(jq -r '.packs.superpowers.skills | join(",")' "$m")"
kept="$(jq -r '.packs.superpowers.files[].path' "$m" | grep -c 'executing-plans' | tr -d ' ')"
check "its file entries were carried forward" test "$kept" -gt 0
check "its files are still on disk" test -f "$t/.claude/skills/executing-plans/SKILL.md"

# Every carried-forward entry still has to hash-match disk, or the manifest is
# lying about a file it did not touch this run.
mismatch=0
while IFS=$'\t' read -r p h; do
  d="$(shasum -a 256 "$t/$p" | awk '{print $1}')"
  [ "$d" = "$h" ] || mismatch=$((mismatch+1))
done < <(jq -r '.packs.superpowers.files[] | "\(.path)\t\(.sha256)"' "$m")
check_eq "carried-forward hashes still match disk" "0" "$mismatch"

rm -rf "$t"
finish
