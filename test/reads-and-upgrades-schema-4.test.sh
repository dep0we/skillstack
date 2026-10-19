#!/bin/bash
# Four real projects hold a schema 4 manifest written by the retired pack tool.
# This tool has to read it, list it, keep detecting hand edits through it, and
# upgrade it to schema 5 on the next write without losing a recorded hash.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"

# Build a schema 4 manifest the way the old tool would have left it: lay two
# skills, then rewrite the manifest into the old shape (a pack name above the
# skills, one pack-level version and commit, a flat files list). A third skill
# the source does not list stands in for pack skills that were never carried
# into dep0we/skills.
run_lay "$out" --skills "executing-plans,brainstorming" "$t"
mkdir -p "$t/.claude/skills/old-only" "$t/.agents/skills/old-only"
printf 'old\n' > "$t/.claude/skills/old-only/SKILL.md"
printf 'old\n' > "$t/.agents/skills/old-only/SKILL.md"
oh="$(shasum -a 256 "$t/.claude/skills/old-only/SKILL.md" | awk '{print $1}')"

jq --arg oh "$oh" '
  {
    schemaVersion: 4,
    packs: {
      superpowers: {
        source: "skillstack",
        packVersion: "0.1.0",
        packCommit: "1111111111111111111111111111111111111111",
        upstream: {repo: "https://github.com/obra/superpowers", subdir: "skills", commit: "2222222222222222222222222222222222222222"},
        installedAt: "2026-08-25T00:00:00Z",
        skills: ((.skills | keys) + ["old-only"]),
        files: (([.skills[].files[]] + [
          {path: ".claude/skills/old-only/SKILL.md", sha256: $oh},
          {path: ".agents/skills/old-only/SKILL.md", sha256: $oh}
        ]) | sort_by(.path))
      }
    }
  }' "$m" > "$m.v4" && mv "$m.v4" "$m"
check_eq "the fixture manifest is schema 4" "4" "$(jq -r '.schemaVersion' "$m")"
check "and has no skills section" test "$(jq 'has("skills")' "$m")" = "false"
cp "$m" "$m.v4copy"
before_hash="$(jq -r '.packs.superpowers.files[] | select(.path==".claude/skills/executing-plans/SKILL.md") | .sha256' "$m")"

# ---------------------------------------------------------------- --list
run_lay "$out" --list "$t"
check_eq "--list reads a schema 4 manifest" 0 "$?"
check "says it is schema 4" grep -q "schema 4" "$out"
check "says the next write upgrades it" grep -q "upgrades it to schema 5" "$out"
check "names a skill from it" grep -q "skill: executing-plans" "$out"
check "shows the retired pack it came from" grep -q "retired pack superpowers 0.1.0" "$out"
check "counts the files" grep -q "files:     2" "$out"
check "--list wrote nothing" cmp -s "$m" "$m.v4copy"

# ----------------------------------------------------- dry run keeps schema 4
run_lay "$out" --skills "executing-plans,brainstorming,old-only" --dry-run "$t"
check "a dry run leaves a schema 4 manifest untouched" cmp -s "$m" "$m.v4copy"

# ------------------------- a write run never rewrites schema 4 on its own
#
# The project's own checks read the old format. A silent rewrite makes them see
# no files. Every write path refuses, writes nothing, and names the way through.
snapshot() { find "$t" -path "$t/.git" -prune -o -type f -print | sort | xargs shasum -a 256 | shasum -a 256 | awk '{print $1}'; }
rules_src="$FIXTURE_DIR/rules.md"
printf '# Rules\n\nPlain.\n' > "$rules_src"
before_snap="$(snapshot)"
for args in \
  "--skills executing-plans" \
  "--skills executing-plans,brainstorming --targets both" \
  "--skills writing-plans --rules" \
  "--rules" \
  "--forget executing-plans"
do
  # shellcheck disable=SC2086  # the word splitting is the point
  SHARED_RULES_FILE="$rules_src" run_lay "$out" $args "$t"
  check_eq "'$args' over schema 4 exits 1" 1 "$?"
  check "'$args' says the repo was laid by the old tool" grep -q "laid by the old pack tool" "$out"
  check "'$args' names --upgrade-manifest" grep -q -- "--upgrade-manifest" "$out"
  check_eq "'$args' wrote nothing at all" "$before_snap" "$(snapshot)"
