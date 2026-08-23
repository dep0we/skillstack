#!/bin/bash
# The manifest is an ordinary file in the project, so anyone can edit it. A
# path recorded for a skill this run did not name is carried forward rather
# than rebuilt, so it reaches the write unexamined unless something looks at
# it. This is the case the path rules exist for: paths this run constructed
# cannot be wrong, and testing only those would have proved nothing.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"

run_lay "$out" --pack "$PACK" --skills "executing-plans" "$t"
check_eq "first lay-down clean" 0 "$?"

doctor() {  # doctor <bad path>
  jq --arg bad "$1" \
    '.packs.superpowers.files += [{path:$bad, sha256:"0000000000000000000000000000000000000000000000000000000000000000"}]' \
    "$m" > "$m.x" && mv "$m.x" "$m"
}

# Each of these is carried forward, because the run below names a DIFFERENT
# skill, so executing-plans and everything recorded under it is untouched.
for bad in \
  "../../../etc/passwd" \
  "/etc/passwd" \
  ".claude/skills/executing-plans/../../../escape.md" \
  ".cursor/skills/executing-plans/SKILL.md" \
  "src/app.ts"
do
  cp "$m" "$m.orig"
  doctor "$bad"
  # Prove the doctoring landed before reading any result from it.
  if ! grep -Fq "$bad" "$m"; then
    fail "the doctored entry '$bad' did not land, so this case proved nothing"
    cp "$m.orig" "$m"; continue
  fi
  run_lay "$out" --pack "$PACK" --skills "brainstorming" "$t"
  rc=$?
  check_eq "refuses a carried-forward '$bad'" 1 "$rc"
  check "names the path it refused ($bad)" grep -Fq "$bad" "$out"
  cp "$m.orig" "$m"
done
rm -f "$m.orig"

# And the identical command has to succeed once the manifest is honest again,
# or every refusal above could have been caused by anything at all.
run_lay "$out" --pack "$PACK" --skills "brainstorming" "$t"
check_eq "the same command succeeds on an undoctored manifest" 2 "$?"
check_fails "and refuses nothing" grep -q "refusing this manifest" "$out"

rm -rf "$t" "$out"
finish
