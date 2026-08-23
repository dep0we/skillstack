#!/bin/bash
# The happy path, and the shape of what it records. Schema 4 exactly.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"

run_lay "$out" --pack "$PACK" --skills "executing-plans,brainstorming" "$t"
check_eq "exits 0 on a clean lay-down" 0 "$?"
check "wrote a manifest" test -f "$m"

check_eq "schema is 4" "4" "$(jq -r '.schemaVersion' "$m")"
check_eq "keyed by pack name, not skill name" "superpowers" "$(jq -r '.packs | keys | join(",")' "$m")"
check_eq "source is skillstack" "skillstack" "$(jq -r '.packs.superpowers.source' "$m")"
check_eq "records both selected skills, sorted" "brainstorming,executing-plans" \
  "$(jq -r '.packs.superpowers.skills | join(",")' "$m")"
check "records a packCommit" test -n "$(jq -r '.packs.superpowers.packCommit' "$m")"
check "records the upstream commit" test -n "$(jq -r '.packs.superpowers.upstream.commit' "$m")"
check "records an installedAt" test -n "$(jq -r '.packs.superpowers.installedAt' "$m")"

# The removed schema 3 field is rejected by a reader rather than ignored, so
# writing one would fail every project loudly.
check_eq "no file entry carries shippedSha256" "0" \
  "$(jq '[.packs.superpowers.files[] | select(has("shippedSha256"))] | length' "$m")"

# Every recorded path has to be <allowed dir>/<selected skill>/<file>. A path
# outside that is not skipped by the gate: it rejects the whole manifest.
bad="$(jq -r '.packs.superpowers.files[].path' "$m" \
  | grep -Ev '^(\.claude|\.agents)/skills/(brainstorming|executing-plans)/.+$' | wc -l | tr -d ' ')"
check_eq "every recorded path is allowed-dir/selected-skill/file" "0" "$bad"

# Two directories, and exactly these two. Pinned by name, never by count: a
# number cannot say which decisions it is made of.
dirs="$(jq -r '.packs.superpowers.files[].path' "$m" | cut -d/ -f1 | sort -u | tr '\n' ' ')"
check_eq "written into exactly the two measured directories" ".agents .claude " "$dirs"

# Every recorded hash matches what is actually on disk right now.
mismatch=0
while IFS=$'\t' read -r p h; do
  [ -f "$t/$p" ] || { mismatch=$((mismatch+1)); continue; }
  d="$(shasum -a 256 "$t/$p" | awk '{print $1}')"
  [ "$d" = "$h" ] || mismatch=$((mismatch+1))
done < <(jq -r '.packs.superpowers.files[] | "\(.path)\t\(.sha256)"' "$m")
check_eq "every recorded hash matches the file on disk" "0" "$mismatch"

# The pack has fourteen skills. Selecting two must not lay down fourteen.
laid="$(find "$t/.claude/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
check_eq "only the selected skills were laid down" "2" "$laid"
check "an unselected skill is absent" test ! -d "$t/.claude/skills/writing-plans"

# --list has to read back what was written.
run_lay "$out" --list "$t"
check_eq "--list exits 0" 0 "$?"
check "--list names the pack" grep -q "superpowers" "$out"

rm -rf "$t"
finish
