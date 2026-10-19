#!/bin/bash
# The mechanic carried forward from vendor-skills.sh, and the reason the
# manifest holds a hash at all: a file whose content moved since it was laid
# down is never overwritten, and the warning has to persist across runs.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"
f=".claude/skills/executing-plans/SKILL.md"

run_lay "$out" --skills "executing-plans" "$t"
check_eq "first lay-down is clean" 0 "$?"
original_hash="$(jq -r --arg p "$f" '.skills["executing-plans"].files[] | select(.path==$p) | .sha256' "$m")"

printf '\nA HAND EDIT THAT MUST SURVIVE\n' >> "$t/$f"
edited_hash="$(shasum -a 256 "$t/$f" | awk '{print $1}')"

run_lay "$out" --skills "executing-plans" "$t"
check_eq "a hand edit makes the run exit 2" 2 "$?"
check "the edit was not overwritten" grep -q "A HAND EDIT THAT MUST SURVIVE" "$t/$f"
check "reports the skipped path" grep -q "edited since it was laid down" "$out"

kept="$(jq -r --arg p "$f" '.skills["executing-plans"].files[] | select(.path==$p) | .sha256' "$m")"
check_eq "manifest keeps the ORIGINAL hash, not the edited one" "$original_hash" "$kept"
check "the edited hash was not recorded" test "$kept" != "$edited_hash"

# The warning has to persist. Recording the edited hash would silence it.
run_lay "$out" --skills "executing-plans" "$t"
check_eq "still exits 2 on a later run" 2 "$?"
check "still reports it" grep -q "edited since it was laid down" "$out"

# A new pin does not get past the refusal either. The edit still wins.
printf '# newer pin\n%s\n' "$FIXTURE_HEAD" > "$FIXTURE_LOCK"
run_lay "$out" --skills "executing-plans" "$t"
check_eq "a newer pin still exits 2 over an edited file" 2 "$?"
check "and the edit is still there" grep -q "A HAND EDIT THAT MUST SURVIVE" "$t/$f"
printf '# fixture pin\n%s\n' "$FIXTURE_PIN" > "$FIXTURE_LOCK"

# A file present on disk that the manifest never recorded is refused too.
mkdir -p "$t/.claude/skills/brainstorming"
printf 'not mine\n' > "$t/.claude/skills/brainstorming/SKILL.md"
run_lay "$out" --skills "brainstorming" "$t"
check_eq "an unrecorded file makes the run exit 2" 2 "$?"
check "reports it as present but unrecorded" grep -q "present but not in" "$out"
check_eq "and did not overwrite it" "not mine" "$(cat "$t/.claude/skills/brainstorming/SKILL.md")"

rm -rf "$t" "$out"
finish
