#!/bin/bash
# --rules keeps one managed block at the top of the project's AGENTS.md,
# between two marker lines. The guarantees that matter: running it twice changes
# nothing, a hand-edited block is reported and skipped rather than overwritten,
# and nothing outside the markers is ever touched.
source "$(dirname "$0")/helpers.sh"

BEGIN='<!-- shared-rules:begin -->'
END='<!-- shared-rules:end -->'

rules="$FIXTURE_DIR/working-with-dan.md"
printf '# Working rules\n\nAnswer first. Plain words.\n' > "$rules"
export SHARED_RULES_FILE="$rules"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"
a="$t/AGENTS.md"

# Rules alone never need the skills source, so a source that cannot be read
# must not block them.
SKILLS_REPO="$FIXTURE_DIR/not-here" run_lay "$out" --rules "$t"
check_eq "--rules alone exits 0 without a skills clone" 0 "$?"

# ------------------------------------------------------------ create
check "created AGENTS.md" test -f "$a"
check_eq "begin marker is the first line" "$BEGIN" "$(sed -n 1p "$a")"
check_eq "end marker is the last line" "$END" "$(tail -n 1 "$a")"
check "the rules text is inside" grep -q "Answer first. Plain words." "$a"
check_eq "exactly one begin marker" "1" "$(grep -cxF "$BEGIN" "$a" | tr -d ' ')"
check_eq "exactly one end marker" "1" "$(grep -cxF "$END" "$a" | tr -d ' ')"
check "says what it did" grep -q "created AGENTS.md" "$out"

check_eq "manifest is schema 5" "5" "$(jq -r '.schemaVersion' "$m")"
check_eq "records the target file" "AGENTS.md" "$(jq -r '.rules.file' "$m")"
check_eq "records the source's hash" "$(shasum -a 256 "$rules" | awk '{print $1}')" \
  "$(jq -r '.rules.sourceSha256' "$m")"
block_now="$(sed -n "1,\$p" "$a" | shasum -a 256 | awk '{print $1}')"
check_eq "records the block's hash" "$block_now" "$(jq -r '.rules.blockSha256' "$m")"
label="$(jq -r '.rules.source' "$m")"
check_fails "the source label carries no absolute path" bash -c 'case "$1" in /*) exit 0;; *) exit 1;; esac' _ "$label"
check_fails "nor the fixture directory" grep -qF "$FIXTURE_DIR" "$m"
check_eq "no skills recorded by a rules-only run" "0" "$(jq '.skills | length' "$m")"
check "no skill directory created" test ! -d "$t/.claude"
check "no .gitignore rule added by a rules-only run" test ! -f "$t/.gitignore"

# --------------------------------------------------------- idempotent
cp "$a" "$a.before"
cp "$m" "$m.before"
run_lay "$out" --rules "$t"
check_eq "a second run exits 0" 0 "$?"
check "AGENTS.md is byte-identical" cmp -s "$a" "$a.before"
check "the manifest is byte-identical too" cmp -s "$m" "$m.before"
check "says it is unchanged" grep -q "unchanged" "$out"
rm -f "$a.before" "$m.before"

# ----------------------------------------- the source changes: update in place
# Content around the block, including a missing final newline, must survive.
printf 'my own notes above\n%s\nmy notes below\nlast line with no newline' "$(cat "$a")" > "$a.x"
mv "$a.x" "$a"
# That put text above the begin marker; a run must leave it exactly where it is.
printf '# Working rules\n\nAnswer first. Plain words. Now with a new line.\n' > "$rules"
run_lay "$out" --rules "$t"
check_eq "a changed source exits 0" 0 "$?"
check "says it updated the block" grep -q "updated the rules block" "$out"
check "the new text is in the block" grep -q "Now with a new line." "$a"
check_eq "the first line outside the block is untouched" "my own notes above" "$(sed -n 1p "$a")"
check "the text below the block is untouched" grep -qx "my notes below" "$a"
check_eq "the last line, which had no newline, is untouched" "last line with no newline" "$(tail -n 1 "$a")"
check "the file still ends with no trailing newline" test -n "$(tail -c 1 "$a")"
check_eq "still exactly one begin marker" "1" "$(grep -cxF "$BEGIN" "$a" | tr -d ' ')"
check_eq "the manifest's source hash moved" "$(shasum -a 256 "$rules" | awk '{print $1}')" \
  "$(jq -r '.rules.sourceSha256' "$m")"

