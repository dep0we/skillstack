#!/bin/bash
# Cursor Cloud and Codex share .agents/skills/. A project that deliberately
# does not run local Claude Code must be able to lay one copy, not two.
source "$(dirname "$0")/helpers.sh"

t="$(new_target)" || exit 1
out="$(new_out)"
m="$t/.vendored-skills.json"

run_lay "$out" --pack "$PACK" --skills "test-driven-development,requesting-code-review" --targets agents "$t"
check_eq "agents-only layout exits 0" 0 "$?"
check "wrote the shared agent skill" test -f "$t/.agents/skills/test-driven-development/SKILL.md"
check "did not write a Claude Code copy" test ! -e "$t/.claude/skills/test-driven-development/SKILL.md"
check "did not write a Cursor copy" test ! -e "$t/.cursor/skills/test-driven-development/SKILL.md"

dirs="$(jq -r '.packs.superpowers.files[].path' "$m" | cut -d/ -f1 | sort -u | tr '\n' ' ')"
check_eq "manifest records only the shared directory" ".agents " "$dirs"
check "the session-state directory is ignored" git -C "$t" check-ignore -q .superpowers/brainstorm/.last-token

two_copy="$(new_target)" || exit 1
run_lay "$out" --pack "$PACK" --skills "test-driven-development" "$two_copy"
check_eq "two-directory layout starts clean" 0 "$?"
before="$(shasum -a 256 "$two_copy/.vendored-skills.json" | awk '{print $1}')"
run_lay "$out" --pack "$PACK" --skills "test-driven-development" --targets agents "$two_copy"
check_eq "refuses an in-place layout switch" 1 "$?"
check "explains why the layout switch is unsafe" grep -q "unmanaged Claude Code copy" "$out"
after="$(shasum -a 256 "$two_copy/.vendored-skills.json" | awk '{print $1}')"
check_eq "refusal leaves the old manifest unchanged" "$before" "$after"

rm -rf "$t"
rm -rf "$two_copy"
finish
