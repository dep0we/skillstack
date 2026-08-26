#!/bin/bash
# Laying a pack down has to leave the target ignoring the directory those
# skills write live session state into. The brainstorming companion server
# writes a session key in cleartext under .superpowers/ the first time it runs,
# and before this the tool copied the skill in and said nothing, so the rule
# existed only if somebody remembered to add it. Four repositories added it by
# hand after the fact.
#
# Everything here asks git whether a path is ignored rather than grepping
# .gitignore for the rule text. Those are different questions: a rule can be in
# the file and undone by a later negation, and a path can be covered by a rule
# that is not in this file at all.
source "$(dirname "$0")/helpers.sh"

# ---------------------------------------------------------------- the pin
#
# Pinned by name, never by count, and it has to equal what the specification
# states. A rule the tool writes and the document does not describe is a rule
# nobody reviewing a project's .gitignore can account for.
decl="$(grep -E '^IGNORE_RULE=' "$LAY")"
check_eq "the tool writes exactly this rule" 'IGNORE_RULE=".superpowers/"' "$decl"
check_eq "and names it in exactly one place" "1" "$(grep -cE '^IGNORE_RULE=' "$LAY")"

spec="$SKILLSTACK_ROOT/docs/SPEC.md"
# shellcheck disable=SC2016  # the backticks are literal markdown, not a subshell
check "the spec states the rule" grep -qF '`.superpowers/`' "$spec"
check "the spec says the tool appends it" \
  grep -qF 'What the tool writes into a project' "$spec"

# ignored_by_rule <repo> <path> -- 0 when git ignores it, 1 when it does not.
# --no-index so this reports on the rules rather than on the index.
ignored_by_rule() { git -C "$1" check-ignore --no-index -q -- "$2"; }

# -------------------------------------------------- positive: a fresh target

t="$(new_target)" || exit 1
out="$(new_out)"

# The instrument has to be able to say "no" here, or every later rc=0 is
# meaningless. This is the state the tool is about to change.
check_fails "before the run, git does not ignore the token path" \
  ignored_by_rule "$t" ".superpowers/brainstorm/.last-token"

run_lay "$out" --pack "$PACK" --skills "brainstorming,subagent-driven-development" "$t"
check_eq "a clean lay-down still exits 0" 0 "$?"
check "reports what it did about the rule" grep -qE '^ignored:   appended' "$out"
check "created a .gitignore" test -f "$t/.gitignore"

check "the brainstorm token path is ignored" \
  ignored_by_rule "$t" ".superpowers/brainstorm/.last-token"
check "the server-info holding the same key in a URL is ignored" \
  ignored_by_rule "$t" ".superpowers/brainstorm/1234-1706000000/state/server-info"
check "the server log is ignored" \
  ignored_by_rule "$t" ".superpowers/brainstorm/1234-1706000000/server.log"
check "the sdd workspace is ignored" \
  ignored_by_rule "$t" ".superpowers/sdd/some-plan/task-1-brief.md"

# The rule that matched has to be the one this tool wrote, in this file. A
# path ignored for some other reason would pass every check above.
v="$(git -C "$t" check-ignore -v --no-index -- ".superpowers/brainstorm/.last-token")"
check "the matching rule is named, and it is ours" \
  grep -qF '.gitignore' <<< "$v"
check "and the rule text is the pinned one" grep -qF '.superpowers/' <<< "$v"

# ------------------------------------------------ negative: not over-broad

check_fails "a directory merely named superpowers is untouched" \
  ignored_by_rule "$t" "superpowers/notes.md"
check_fails "a file whose name starts with .superpowers is untouched" \
  ignored_by_rule "$t" "docs/.superpowers-notes.md"
check_fails "an ordinary source file is untouched" \
  ignored_by_rule "$t" "src/main.js"
check_fails "the skills the tool just laid down are untouched" \
  ignored_by_rule "$t" ".claude/skills/brainstorming/SKILL.md"

# ----------------------------------------------------------- idempotence

before="$(shasum -a 256 "$t/.gitignore" | awk '{print $1}')"
run_lay "$out" --pack "$PACK" --skills "brainstorming,subagent-driven-development" "$t"
check_eq "a second run exits 0" 0 "$?"
after="$(shasum -a 256 "$t/.gitignore" | awk '{print $1}')"
check_eq "a second run leaves .gitignore byte-identical" "$before" "$after"
check_eq "the rule appears exactly once" "1" \
  "$(grep -cxF '.superpowers/' "$t/.gitignore" | tr -d ' ')"
