#!/bin/bash
# Every value that becomes a path segment is validated before it is
# interpolated anywhere. A skill name reaches three path positions.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"

run_lay "$out" --skills "no-such-skill" "$t"
check_eq "unknown skill exits 1" 1 "$?"
check "names the skill it could not find" grep -q "no-such-skill" "$out"
check "wrote nothing" test ! -f "$t/.vendored-skills.json"

for bad in "../escape" "a/b" ".." "." "skills/executing-plans" 'a\b'; do
  run_lay "$out" --skills "$bad" "$t"
  check_eq "refuses skill name '$bad'" 1 "$?"
done
check "no directory escaped the target" test ! -d "$t/../.claude"
check "nothing was laid" test ! -d "$t/.claude"

run_lay "$out" --skills "executing-plans,executing-plans" "$t"
check_eq "refuses a skill named twice" 1 "$?"

run_lay "$out" --skills "executing-plans" --targets elsewhere "$t"
check_eq "refuses an unknown --targets value" 1 "$?"
run_lay "$out" --skills "executing-plans" --targets "$t"
check_eq "refuses --targets with no value" 1 "$?"

run_lay "$out" --skills "executing-plans" --forget executing-plans "$t"
check_eq "refuses --skills with --forget" 1 "$?"
run_lay "$out" --rules --forget executing-plans "$t"
check_eq "refuses --rules with --forget" 1 "$?"
run_lay "$out" --list --skills executing-plans "$t"
check_eq "refuses --list with --skills" 1 "$?"

rm -rf "$t" "$out"
finish
