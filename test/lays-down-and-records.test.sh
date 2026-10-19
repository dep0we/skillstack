#!/bin/bash
# The happy path, and the shape of what it records. Schema 5 exactly, laid from
# a fixture repository at a pinned commit.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"

run_lay "$out" --skills "executing-plans,brainstorming" "$t"
check_eq "exits 0 on a clean lay-down" 0 "$?"
check "wrote a manifest" test -f "$m"

check_eq "schema is 5" "5" "$(jq -r '.schemaVersion' "$m")"
check_eq "records the source repository" "dep0we/skills" "$(jq -r '.source.repo' "$m")"
check_eq "records the pinned source commit" "$FIXTURE_PIN" "$(jq -r '.source.commit' "$m")"
check_eq "has no pack section" "false" "$(jq 'has("packs")' "$m")"
check_eq "records both selected skills, keyed by name" "brainstorming,executing-plans" \
  "$(jq -r '.skills | keys | join(",")' "$m")"
check_eq "records the folder a skill came from" "vendor/superpowers/brainstorming" \
  "$(jq -r '.skills.brainstorming.folder' "$m")"
check_eq "records the commit per skill" "$FIXTURE_PIN" \
  "$(jq -r '.skills["executing-plans"].commit' "$m")"
check "records an installedAt" test -n "$(jq -r '.skills.brainstorming.installedAt' "$m")"
check_eq "no rules entry when --rules was not asked for" "false" "$(jq 'has("rules")' "$m")"

# The pin is a commit, and the commit is what gets read. The clone's head
# commit and its working tree both hold different text for this file.
sk=".claude/skills/executing-plans/SKILL.md"
check_eq "the bytes come from the pinned commit" "executing-plans COMMIT ONE" "$(cat "$t/$sk")"
check_fails "not from the clone's next commit" grep -q "COMMIT TWO" "$t/$sk"
check_fails "and not from its working tree" grep -q "WORKING TREE EDIT" "$t/$sk"

# A skill is a folder: nested files come too, and the executable bit survives.
check "a nested file was laid" test -f "$t/.agents/skills/executing-plans/scripts/run.sh"
check "the executable bit survived" test -x "$t/.agents/skills/executing-plans/scripts/run.sh"
check "a second file in a skill was laid" test -f "$t/.claude/skills/brainstorming/visual-companion.md"

# The name is the folder's last path segment, whichever top folder it lives in.
run_lay "$out" --skills "executing-plans,brainstorming,writing-plans" "$t"
check_eq "a skill from the carried folder lays too" 0 "$?"
check "and lands under its last path segment" test -f "$t/.claude/skills/writing-plans/SKILL.md"

check_eq "no file entry carries shippedSha256" "0" \
  "$(jq '[.skills[].files[] | select(has("shippedSha256"))] | length' "$m")"

# Every recorded path has to be <allowed dir>/<its skill>/<file>. A path
# outside that is not skipped by the gate: it rejects the whole manifest.
bad="$(jq -r '.skills | to_entries[] | .key as $k | .value.files[].path | select((split("/")[2]) != $k)' "$m" | wc -l | tr -d ' ')"
check_eq "every recorded path sits under its own skill" "0" "$bad"
bad="$(jq -r '.skills[].files[].path' "$m" | grep -Ev '^(\.claude|\.agents)/skills/[a-z-]+/.+$' | wc -l | tr -d ' ')"
check_eq "every recorded path is allowed-dir/skill/file" "0" "$bad"

# Two directories, and exactly these two. Pinned by name, never by count: a
# number cannot say which decisions it is made of.
dirs="$(jq -r '.skills[].files[].path' "$m" | cut -d/ -f1 | sort -u | tr '\n' ' ')"
check_eq "written into exactly the two measured directories" ".agents .claude " "$dirs"

# Every recorded hash matches what is actually on disk right now.
mismatch=0
while IFS=$'\t' read -r p h; do
  [ -f "$t/$p" ] || { mismatch=$((mismatch+1)); continue; }
  d="$(shasum -a 256 "$t/$p" | awk '{print $1}')"
  [ "$d" = "$h" ] || mismatch=$((mismatch+1))
done < <(jq -r '.skills[].files[] | "\(.path)\t\(.sha256)"' "$m")
check_eq "every recorded hash matches the file on disk" "0" "$mismatch"

# The source has five skills. Selecting three must not lay down five.
laid="$(find "$t/.claude/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
check_eq "only the selected skills were laid down" "3" "$laid"
check "an unselected skill is absent" test ! -d "$t/.claude/skills/subagent-driven-development"

# --list has to read back what was written.
run_lay "$out" --list "$t"
check_eq "--list exits 0" 0 "$?"
check "--list names a skill" grep -q "skill: brainstorming" "$out"
check "--list names the source" grep -q "dep0we/skills @ $FIXTURE_PIN" "$out"

rm -rf "$t" "$out"
finish