check "the second run says the rule was already covered" \
  grep -qE '^ignored:   .* already covered' "$out"

# --------------------------------------------- regression: the original bug
#
# A session writes a key, someone stages everything, and the key is in the
# commit. That is what happened, measured, in a target with no rule.

mkdir -p "$t/.superpowers/brainstorm/1234-1706000000/state" "$t/.superpowers/sdd/plan"
tok="$(openssl rand -hex 32)"
printf '%s' "$tok" > "$t/.superpowers/brainstorm/.last-token"
printf '{"url":"http://127.0.0.1:8321/?key=%s"}\n' "$tok" \
  > "$t/.superpowers/brainstorm/1234-1706000000/state/server-info"
printf 'ledger\n' > "$t/.superpowers/sdd/plan/progress.md"

git -C "$t" add -A
staged="$(git -C "$t" diff --cached --name-only | grep -c '^\.superpowers/' | tr -d ' ')"
check_eq "git add -A after a session stages no session state" "0" "$staged"
leaks="$(git -C "$t" diff --cached | grep -c "$tok" | tr -d ' ')"
check_eq "and the session key reaches no staged content" "0" "$leaks"
git -C "$t" reset --quiet

# ------------------------------------------- a target that already has one

t2="$(new_target)" || exit 1
printf '# mine\nnode_modules/\n.superpowers/\n' > "$t2/.gitignore"
git -C "$t2" add -A >/dev/null 2>&1
git -C "$t2" commit --quiet -m gitignore
pre="$(shasum -a 256 "$t2/.gitignore" | awk '{print $1}')"

run_lay "$out" --pack "$PACK" --skills "brainstorming" "$t2"
check_eq "exits 0 against a target that already had the rule" 0 "$?"
check_eq "and its .gitignore is byte-identical" "$pre" \
  "$(shasum -a 256 "$t2/.gitignore" | awk '{print $1}')"
check "the token path is ignored there too" \
  ignored_by_rule "$t2" ".superpowers/brainstorm/.last-token"

# ------------------------------------ an existing file is appended to, never
# rewritten, and a missing final newline does not swallow a line

t3="$(new_target)" || exit 1
printf '# mine\nnode_modules/\ndist/' > "$t3/.gitignore"   # no trailing newline
git -C "$t3" add -A >/dev/null 2>&1
git -C "$t3" commit --quiet -m gitignore

run_lay "$out" --pack "$PACK" --skills "brainstorming" "$t3"
check_eq "exits 0 against a file with no final newline" 0 "$?"
check "the original first line survives" grep -qxF '# mine' "$t3/.gitignore"
check "the original last line survives whole" grep -qxF 'dist/' "$t3/.gitignore"
check "the rule is on a line of its own" grep -qxF '.superpowers/' "$t3/.gitignore"
check "and their own rules still work" ignored_by_rule "$t3" "dist/bundle.js"

# ----------------------------- session state already committed is not "fixed"
#
# An ignore rule does not untrack a tracked file. Reporting a protected tree
# over the top of a committed credential is the same false clean result this
# whole change exists to remove.

t4="$(new_target)" || exit 1
mkdir -p "$t4/.superpowers/brainstorm"
openssl rand -hex 32 > "$t4/.superpowers/brainstorm/.last-token"
git -C "$t4" add -A >/dev/null 2>&1
git -C "$t4" commit --quiet -m "committed a session key"

run_lay "$out" --pack "$PACK" --skills "brainstorming" "$t4"
check_eq "a run that finds committed session state exits 2" 2 "$?"
check "and says it is already committed" grep -q "ALREADY COMMITTED" "$out"
check "and names the file" grep -qF ".superpowers/brainstorm/.last-token" "$out"
check "the rule is still added for what is not yet tracked" \
  ignored_by_rule "$t4" ".superpowers/brainstorm/1234/state/server-info"

# --------------------------------------------------- a dry run writes nothing

t5="$(new_target)" || exit 1
run_lay "$out" --pack "$PACK" --skills "brainstorming" --dry-run "$t5"
check_eq "dry run exits 0" 0 "$?"
check "wrote no .gitignore" test ! -f "$t5/.gitignore"
check "and says what it would have done" grep -qE '^\[dry-run\] ignored:   would append' "$out"
check_fails "and left the target still unprotected" \
  ignored_by_rule "$t5" ".superpowers/brainstorm/.last-token"

rm -rf "$t" "$t2" "$t3" "$t4" "$t5" "$out"
finish
