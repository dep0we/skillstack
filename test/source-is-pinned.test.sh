#!/bin/bash
# Skills come from one pinned commit of dep0we/skills and nowhere else. These
# are the refusals around that: a name the source does not list, a pinned commit
# the clone does not hold, a malformed pin, and the retired --pack flag.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"

# ------------------------------------------------- a name primary-set.txt omits
#
# skills/hidden is a real folder in the pinned commit. It is not listed, so it
# is not installable. Being in the repository is not the same as being listed.
run_lay "$out" --skills "hidden" "$t"
check_eq "refuses a skill the source does not list" 1 "$?"
check "names the skill" grep -q "hidden" "$out"
check "says it is not in primary-set.txt" grep -q "primary-set.txt" "$out"
check "wrote no manifest" test ! -f "$t/.vendored-skills.json"
check "laid nothing" test ! -d "$t/.claude"

# One bad name stops the whole run: no partial lay-down of the good ones.
run_lay "$out" --skills "executing-plans,hidden" "$t"
check_eq "a list with one unlisted name exits 1" 1 "$?"
check "and the listed one was not laid either" test ! -d "$t/.claude/skills/executing-plans"

# ------------------------------------------------ the pinned commit is missing
#
# The pin names a commit the clone does not hold. The tool says so in plain
# words and names the one command that fixes it. It must not run that command.
before_refs="$(git -C "$FIXTURE_REPO" for-each-ref | shasum -a 256 | awk '{print $1}')"
before_objs="$(git -C "$FIXTURE_REPO" count-objects -v | shasum -a 256 | awk '{print $1}')"
printf '# a pin the clone does not have\n%s\n' "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$FIXTURE_LOCK"
run_lay "$out" --skills "executing-plans" "$t"
check_eq "a missing pinned commit exits 1" 1 "$?"
check "says the pinned commit is not in the clone" grep -q "is not in the clone" "$out"
check "names the fetch command with the clone path" grep -qF "git -C $FIXTURE_REPO fetch" "$out"
check "says the tool never fetches" grep -q "never fetches" "$out"
check "wrote no manifest" test ! -f "$t/.vendored-skills.json"
check "laid nothing" test ! -d "$t/.claude"
check_eq "the clone's refs are untouched" "$before_refs" \
  "$(git -C "$FIXTURE_REPO" for-each-ref | shasum -a 256 | awk '{print $1}')"
check_eq "the clone's object store is untouched" "$before_objs" \
  "$(git -C "$FIXTURE_REPO" count-objects -v | shasum -a 256 | awk '{print $1}')"

# ------------------------------------------------------------ a malformed pin
for bad in "main" "69985ce" "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"; do
  printf '%s\n' "$bad" > "$FIXTURE_LOCK"
  run_lay "$out" --skills "executing-plans" "$t"
  check_eq "refuses a pin that is not a full commit hash ('$bad')" 1 "$?"
done
printf '# only a comment\n' > "$FIXTURE_LOCK"
run_lay "$out" --skills "executing-plans" "$t"
check_eq "refuses a pin file with no commit in it" 1 "$?"
rm -f "$FIXTURE_LOCK"
run_lay "$out" --skills "executing-plans" "$t"
check_eq "refuses a missing pin file" 1 "$?"
printf '# fixture pin\n%s\n' "$FIXTURE_PIN" > "$FIXTURE_LOCK"

# ---------------------------------------------------------- no clone at all
SKILLS_REPO="$FIXTURE_DIR/not-here" run_lay "$out" --skills "executing-plans" "$t"
check_eq "a missing clone exits 1" 1 "$?"
check "says where it looked" grep -qF "$FIXTURE_DIR/not-here" "$out"

# -------------------------------------------- the same command, pin restored
#
# Without this, every refusal above could have had any cause at all.
run_lay "$out" --skills "executing-plans" "$t"
check_eq "the same command succeeds with a good pin" 0 "$?"

# ----------------------------------------------------- --pack is retired
t2="$(new_target)" || exit 1
run_lay "$out" --pack superpowers --skills "executing-plans" "$t2"
check_eq "--pack exits 1" 1 "$?"
check "says packs are retired" grep -q "packs are retired" "$out"
check "points at dep0we/skills" grep -q "dep0we/skills" "$out"
check "wrote no manifest" test ! -f "$t2/.vendored-skills.json"
check "laid nothing" test ! -d "$t2/.claude"
run_lay "$out" --pack "$t2"
check_eq "--pack alone also exits 1" 1 "$?"
check "and also says retired" grep -q "packs are retired" "$out"

# ------------------------------------------- the shipped pin file is well formed
real="$SKILLSTACK_ROOT/source.lock"
check "source.lock exists at the repository root" test -f "$real"
real_pin="$(grep -v '^[[:space:]]*#' "$real" | grep -v '^[[:space:]]*$')"
check_eq "it holds exactly one non-comment line" "1" "$(printf '%s\n' "$real_pin" | grep -c '')"
check "and that line is a full 40-character commit hash" \
  bash -c 'printf "%s" "$1" | grep -Eq "^[0-9a-f]{40}$"' _ "$real_pin"
check "a comment says the pin moves to claude-config's skills.lock" grep -q "^#.*skills\.lock" "$real"

rm -rf "$t" "$t2" "$out"
finish
