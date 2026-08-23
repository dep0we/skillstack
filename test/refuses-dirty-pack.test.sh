#!/bin/bash
# packCommit records the commit a pack version was cut from, and a gate
# resolves published hashes against a release built from that content. With
# uncommitted changes under packs/, that field names a commit whose content is
# not what was copied, and the disagreement surfaces much later, in somebody
# else's repository, as a hash mismatch with no visible cause.
#
# The mutation here is restored BY FILE COPY, never with git checkout: a
# checkout restores to the index and would discard any uncommitted work that
# happened to be in this tree.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
victim="$SKILLSTACK_ROOT/packs/superpowers/skills/executing-plans/SKILL.md"
backup="$(mktemp "${TMPDIR:-/tmp}/packbackup.XXXXXX")"

cp "$victim" "$backup" || exit 1
restore() { cp "$backup" "$victim"; rm -f "$backup"; }
trap restore EXIT

printf '\nDIRTY TREE MARKER\n' >> "$victim"

# Prove the mutation actually landed BEFORE reading any result from it. An
# edit that silently did not apply reads exactly like a passing guard.
if ! git -C "$SKILLSTACK_ROOT" status --porcelain -- packs/superpowers | grep -q .; then
  fail "the mutation did not land, so this test proved nothing"
  finish
fi
pass "mutation landed (packs/superpowers is dirty)"

run_lay "$out" --pack "$PACK" --skills "executing-plans" "$t"
check_eq "refuses to lay down from a dirty pack tree" 1 "$?"
check "names the uncommitted pack" grep -q "uncommitted changes" "$out"
check "wrote nothing" test ! -f "$t/.vendored-skills.json"

restore
trap - EXIT
check_eq "the pack tree is clean again" "" \
  "$(git -C "$SKILLSTACK_ROOT" status --porcelain -- packs/superpowers)"

# And with the tree clean, the same command has to succeed. Without this the
# test could pass because of anything at all.
run_lay "$out" --pack "$PACK" --skills "executing-plans" "$t"
check_eq "the same command succeeds once the tree is clean" 0 "$?"

rm -rf "$t"
finish
