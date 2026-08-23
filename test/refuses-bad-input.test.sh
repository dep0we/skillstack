#!/bin/bash
# Every value that becomes a path segment or a release tag is validated before
# it is interpolated anywhere. A skill name reaches three path positions.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"

run_lay "$out" --pack "$PACK" --skills "no-such-skill" "$t"
check_eq "unknown skill exits 1" 1 "$?"
check "names the skill it could not find" grep -q "no-such-skill" "$out"
check "wrote nothing" test ! -f "$t/.vendored-skills.json"

for bad in "../escape" "a/b" ".." "."; do
  run_lay "$out" --pack "$PACK" --skills "$bad" "$t"
  check_eq "refuses skill name '$bad'" 1 "$?"
done
check "no directory escaped the target" test ! -d "$t/../.claude"

run_lay "$out" --pack "nope" --skills "brainstorming" "$t"
check_eq "unknown pack exits 1" 1 "$?"

# The naming grammar exists so two packs cannot produce one release tag.
run_lay "$out" --pack "foo-v1" --skills "brainstorming" "$t"
check_eq "refuses a pack name containing -v followed by a digit" 1 "$?"
check "names the grammar" grep -qi "naming grammar" "$out"

run_lay "$out" --pack "Superpowers" --skills "brainstorming" "$t"
check_eq "refuses an uppercase pack name" 1 "$?"

rm -rf "$t"
finish
