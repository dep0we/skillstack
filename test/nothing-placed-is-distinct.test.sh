#!/bin/bash
# A run that placed nothing must not read like a run that placed something.
# In this repository's neighbour, a check that could not run and a check that
# found nothing have returned the same clean result about ten times, and it is
# the most expensive recurring mistake either repo has made.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
placed="$(new_out)"
nothing="$(new_out)"

run_lay "$placed" --pack "$PACK" --skills "executing-plans" "$t"
check_eq "a real lay-down exits 0" 0 "$?"
check_fails "and does NOT claim nothing was placed" grep -q "NOTHING WAS PLACED" "$placed"

# Now make every candidate file unwritable-by-policy: present on disk and
# unrecorded, so all of them are skipped and none is written.
t2="$(new_target)" || exit 1
mkdir -p "$t2/.claude/skills/executing-plans" "$t2/.agents/skills/executing-plans"
printf 'mine\n' > "$t2/.claude/skills/executing-plans/SKILL.md"
printf 'mine\n' > "$t2/.agents/skills/executing-plans/SKILL.md"

run_lay "$nothing" --pack "$PACK" --skills "executing-plans" "$t2"
check_eq "a run that placed nothing exits 2" 2 "$?"
check "and says so in its own words" grep -q "NOTHING WAS PLACED" "$nothing"
check "written count is zero" grep -qE '^written:   0$' "$nothing"

# The two outputs must not be confusable. This is the whole point.
check_fails "the two runs do not print the same thing" diff -q "$placed" "$nothing"

rm -rf "$t" "$t2" "$placed" "$nothing"
finish
