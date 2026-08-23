# The gate asks skillstack for shipped hashes; it does not trust the project's copy

**Date:** 2026-08-20
**Ruled by:** the maintainer, on Linear DAR-154
**Status:** settled. Section 4 of `docs/SPEC.md` is written as a contract on
this basis. Reopening needs a reason, not a fresh opinion.

## What was decided

The merge gate does **not** trust the hash list inside the project under
review. It asks `skillstack` what the real shipped hashes were for the
recorded pack version, and compares against that. A pull request can edit the
manifest in its own repository. It cannot edit what `skillstack` published.

Two constraints came with the ruling, both load-bearing:

1. **When the gate cannot reach `skillstack`, it must refuse to exclude
   anything, loudly, and say why.** A lookup that failed and a lookup that
   found no differences must never produce the same outcome.
2. **The pack version and pack identity are themselves read from the project's
   manifest**, so a change can point at a different pack version whose hashes
   suit it. Whatever is built has to account for that, or the lookup just
   moves the forgery one field over.

Also settled, and not to be reopened: **a human reading the manifest diff is
not the control.** It was considered and rejected as the primary mechanism,
because a page of hashes is exactly the check that quietly stops happening,
and nothing reports when it does.

## Why it was needed

Adversarial review found that exclusion could not be trusted the way the
original design assumed. `shippedSha256`, the `files` list and the `skills`
list all live in the project repository, so the same change that edits a skill
file can edit all three to agree with it. A reader holding only the manifest
and the working tree has no copy of what `skillstack` published and cannot
check them.

The obvious comfort does not rescue it: yes, the manifest change appears in
the pull request diff, but the file that needed a hostile read is the skill
file, and this mechanism is what took it out of scope. A changed number in a
JSON file is not that read.

## What the ruling cost, and what was accepted

Option 1 (fetch from `skillstack`) costs a network dependency in the gate and
a decision about what happens when it cannot reach the source. Option 2 (a
human treats the manifest diff as the real review) costs nothing mechanically
and puts the weight on a check that degrades quietly. Option 1 was taken, with
the unreachable case specified rather than left to the implementation.

## What was worked out afterwards, implementing this ruling

These are consequences of the ruling, not part of it, and they are recorded
here because section 4 depends on them:

- **The lookup key is the pack version, resolved to an immutable annotated
  tag.** It is not the recorded commit. This repository's history was rebuilt
  into a single root commit on 2026-08-19 to strip private paths and names
  before publishing, which orphaned every commit sha existing clones held. A
  recorded commit sha is therefore not a durable reference: an unauthenticated
  fetch of an orphaned sha returns HTTP 404, the same status an unreachable
  repository returns. Measured, not assumed.
- **Scope comes from the target branch's manifest, not the pull request's.**
  Comparing the two is not enough on its own. A change can leave the version
  fields untouched and simply add paths to the `files` array, and those paths
  would then be excluded. The array is as writable as the fields around it.
- **The general rule under all three of the above:** anything the change under
  review can write is evidence, never authority. This design has been defeated
  three times, each time by a different field that had been read as
  authoritative. Apply the rule to every new field before adding one.

## Not covered by this ruling

Creating the tag protection rule this design requires is a repository setting
and remains the maintainer's call. Until it exists, and until the first
release tag is cut, every project resolves `release not found` and nothing is
excluded anywhere.
