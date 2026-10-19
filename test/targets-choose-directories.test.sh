#!/bin/bash
# --targets decides which skill directories are written. "both" is the default
# and writes .agents/skills and .claude/skills. "agents" writes .agents/skills
# only. Narrowing must never drop a recorded file from the manifest.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"

run_lay "$out" --skills "executing-plans" --targets agents "$t"
check_eq "--targets agents exits 0" 0 "$?"
check "wrote .agents/skills" test -f "$t/.agents/skills/executing-plans/SKILL.md"
check "did not write .claude/skills" test ! -d "$t/.claude"
check_eq "records only .agents paths" ".agents" \
  "$(jq -r '.skills[].files[].path' "$m" | cut -d/ -f1 | sort -u | tr '\n' ' ' | sed 's/ $//')"
check "the report names the directory" grep -q "into 1 directories (.agents/skills)" "$out"

# Widening later fills in the other directory, with the same pinned bytes.
run_lay "$out" --skills "executing-plans" --targets both "$t"
check_eq "--targets both exits 0" 0 "$?"
check "now .claude/skills exists" test -f "$t/.claude/skills/executing-plans/SKILL.md"
check_eq "records both directories" ".agents .claude" \
  "$(jq -r '.skills[].files[].path' "$m" | cut -d/ -f1 | sort -u | tr '\n' ' ' | sed 's/ $//')"

# The default is both.
t2="$(new_target)" || exit 1
run_lay "$out" --skills "executing-plans" "$t2"
check "the default writes .claude/skills" test -f "$t2/.claude/skills/executing-plans/SKILL.md"
check "and .agents/skills" test -f "$t2/.agents/skills/executing-plans/SKILL.md"

# Narrowing after a both-directory lay keeps the other directory's entries.
before="$(jq -c '.skills["executing-plans"].files | map(.path) | sort' "$m")"
run_lay "$out" --skills "executing-plans" --targets agents "$t"
check_eq "narrowing exits 0" 0 "$?"
check_eq "and no recorded file was dropped" "$before" \
  "$(jq -c '.skills["executing-plans"].files | map(.path) | sort' "$m")"
check_fails "nor reported as an orphan" grep -q "no longer ships" "$out"
check "the .claude copy is still on disk" test -f "$t/.claude/skills/executing-plans/SKILL.md"

# A hand edit in the directory that was NOT targeted is not examined, so it is
# neither overwritten nor flagged by an agents-only run.
printf 'edit\n' >> "$t/.claude/skills/executing-plans/SKILL.md"
run_lay "$out" --skills "executing-plans" --targets agents "$t"
check_eq "an edit outside the targeted directory does not fail an agents-only run" 0 "$?"
check "and survives" grep -q "^edit$" "$t/.claude/skills/executing-plans/SKILL.md"
run_lay "$out" --skills "executing-plans" "$t"
check_eq "a default run does catch it" 2 "$?"

rm -rf "$t" "$t2" "$out"
finish
