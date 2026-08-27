#!/bin/bash
# The destination directories are pinned BY NAME, never by count. Every
# increment to a list like this had a good reason at the time, and a number
# cannot say which decisions it is made of.
#
# This list must equal the allowed-location prefixes in docs/SPEC.md section 4.
# They are not independent: a path the gate does not allow is not skipped, it
# rejects the whole manifest, so a directory added here and not there turns
# exclusion off silently for every project.
source "$(dirname "$0")/helpers.sh"

decl="$(grep -E '^ALLOWED_DEST_DIRS=' "$LAY")"
check_eq "the tool allows exactly these two directories" \
  'ALLOWED_DEST_DIRS=(".claude/skills" ".agents/skills")' "$decl"

check_eq "and names allowed locations in exactly one place" "1" \
  "$(grep -cE '^ALLOWED_DEST_DIRS=' "$LAY")"

check "the tool supports the agents-only layout" \
  grep -q 'agents) DEST_DIRS=(".agents/skills")' "$LAY"

# The specification's allowed locations have to agree, or the manifest this
# tool writes is one a gate throws away whole.
spec="$SKILLSTACK_ROOT/docs/SPEC.md"
check "the spec allows .claude/skills/" grep -q '`.claude/skills/`' "$spec"
check "the spec allows .agents/skills/" grep -q '`.agents/skills/`' "$spec"
check "the spec still excludes .cursor/skills/" \
  grep -q '`.cursor/skills/` is not an allowed location' "$spec"

# .cursor/skills/ must not appear as a destination anywhere in the tool. Local
# Cursor reads it, so this is a live possibility rather than a hypothetical,
# and it is held out pending the cloud measurement.
check_fails "the tool never writes to .cursor/skills" grep -q '\.cursor/skills' "$LAY"

finish
