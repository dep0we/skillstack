# Store a corrected snapshot, not a fork and not patches applied at install time

- **Status:** accepted
- **Date:** 2026-08-19
- **Supersedes:** none
- **Reversible:** yes, but not cheaply. Reversing means deciding again where
  the corrected content lives, and every project that took a pack in the
  meantime would need re-laying from whatever replaced it.

## Context

A pack has to get corrected skill content into a project. There are three
ways to hold that content, and the choice decides whether "review the
corrections once" is true or only aspirational.

1. **A snapshot.** The corrected files live here, committed, pinned to an
   upstream commit. The tool copies them into a project.
2. **A fork.** Fork upstream, keep the corrections as commits on the fork,
   and point projects at the fork.
3. **Patches at lay-down time.** Hold only the corrections, fetch upstream
   when a project installs, and apply the corrections then.

## Decision

Hold a **corrected snapshot**, committed here. Alongside it, keep the
corrections as a separate record: one entry per change, each with the reason
it exists.

Both, not either. The snapshot is what ships to a project. The record is how
a newer upstream snapshot gets re-corrected, and how anyone can tell a
deliberate correction from a stray edit.

The upstream copyright notice travels with the snapshot, because the licence
requires it to accompany any copy.

## Rationale

**Review-once only works if the reviewed artifact exists.** Option 3 produces
the bundle at install time, so what lands in a project is assembled from
whatever upstream says that day. No two installs are guaranteed identical and
nothing reviewed the result as a whole. That is the per-project surprise this
repository exists to end.

**Phrase-matching corrections break silently when upstream rewords; that is
not true of every install-time approach.** A pinned exact patch against a
pinned upstream commit stops the install when surrounding text no longer
matches, instead of quietly leaving the hole. This is measured for
phrase-matching, not predicted. `bin/soften-tdd.py` corrects by matching
phrases. Adversarial review found it caught three instances of the
instruction it targets and missed four more of the same instruction, in the
same file set, plus three files it never opens. The snapshot still wins
because the finished bundle is reviewed once here as a whole; install-time
assembly cannot offer that even when individual steps fail loud.

**A fork puts the corrections into someone else's history.** Every upstream
update becomes a merge to resolve, and the plain list of what was changed and
why stops existing as a first-class thing. That list is the artifact the
four-repo experience proved is needed: without it, a refresh cannot tell a
correction from an edit, and the tool's own hand-edit protection turns into a
trap that either freezes a project forever or silently restores every defect.

A snapshot also removes the network from install, so an upstream that
disappears, moves, or force-pushes cannot change what a project gets.

## Consequences

Roughly 175KB of third-party files live in this repository per pack, and they
are content this project did not write. They are reviewed once, here, and a
project that takes the pack reviews none of them.

Taking a newer upstream snapshot is deliberate work: re-cut the snapshot,
re-apply the corrections from the record, and confirm each one still lands.
The record is what makes that checkable rather than remembered. A correction
that no longer applies is a signal that upstream changed the text underneath
it, and it must be read rather than force-fitted.

The alternative that was rejected is not "no corrections". It is corrections
whose result nobody ever inspected as a whole.
