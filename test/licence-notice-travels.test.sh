#!/bin/bash
# The upstream licence requires its notice to accompany every copy. In the
# skills source the notice sits above the skill folders (vendor/<set>/LICENSE),
# so the tool stages the nearest ancestor's notice into each laid skill, and
# records it like any other file.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"

run_lay "$out" --skills "brainstorming,subagent-driven-development,own-licensed,executing-plans" "$t"
check_eq "lay-down exits 0" 0 "$?"

for dir in .claude .agents; do
  for s in brainstorming subagent-driven-development; do
    f="$t/$dir/skills/$s/LICENSE"
    check "the set's notice reaches $dir/skills/$s" test -f "$f"
    check_eq "and is the ancestor's text ($dir/$s)" "MIT notice for the superpowers set" "$(cat "$f")"
    p="$dir/skills/$s/LICENSE"
    rec="$(jq -r --arg s "$s" --arg p "$p" '.skills[$s].files[] | select(.path==$p) | .sha256' "$m")"
    check_eq "and is recorded with its hash ($dir/$s)" "$(shasum -a 256 "$f" | awk '{print $1}')" "$rec"
  done
  check_eq "a skill with its own notice keeps it ($dir)" "the skill's own notice" \
    "$(cat "$t/$dir/skills/own-licensed/LICENSE")"
  check "a skill with no ancestor notice gets none ($dir)" test ! -e "$t/$dir/skills/executing-plans/LICENSE"
done

# --targets agents carries it too.
t2="$(new_target)" || exit 1
run_lay "$out" --skills "brainstorming" --targets agents "$t2"
check "agents-only still gets the notice" test -f "$t2/.agents/skills/brainstorming/LICENSE"

# It is protected like any laid file.
printf 'edit\n' >> "$t/.claude/skills/brainstorming/LICENSE"
run_lay "$out" --skills "brainstorming" "$t"
check_eq "an edited notice makes the run exit 2" 2 "$?"
check "and is reported" grep -q "skills/brainstorming/LICENSE (edited" "$out"

rm -rf "$t" "$t2" "$out"
finish
