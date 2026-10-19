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
2. **A danger to be closed, not a design to be implemented.** Stated as the
   hazard first, because the original phrasing named the dangerous design in
   the voice of a decision and a builder could implement it as written:

   > if the pack version and pack identity are read from the project's own
   > manifest, a change can point at a different pack version whose hashes
   > suit it, and the lookup has just moved the forgery one field over.

   **The closure, which is part of this ruling and not a later refinement:
   identity is taken from the manifest already merged into the target branch,
   never from the change under review, and the publishing repository is a
   constant compiled into the gate, never read from any manifest.** Both
   belong here rather than only in the specification, because a builder who
   reads a ruling and stops at the end of its "what was decided" section must
   not be able to build the hole it exists to prevent.

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

- **The lookup key is the pack name together with the pack version**,
  resolved to an immutable annotated tag named `<pack>-v<version>`. Not the
  version alone: two packs at `0.1.0` would collapse onto one release. It is not the recorded commit. This repository's history was rebuilt
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
  four times, each time by a different input that had been read as
  authoritative: the per-file hash, then `shippedSha256` beside it, then the
  `files` array, then the publishing repository itself, which the document had
  never named. Apply the rule to every new input before adding one, and keep
  the specification's input inventory exhaustive, because a principle does not
  enumerate and each of the four was an input nobody had written down.

## Not covered by this ruling

Creating the tag protection rule this design requires is a repository setting
and remains the maintainer's call. Until it exists, and until the first
release tag is cut, every project resolves `release not found` and nothing is
excluded anywhere.

## Update, 2026-10-19: the source of skills changed

`bin/lay-pack.sh` no longer lays from `packs/`. It lays from `dep0we/skills` at
a pinned commit and writes schema 5 manifests. See
`2026-10-19-skills-come-from-one-pinned-source.md`. This section records what
that does to the ruling above. The ruling itself is not reopened.

**What still holds, unchanged:** the gate does not trust the hash list in the
project under review. Anything the change under review can write is evidence,
never authority. Identity comes from the manifest already merged into the target
branch. The publishing repository is a constant compiled into the gate. An
unreachable source must never read as "no differences".

**What breaks:** the schema 4 gate cannot validate a schema 5 manifest.

- It implements schema 4 only, so a schema 5 baseline reports `unsupported
  schema — unrecognised` and nothing is excluded. This fails safe and loudly, and
  it is the outcome the contract already names for "needs the gate upgraded".
- Even upgraded to read schema 5's shape, the old lookup finds nothing. It
  derives the tag `<pack>-v<version>` in `dep0we/skillstack` and fetches
  `packs/<pack>/files.json`. Schema 5 has no pack name or pack version, and no
  new release is cut in this repository for skills that now ship from
  `dep0we/skills`.
- The four projects holding a schema 4 manifest keep validating, because
  `superpowers-v0.1.0` and `packs/superpowers/files.json` stay in this
  repository. The first time one of them is re-run with the new tool, its
  manifest becomes schema 5 and its exclusion stops until the gate is updated.

**What a schema 5 gate would need.** These are the same rules applied to the new
inputs, not new rules.

| Input | Class | Note |
| --- | --- | --- |
| Publishing repository `dep0we/skills` | constant | Compiled into the gate, never read from a manifest |
| Schema version, 5 | constant | The gate's own |
| Skill names and their file paths | authority, from the baseline manifest | Same reasoning as the `files` array in schema 4 |
| Commit | authority, from the baseline manifest | A full commit hash, validated as 40 hex characters before use |
| Folder a skill came from | derived | Read from `primary-set.txt` at that commit, never from the manifest's `folder` |
| Hash of each file | published | SHA-256 of the blob at `<folder>/<rest>` at that commit |
| `source`, `folder`, per-skill `commit`, `rules`, `installedAt` | evidence | Reported, never resolved |

A commit hash is immutable by construction, so the tag protection ruleset is not
needed for this path. The remaining hazard is that a commit nobody can fetch
(history rewritten, repository private) must report as the source being
unreachable, never as a match.

**`rules` is not skill content.** The managed block in `AGENTS.md` is not under
an allowed skill directory and is not recorded in `files`. A gate has nothing to
exclude there, and the block gets reviewed as ordinary project content.

**Not built.** This repository has not changed any gate. Whether the kit
repository already implements a schema 4 gate was not checked. The update to the
gate is the maintainer's call and belongs to whoever owns that repository.
