#!/bin/bash
# Both carried-forward scripts are kept as readable references and must never
# run against a project again. vendor-skills.sh is the dangerous one: it clones
# upstream's latest default branch and writes a schema 1 manifest over a schema
# 4 one, destroying the record a gate resolves published hashes against.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"

bash "$SKILLSTACK_ROOT/bin/vendor-skills.sh" "$t" > "$out" 2>&1
check_eq "vendor-skills.sh exits 1" 1 "$?"
check "says it is superseded" grep -q "superseded and refuses to run" "$out"
check "names the replacement" grep -q "lay-pack.sh" "$out"
check "it did not clone anything" test ! -d "$t/.git/vendor-clone"
check "it wrote no manifest" test ! -f "$t/.vendored-skills.json"

# --list and --dry-run are the two arguments most likely to be tried by
# someone who believes they are being careful. Neither may get past it.
for args in "--list" "--dry-run"; do
  bash "$SKILLSTACK_ROOT/bin/vendor-skills.sh" $args "$t" > "$out" 2>&1
  check_eq "vendor-skills.sh $args also refuses" 1 "$?"
  check "and still says superseded ($args)" grep -q "superseded" "$out"
done

python3 "$SKILLSTACK_ROOT/bin/soften-tdd.py" > "$out" 2>&1
check_eq "soften-tdd.py exits 1" 1 "$?"
check "says it is superseded" grep -q "superseded and refuses to run" "$out"
python3 "$SKILLSTACK_ROOT/bin/soften-tdd.py" --verify > "$out" 2>&1
check_eq "soften-tdd.py --verify also refuses" 1 "$?"

# The refusal must be unconditional. An environment override added "so tests
# can still exercise the old path" becomes the only route through once that
# path rots, and then every test takes it and the guard has never run.
check_fails "no environment override exists in either script" \
  grep -rq "ALLOW_SUPERSEDED" "$SKILLSTACK_ROOT/bin"

rm -rf "$t" "$out"
finish
