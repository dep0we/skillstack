#!/usr/bin/env python3
"""Remove the instructions that tell an agent to delete code.

The vendored test-first skill tells an agent that code written before its test
must be deleted, with no exceptions, and lists "deleting hours of work is
wasteful" as an excuse to reject. This removes those instructions and keeps the
test-first discipline.

Run from the root of a project that has had the skill stack vendored into it.
It finds EVERY copy of the skill in the repo rather than assuming how many
folders the vendoring wrote to, so adding a fourth skill directory cannot
silently leave one copy dangerous.

  soften-tdd.py            apply, then verify
  soften-tdd.py --verify   verify only, change nothing

Exits non-zero on every failure, including finding no copies at all. A check
that cannot find its target must never look like a clean result.
"""

# ---------------------------------------------------------------- SUPERSEDED
#
# Kept as a readable reference for why correcting at lay-down time was
# abandoned, and it must not be run against a project again.
#
# Its scope is proven too narrow to trust. It opens every path matching
# */skills/test-driven-development/SKILL.md and replaces three exact phrases in
# each copy. Adversarial review of a real import found the same
# delete-the-code instruction live and untouched in three files this script
# never opens, and four more instances inside each file it does open, in
# wording its three-phrase list does not match. A correction that only proves
# itself against the exact file and wording it was written for, with no signal
# when upstream rewords, is not a mechanism to carry forward.
#
# Corrections are applied once now, when a pack version is cut, and the pack
# ships already corrected. Nothing corrects at lay-down time.
# There is deliberately no environment override. A hook that lets a test skip a
# guard becomes the only way through once the guarded path rots, and then every
# test uses it and the guard has never run.
import sys as _sys

_sys.stderr.write(
    "error: soften-tdd.py is superseded and refuses to run.\n\n"
    "It matched three exact phrases in one file name, and adversarial review\n"
    "found the same instruction live in files it never opens. Corrections are\n"
    "applied once, when a pack version is cut, and packs/ ships corrected.\n\n"
    "Use instead:\n"
    "  bin/lay-pack.sh --pack <name> --skills a,b,c <project>\n"
)
raise SystemExit(1)

import sys
from pathlib import Path

SKILL_REL = "skills/test-driven-development/SKILL.md"
MARKER = "Never delete his code"

# Any of these surviving means the dangerous instruction is still present.
FORBIDDEN = [
    "Delete it. Start over.",
    "Delete means delete",
    "Delete code. Start over with TDD.",
]

EDITS = [
(
'''Write code before the test? Delete it. Start over.

**No exceptions:**
- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Don't look at it
- Delete means delete

Implement fresh from tests. Period.''',
'''Write code before the test? Stop and tell the maintainer. He decides
whether to keep it and add tests, or start over. Never delete his code
yourself, and never delete uncommitted work for any reason.'''
),
(
'**All of these mean: Delete code. Start over with TDD.**',
'**All of these mean: stop and ask the maintainer how to proceed. Do not delete code.**'
),
(
'''| "Keep as reference, write tests first" | You'll adapt it. That's testing after. Delete means delete. |''',
'''| "Keep as reference, write tests first" | Adapting existing code is testing after. Say so out loud and let the maintainer decide. |'''
),
]

verify_only = "--verify" in sys.argv[1:]
root = Path.cwd()

# Find every copy, wherever the vendoring put it. Skip .git.
found = sorted(
    p for p in root.glob("*/" + SKILL_REL)
    if ".git" not in p.parts
)

if not found:
    sys.exit(
        "FAILED: no copy of the test-first skill found under " + str(root) + ".\n"
        "  Looked for: <any-dir>/" + SKILL_REL + "\n"
        "  Are you in the project root, and has the stack been vendored yet?\n"
        "  If upstream renamed the skill folder, this script needs updating."
    )

failures = []

for path in found:
    rel = path.relative_to(root)
    text = path.read_text()

    if MARKER in text:
        print("ALREADY:  " + str(rel))
    elif verify_only:
        failures.append(str(rel) + " has not been softened")
        continue
    else:
        for old, new in EDITS:
            if old not in text:
                sys.exit(
                    "FAILED: expected text not found in " + str(rel) + ".\n"
                    "  Upstream wording changed. Nothing was written to any file.\n"
                    "  This script must be updated before vendoring is safe."
                )
            text = text.replace(old, new)
        path.write_text(text)
        print("APPLIED:  " + str(rel))

    # Verify by re-reading from disk, not from the buffer above.
    check = path.read_text()
    if MARKER not in check:
        failures.append(str(rel) + " is missing the expected replacement text")
    for bad in FORBIDDEN:
        if bad in check:
            failures.append(str(rel) + " still contains: " + bad)

if failures:
    print("")
    for f in failures:
        print("FAILED:   " + f)
    sys.exit(1)

print("")
print("VERIFIED: " + str(len(found)) + " cop" + ("y" if len(found) == 1 else "ies") +
      " carry no instruction to delete code.")