# ------------------------------------------------ an existing AGENTS.md
t2="$(new_target)" || exit 1
printf '# Project notes\n\nKeep this.\n' > "$t2/AGENTS.md"
cp "$t2/AGENTS.md" "$t2/orig"
run_lay "$out" --rules "$t2"
check_eq "inserting into an existing file exits 0" 0 "$?"
check_eq "the block is at the very top" "$BEGIN" "$(sed -n 1p "$t2/AGENTS.md")"
check "says it added the block" grep -q "added the rules block at the top" "$out"
tail -n 3 "$t2/AGENTS.md" > "$t2/tail3"
check "the original content follows, byte for byte" cmp -s "$t2/tail3" <(tail -n 3 "$t2/orig")
rm -f "$t2/orig" "$t2/tail3"

# ---------------------------------------------------- hand edit: skip, exit 2
printf 'ONE HAND-WRITTEN LINE\n' > "$t2/edit"
{ head -n 3 "$t2/AGENTS.md"; cat "$t2/edit"; tail -n +4 "$t2/AGENTS.md"; } > "$t2/AGENTS.new"
mv "$t2/AGENTS.new" "$t2/AGENTS.md"
rm -f "$t2/edit"
printf '# Working rules\n\nA newer source that must not clobber the edit.\n' > "$rules"
recorded_block="$(jq -r '.rules.blockSha256' "$t2/.vendored-skills.json")"
cp "$t2/AGENTS.md" "$t2/AGENTS.expect"
run_lay "$out" --rules "$t2"
check_eq "an edited block exits 2" 2 "$?"
check "reports it was left alone" grep -q "edited since it was laid down" "$out"
check "tells how to take the shared version" grep -q "delete everything" "$out"
check "AGENTS.md is byte-identical to before the run" cmp -s "$t2/AGENTS.md" "$t2/AGENTS.expect"
check "the hand-written line survived" grep -qx "ONE HAND-WRITTEN LINE" "$t2/AGENTS.md"
check_eq "the manifest keeps the ORIGINAL block hash" "$recorded_block" \
  "$(jq -r '.rules.blockSha256' "$t2/.vendored-skills.json")"
run_lay "$out" --rules "$t2"
check_eq "and the warning persists on the next run" 2 "$?"

# The way back: delete the block, run again, and the shared version returns.
{ sed -n '/^<!-- shared-rules:end -->$/,$p' "$t2/AGENTS.md" | tail -n +2; } > "$t2/AGENTS.rest"
mv "$t2/AGENTS.rest" "$t2/AGENTS.md"
run_lay "$out" --rules "$t2"
check_eq "after the block is deleted, a run exits 0" 0 "$?"
check "the new source text is laid" grep -q "A newer source that must not clobber" "$t2/AGENTS.md"
check "the content below the old block is still there" grep -q "Keep this." "$t2/AGENTS.md"
check_fails "and the hand-written line went with the block" grep -q "ONE HAND-WRITTEN LINE" "$t2/AGENTS.md"

# A block the manifest has never heard of is not overwritten either.
t3="$(new_target)" || exit 1
printf '%s\nsomeone else wrote this\n%s\n' "$BEGIN" "$END" > "$t3/AGENTS.md"
run_lay "$out" --rules "$t3"
check_eq "an unrecorded block exits 2" 2 "$?"
check "says it is not recorded" grep -q "not recorded" "$out"
check "and the block is as it was" grep -qx "someone else wrote this" "$t3/AGENTS.md"

# Broken markers are an integrity refusal, written nowhere.
t4="$(new_target)" || exit 1
printf '%s\nhalf a block\n' "$BEGIN" > "$t4/AGENTS.md"
cp "$t4/AGENTS.md" "$t4/orig"
run_lay "$out" --rules "$t4"
check_eq "a lone begin marker exits 1" 1 "$?"
check "AGENTS.md was not changed" cmp -s "$t4/AGENTS.md" "$t4/orig"
check "no manifest written" test ! -f "$t4/.vendored-skills.json"

