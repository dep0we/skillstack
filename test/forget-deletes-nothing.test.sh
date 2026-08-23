#!/bin/bash
# --forget is the single deliberate way past the hand-edit refusal, and its
# whole contract is that it deletes nothing. It re-records the CURRENT hash so
# the next run sees a tracked, unmodified file and overwrites it normally.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"
f=".claude/skills/executing-plans/SKILL.md"

run_lay "$out" --pack "$PACK" --skills "executing-plans" "$t"
before_count="$(find "$t/.claude" "$t/.agents" -type f | wc -l | tr -d ' ')"

printf '\nEDIT\n' >> "$t/$f"
run_lay "$out" --pack "$PACK" --forget "executing-plans" "$t"
check_eq "--forget exits 0" 0 "$?"
check "says nothing was deleted" grep -q "Nothing was deleted" "$out"

after_count="$(find "$t/.claude" "$t/.agents" -type f | wc -l | tr -d ' ')"
check_eq "--forget removed no files" "$before_count" "$after_count"
check "the edited file is still there" test -f "$t/$f"

now="$(shasum -a 256 "$t/$f" | awk '{print $1}')"
rec="$(jq -r --arg p "$f" '.packs.superpowers.files[] | select(.path==$p) | .sha256' "$m")"
check_eq "re-recorded at the current on-disk hash" "$now" "$rec"

run_lay "$out" --pack "$PACK" --skills "executing-plans" "$t"
check_eq "the next run is clean again" 0 "$?"
check_fails "and the edit is gone, as asked" grep -q "^EDIT$" "$t/$f"

# The case --forget exists for: a file on disk the manifest never recorded.
# Walking only the manifest would leave it unreachable forever.
printf 'stray\n' > "$t/.claude/skills/executing-plans/STRAY.md"
run_lay "$out" --pack "$PACK" --forget "executing-plans" "$t"
check_eq "--forget adopts an unrecorded file" 0 "$?"
check "and says so" grep -q "unrecorded" "$out"
check "the stray file still exists" test -f "$t/.claude/skills/executing-plans/STRAY.md"

rm -rf "$t"
finish