done
check "the manifest is still schema 4, byte for byte" cmp -s "$m" "$m.v4copy"
check "no AGENTS.md appeared" test ! -f "$t/AGENTS.md"
SHARED_RULES_FILE="$rules_src" run_lay "$out" --rules --upgrade-manifest "$t"
check_eq "--rules with --upgrade-manifest goes through" 0 "$?"
check_eq "and writes schema 5" "5" "$(jq -r '.schemaVersion' "$m")"
rm -f "$t/AGENTS.md"
cp "$m.v4copy" "$m"

# ------------------------------------------- a hand edit is still caught
printf '\nEDITED UNDER THE OLD TOOL\n' >> "$t/.claude/skills/executing-plans/SKILL.md"
run_lay "$out" --upgrade-manifest --skills "executing-plans,brainstorming" "$t"
check_eq "an edit made under schema 4 still exits 2" 2 "$?"
check "and is reported" grep -q "edited since it was laid down" "$out"
check "the edit survived" grep -q "EDITED UNDER THE OLD TOOL" "$t/.claude/skills/executing-plans/SKILL.md"

# --------------------------------------------------- the upgrade on write
check_eq "the write upgraded the manifest to schema 5" "5" "$(jq -r '.schemaVersion' "$m")"
check_eq "no pack section is left" "false" "$(jq 'has("packs")' "$m")"
kept="$(jq -r '.skills["executing-plans"].files[] | select(.path==".claude/skills/executing-plans/SKILL.md") | .sha256' "$m")"
check_eq "the recorded hash of the edited file was carried over, not replaced" "$before_hash" "$kept"
run_lay "$out" --skills "executing-plans" "$t"
check "so the edit is still flagged on the next run" grep -q "edited since it was laid down" "$out"

# A skill the source does not list stays tracked, with its hashes, and is
# reported as recorded-but-not-named, never silently dropped.
check_eq "the skill the source does not list is still recorded" "true" \
  "$(jq '.skills | has("old-only")' "$m")"
check_eq "with both of its files" "2" "$(jq '.skills["old-only"].files | length' "$m")"
check_eq "and its recorded hash" "$oh" "$(jq -r '.skills["old-only"].files[0].sha256' "$m")"
check_eq "and where it came from" "superpowers" "$(jq -r '.skills["old-only"].legacy.pack' "$m")"
check "the run reported it as not named" grep -q "NOT named in --skills" "$out"

# Clear the edit, name everything, and a clean run lays the pinned bytes.
run_lay "$out" --forget executing-plans "$t"
check_eq "--forget works on the upgraded manifest" 0 "$?"
run_lay "$out" --skills "executing-plans,brainstorming" "$t"
check_eq "after --forget the run lays the pinned version" 2 "$?"
check "the pinned text is back" grep -q "COMMIT ONE" "$t/.claude/skills/executing-plans/SKILL.md"
check_fails "and the edit is gone, as asked" grep -q "EDITED UNDER THE OLD TOOL" "$t/.claude/skills/executing-plans/SKILL.md"
check_eq "a relaid skill carries its source folder" "skills/executing-plans" \
  "$(jq -r '.skills["executing-plans"].folder' "$m")"
check_eq "and no legacy marker" "false" "$(jq '.skills["executing-plans"] | has("legacy")' "$m")"

# ------------------------------------- --forget upgrades a schema 4 file too
cp "$m.v4copy" "$m"
run_lay "$out" --upgrade-manifest --forget brainstorming "$t"
check_eq "--forget on a schema 4 manifest exits 0" 0 "$?"
check_eq "and writes schema 5" "5" "$(jq -r '.schemaVersion' "$m")"

# ----------------------------------------- a doctored schema 4 path is refused
cp "$m.v4copy" "$m"
jq '.packs.superpowers.files += [{path:"../../etc/passwd", sha256:"0000000000000000000000000000000000000000000000000000000000000000"}]' \
  "$m" > "$m.x" && mv "$m.x" "$m"
run_lay "$out" --list "$t"
check_eq "--list refuses a doctored schema 4 manifest" 1 "$?"
check "names the path" grep -Fq "../../etc/passwd" "$out"
run_lay "$out" --upgrade-manifest --skills "executing-plans" "$t"
check_eq "a lay-down refuses it too" 1 "$?"

# Schema 1 and unknown versions are still refused outright.
printf '{"vendored":{}}\n' > "$m"
run_lay "$out" --skills "executing-plans" "$t"
check_eq "an unversioned manifest is refused" 1 "$?"
printf '{"schemaVersion":9,"skills":{}}\n' > "$m"
run_lay "$out" --list "$t"
check_eq "a schema this tool does not know is refused" 1 "$?"

rm -f "$m.v4copy"
rm -rf "$t" "$out"
finish