# -------------------------------------------------- dry run writes nothing
t5="$(new_target)" || exit 1
run_lay "$out" --rules --dry-run "$t5"
check_eq "dry run exits 0" 0 "$?"
check "says what it would do" grep -q "would create AGENTS.md" "$out"
check "wrote no AGENTS.md" test ! -f "$t5/AGENTS.md"
check "wrote no manifest" test ! -f "$t5/.vendored-skills.json"

# ------------------------------------- with skills in the same run
t6="$(new_target)" || exit 1
printf '# Working rules\n\nCombined run.\n' > "$rules"
run_lay "$out" --skills "executing-plans" --rules "$t6"
check_eq "skills and rules together exit 0" 0 "$?"
check "skills were laid" test -f "$t6/.claude/skills/executing-plans/SKILL.md"
check "rules were laid" grep -q "Combined run." "$t6/AGENTS.md"
check_eq "both are in the manifest" "executing-plans AGENTS.md" \
  "$(jq -r '(.skills | keys | join(",")) + " " + .rules.file' "$t6/.vendored-skills.json")"
# A rules skip must not stop the skills from being laid, and still exits 2.
{ head -n 3 "$t6/AGENTS.md"; echo EDIT; tail -n +4 "$t6/AGENTS.md"; } > "$t6/AGENTS.x" && mv "$t6/AGENTS.x" "$t6/AGENTS.md"
printf '%s\n' "# Working rules" "" "Newer." > "$rules"
run_lay "$out" --skills "executing-plans,brainstorming" --rules "$t6"
check_eq "a skipped rules block exits 2" 2 "$?"
check "but the new skill was laid" test -f "$t6/.claude/skills/brainstorming/SKILL.md"

# ------------------------------------------- a source that looks private
printf '# Working rules\n' > "$rules"
for bad in \
  'Config lives in /Users/someone/Documents/notes' \
  'token = abcdef0123456789abcdef' \
  'key ghp_abcdefghijklmnopqrstuvwxyz0123456789' \
  '-----BEGIN RSA PRIVATE KEY-----' \
  'mail me at someone@example.com' \
  'host 10.20.30.40 is the box' \
  'synced at /Volumes/Backup/data' \
  'C:\Users\someone\notes'
do
  printf '# Working rules\n%s\n' "$bad" > "$rules"
  tp="$(new_target)" || exit 1
  run_lay "$out" --rules "$tp"
  check_eq "refuses a source holding: $bad" 1 "$?"
  check "says it looks private" grep -q "looks like it holds private data" "$out"
  check "wrote no AGENTS.md" test ! -f "$tp/AGENTS.md"
  check "wrote no manifest" test ! -f "$tp/.vendored-skills.json"
  rm -rf "$tp"
done
# The scan reports a line number and a kind, never the text it matched.
printf '# Working rules\ntoken = abcdef0123456789abcdef\n' > "$rules"
tp="$(new_target)" || exit 1
run_lay "$out" --rules "$tp"
check_fails "the report does not echo the matching text" grep -q "abcdef0123456789abcdef" "$out"
check "it names the line" grep -q "line(s): 2" "$out"
rm -rf "$tp"

# A source that carries the markers would corrupt the block.
printf '# Working rules\n%s\n' "$BEGIN" > "$rules"
tp="$(new_target)" || exit 1
run_lay "$out" --rules "$tp"
check_eq "refuses a source containing the markers" 1 "$?"
rm -rf "$tp"

# Missing and empty sources.
export SHARED_RULES_FILE="$FIXTURE_DIR/nope.md"
tp="$(new_target)" || exit 1
run_lay "$out" --rules "$tp"
check_eq "refuses a missing rules source" 1 "$?"
: > "$rules"
export SHARED_RULES_FILE="$rules"
run_lay "$out" --rules "$tp"
check_eq "refuses an empty rules source" 1 "$?"
rm -rf "$tp"

rm -rf "$t" "$t2" "$t3" "$t4" "$t5" "$t6" "$out"
finish
