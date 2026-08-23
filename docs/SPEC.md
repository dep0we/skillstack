# skillstack: spec

**Status:** the corrected pack is built and merged. Section 4 is a settled
contract between this repository and the guardrail toolkit that reads the
manifest; everything it describes on the reading side is specified and not yet
built on either side. The layering tool itself does not exist yet: `bin/` still
holds only the two carried-forward scripts, copied in unmodified, both of which
section 6 marks superseded.

## 1. The problem this solves

The maintainer layers third-party agent skills into project repositories so a
cloud coding agent — which clones a repo into an isolated VM with no access to
the maintainer's laptop — can read them. Skills are committed files, not an
installed plugin, for that reason alone.

The current tool, `vendor-skills.sh` in the maintainer's personal config
repository, does the copy and the hand-edit protection well, but three things
are missing, each measured across four project repositories on 2026-08-18/19:

1. **No skill selection.** It vendors every skill under the upstream
   `skills/` subdirectory or none. One project has 165 of 194 tracked files as
   skill copies (roughly 520KB) because there is no way to take three skills
   and leave the other thirteen.
2. **No corrections.** The upstream stack ships instructions that contradict
   the maintainer's rules — six found by review so far: delete code written
   before its test (destroys uncommitted work that exists nowhere else),
   offer to merge a branch locally, print environment variables while
   debugging, commit plans and specs holding client values, decide a reserved
   question itself and report a capped review as finished, and use a scratch
   directory as a home for client values. `bin/soften-tdd.py` fixes one of
   these in every copy of one skill file the script reaches (normally three,
   under `.claude/`, `.cursor/`, and `.agents/`), and the identical wording
   is still live, untouched, in three more files this script never opens
   (`writing-skills/SKILL.md` and two files beside it).
3. **No propagation.** Three project repos hold three divergent copies of the
   same upstream commit, differing in sixteen files. Only one carries the
   upstream copyright notice the licence requires to travel with the copies.
   Only one carries the package declaration that lets a shipped script run on
   a current Node runtime.

`skillstack` is the fix: one repository that owns the corrected bundle
("pack") definitions, and a tool that lays a chosen set of them into a project
repository, recording enough about what it did that both a human and an
automated reader can trust the result without re-deriving it.

## 2. What a "skill pack" is

A **pack** is a named, versioned bundle consisting of:

- an **upstream source**: a git repository URL, a subdirectory within it
  (upstream ships skills under `skills/`), and the exact commit the pack was
  cut from;
- a set of **skill directories** taken from that source, each one usable
  independently — a project can take some skills from a pack and not others;
- a set of **corrections**: specific, reviewed edits applied on top of the
  upstream content, each with a stated reason, before the pack is ever handed
  to a project. A correction is not a per-project hand-edit; it is decided
  once, here, and every project that takes the pack gets the same fix.
- a **pack version**, independent of the upstream commit. The pack version
  moves when the maintainer's corrections change — a new correction is added,
  an existing one is revised — even if upstream has not moved. The upstream
  commit moves when the maintainer decides to take a newer upstream snapshot,
  which can happen without any correction changing. These are two different
  axes and the manifest (section 4) has to carry both, separately, or a
  reader cannot tell "the corrections changed" from "upstream moved" from the
  version number alone.

A pack is the unit `skillstack` publishes. A project does not vendor from
upstream directly; it takes a pack, at a pack version, from `skillstack`.

### How pack content is held

**A pack is a corrected snapshot, committed in this repository.** The
corrected files live here, pinned to an upstream commit, and the tool copies
them into a project. Alongside them, the corrections are kept as a separate
record: one entry per change, each with its reason.

Both, not either. The snapshot is what ships. The record is how a newer
upstream snapshot gets re-corrected, and how anyone tells a deliberate
correction from a stray edit.

Two alternatives were considered and rejected. Forking upstream puts the
corrections into someone else's commit history and turns every upstream
update into a merge, while dissolving the list of what was changed and why.
Holding only the corrections and applying them at install time means the
bundle is assembled from whatever upstream says that day, so no two installs
are guaranteed identical and nothing ever reviews the result as a whole.
A pinned exact patch against a pinned upstream commit would fail loud when
surrounding text no longer matches, not silently leave the hole; the snapshot
still wins because the finished bundle is reviewed once here as a whole,
which install-time assembly cannot offer even when individual steps fail loud.

The phrase-matching shape is not a theoretical risk. `bin/soften-tdd.py`
corrects by matching phrases in upstream text; adversarial review found it
caught three instances of the instruction it targets and missed four more of
the same instruction, plus three files it never opens. Install-time patching
that copies that shape breaks silently when upstream rewords.

The upstream copyright notice travels with the snapshot, because the licence
requires it to accompany any copy. Two of the four projects that vendored by
hand are currently missing it.

See `docs/decisions/2026-08-19-store-a-corrected-snapshot.md`.

## 3. What the tool does (not yet built)

Conceptually, replacing `bin/vendor-skills.sh` with something that:

1. Lets the caller name which skills to take from a pack, not just which
   pack — closing gap 1 above.
2. Copies pack content that is **already corrected**, rather than correcting
   at lay-down time. Corrections are applied once, here, when a pack version
   is cut; see "How pack content is held" above. The tool's job is to copy a
   reviewed snapshot faithfully, not to transform upstream text per project,
   which is what closes gap 2. The corrections
   themselves need a verification shape that survives what a vendored-skill
   guard script in one existing project proves a gate has to survive: a hash
   alone is defeated by a same-change re-pin — a change that edits a corrected
   file, recomputes its hash, and updates whatever recorded the old one passes
   every on-disk hash check trivially. A second hash stored beside the first
   does not fix it, because the same change can write both; section 4 answers
   it instead by taking the shipped hashes from outside the repository under
   review entirely. Additional
   signals (required wording present a minimum number of times, a floor on
   how many files are corrected, a scan for the forbidden phrasing the
   correction removed) remain design work for the pack-cutting step, not for
   the project manifest a merge gate reads.
3. Keeps the existing manifest mechanics that already work: per-file
   sha256 of on-disk content, a refusal to overwrite a file whose disk hash
   no longer matches what was recorded (a hand edit), and a `--forget`-style
   deliberate override that never deletes anything and re-records only the
   on-disk hash, never the shipped hash — closing gap 3 by giving every
   project the same corrected content, recorded the same way, from one source.
4. Publishing a new pack version, or moving to a newer upstream commit, has
   to be something every project can pick up without hand-copying files again
   — this is the propagation gap. The mechanism for that (a re-run of the
   tool against the recorded pack version) is design work for the
   implementation phase, not this document. Today's `vendor-skills.sh` does
   not diff against a recorded upstream commit; it clones the latest default
   branch, walks every file, and copies by fingerprint.

None of this is implemented here. This section states intent so the manifest
shape in section 4 is grounded in what will eventually write and read it,
not designed in a vacuum.

## 4. The manifest shape

**This is the load-bearing decision in this document**, because a project
repository's manifest is read by a party outside this repository entirely:
the kit merge gate needs to exclude vendored files from adversarial review
scope, and it can only do that by reading a committed file — it has no other
way to know which files in a diff are pack content the maintainer already
reviewed once, here, versus project-specific work that needs the same
scrutiny as everything else.

**This shape is now agreed with the kit-side work.** The maintainer ruled on
2026-08-20 that the gate does not trust the hash list inside the project under
review; it asks `skillstack` for the hashes that pack version actually
shipped. Schema 3, described in earlier revisions of this document, proposed
the opposite and is withdrawn. What follows is a contract, not a proposal.

### The trust model, which the rest of this section only implements

Three rules. Every mechanism below exists to serve one of them, and a reader
that keeps them straight can re-derive the rest.

1. **Anything the change under review can write is evidence, never
   authority.** Every field in `.vendored-skills.json` lives in the project
   repository, so the same change that edits a skill file can edit any field
   that would have vouched for it. This is not a flaw in a particular field.
   It is true of the file, and of any file a pull request can reach.
2. **Exclusion scope comes from the target branch.** What may be excluded is
   decided by the manifest already merged into the branch being merged into.
   The proposed manifest is compared against that baseline and is never read
   as the source of scope or identity.
3. **Shipped hashes come from `skillstack`, at an immutable release tag.** A
   pull request can edit its own manifest. It cannot edit what this repository
   published.

This design has now been defeated three times, each time in the same way: a
field that a reviewer had not thought of turned out to be writable by the
change being reviewed, and it was read as authority. First the per-file hash.
Then `shippedSha256` beside it. Then the `files` array itself, still read as
authority after the version fields around it had been checked. Rule 1 is the
general form. Apply it to every new field before adding one.

### The manifest (`schemaVersion: 4`)

Filename: `.vendored-skills.json` at the project root — the name
`vendor-skills.sh` already writes and that a vendored-skill guard script in
one existing project and the maintainer's own decision record already
reference. Continuity over a fresh name, since three things outside this
repository already look for it by that name.

**One hash per file, named `sha256`, and it belongs to the tool, not to the
gate.** It records what the layering tool last wrote or last accepted on disk.
It is what makes hand-edit detection and `--forget` work with no network. The
gate never reads it. Schema 3's second field, `shippedSha256`, is **removed**
rather than renamed: it was not authoritative, its name asserted that it was,
and two authoritative-looking fields where only one is authoritative is how
the previous design was defeated.

```json
{
  "schemaVersion": 4,
  "packs": {
    "superpowers": {
      "source": "skillstack",
      "packVersion": "0.1.0",
      "packCommit": "<sha of the skillstack commit this pack version was cut from>",
      "upstream": {
        "repo": "https://github.com/obra/superpowers",
        "subdir": "skills",
        "commit": "<sha upstream was pinned to when this pack version was cut>"
      },
      "installedAt": "<ISO 8601 timestamp>",
      "skills": ["test-driven-development"],
      "files": [
        {
          "path": ".claude/skills/test-driven-development/SKILL.md",
          "sha256": "<sha256 the tool last recorded for on-disk content>"
        },
        {
          "path": ".agents/skills/test-driven-development/SKILL.md",
          "sha256": "<sha256 the tool last recorded for on-disk content>"
        }
      ]
    }
  }
}
```

**The key under `"packs"` is the pack name, not a skill name.** In the example
above that is `superpowers`, matching `packs/superpowers/pack.json`, while
`test-driven-development` is one of the skills that pack contains. Earlier
revisions of this document used a skill name as the key, which taught the
wrong lookup key for the field the gate resolves a release by.

**There is no `packTag` field, deliberately.** The release tag is derived from
the pack name and pack version (see below), never read from the manifest. A
tag name the project supplies is one more thing the change under review can
write, which rule 1 forbids.

`packCommit` is **audit-only**. It answers "which commit was this cut from"
for a human reading history. Nothing resolves it, nothing verifies against it,
and forging it gains nothing. The commit a gate reports as authoritative is
the one it resolved from the release tag, not this field.

`schemaVersion` history: **1** is the undocumented shape `vendor-skills.sh`
writes today, keyed by repository URL under `"vendored"`, one hash per path,
no pack concept. **2** and **3** were proposals in earlier revisions of this
document and are withdrawn; 3 in particular carried `shippedSha256` and told
gates to exclude on it, which is now known to be unsound. A reader must treat
a manifest with no `schemaVersion` as schema 1, and must not apply the rules
below to any version it does not recognise.

### Path normalization

Before any comparison — duplicate detection, allowed-location checks, or
hash lookup — a reader must normalize every path string the same way:

1. Replace backslashes with forward slashes.
2. If the path is absolute, reject the whole manifest (see integrity rules).
3. Strip a leading `./` if present.
4. Collapse every run of two or more `/` characters to a single `/`.
5. Reject if any path segment is `..` or empty.
6. Reject if the path ends with `/` (these entries name files, not
   directories).

Two spellings that normalize to the same string are the same path. A reader
must apply normalization before deciding whether a path appears twice or
whether a working-tree file is listed.

### Allowed locations

A path in `files` is pack content only if **all** of the following hold after
normalization:

1. It starts with exactly one of `.claude/skills/` or `.agents/skills/`.
2. The first path segment after that prefix (the skill directory name) appears
   in that pack's `"skills"` array. For
   `.claude/skills/test-driven-development/SKILL.md` that segment is
   `test-driven-development`, the third segment overall, not the fourth
   (`SKILL.md`).
3. It names a file, not a directory (no trailing `/` after normalization).

**`.cursor/skills/` is not an allowed location in schema 4.** The reason is
that Cursor and Codex both read `.agents/skills/`, which makes a third copy
redundant. That rests on a loader-trace measurement taken on 2026-08-17 and
2026-08-18, carried here from a prior session's record rather than re-run for
this document. It is the load-bearing fact for the narrowing, so it is being
re-measured under DAR-157 and the transcripts will be recorded with that
decision. **If the re-measurement contradicts it, this rule is what changes.**
A schema 4 manifest naming a `.cursor/` path was not written by this tool and
the reader rejects it. Schema 1 manifests predate all of this and are governed
by their own (absent) rules, not by these.

Anything else — including project source, configuration, or a skill directory
not named in `"skills"` — is not pack content for this mechanism even if
someone added a matching hash. A reader that finds a disallowed path must
reject the whole manifest and exclude nothing.

### Resolving shipped hashes from `skillstack`

**The release tag.** Cutting a pack version creates an annotated tag named
`<pack>-v<packVersion>`, so pack `superpowers` at version `0.1.0` is
`refs/tags/superpowers-v0.1.0`. A reader derives that name from the pack name
and version in the manifest and resolves that exact ref. It does not accept a
tag name from the manifest, does not fall back to a branch, and does not fall
back to `packCommit`.

**Tags are cut on the merged commit, after merge, never before.** This
repository publishes by squash merge, and a squash merge creates a commit that
does not exist until the merge happens. A tag cut on a pre-merge commit names
an object that the merge orphans. This is not hypothetical: rebuilding this
repository's history on 2026-08-19 orphaned every commit sha that existing
clones held, and an unauthenticated fetch of one of those shas returns HTTP
404 — the same status an unreachable repository returns.

**REQUIRED, and not yet in place: a tag protection rule on this repository.**
A tag is only immutable if the host enforces it. The rule must forbid both
rewriting and deleting any tag matching `*-v*`. Without it, "immutable release
tag" is a description of intent rather than a property, and the whole
mechanism rests on it. Creating the rule is a repository setting and therefore
the maintainer's call, not something this document or the tool can do. As of
this writing this repository has **no tags and no rulesets**, so the mechanism
has nothing to resolve yet; see "release not found" below, which is the state
every project is in until the first tag exists.

**The published hash map.** At each release tag, this repository carries
`packs/<pack>/files.json`:

```json
{
  "schemaVersion": 1,
  "pack": "superpowers",
  "packVersion": "0.1.0",
  "packCommit": "<sha>",
  "files": {
    "test-driven-development/SKILL.md": "<sha256>"
  }
}
```

**Keys are pack-relative, not project-relative.** This is what keeps the
published list independent of how many directories a project lays skills into:
a project that took two directories and one that took three check against the
same map, and changing the layout cannot invalidate a published pack. A reader
maps a project path to a pack-relative key by stripping the
`.claude/skills/` or `.agents/skills/` prefix. One fetch per pack, not one per
file.

Release-time validation, which is the pack-cutting step's obligation and not
the gate's: `files.json` must be the complete and exact hash map of everything
under `packs/<pack>/skills`, and its `packVersion` must match the tag it is
published under. A file omitted from the map is not excluded by any gate, so
an omission fails safe, but it still means the map is wrong.

**What a hash in this map does and does not prove.** It proves the bytes on
disk are the bytes this repository published at that release. It does not
prove the pack was correctly reviewed, that its corrections are complete, that
it is licence-compliant, that it was really derived from the upstream commit
it names, or that this repository was not itself compromised. Fetching and
hashing each remote file rather than trusting the map adds nothing against
those, because the bytes and the map come from the same authority.

### What the gate determines, and in what order

1. **Read the baseline manifest** — `.vendored-skills.json` as it exists on
   the actual target commit being merged into, not on the pull request's merge
   base and not on the working tree. For a merge from another branch these
   differ, and the target commit is the one whose contents a merge actually
   accepts. This baseline is the sole source of exclusion scope and pack
   identity.
2. **Read the proposed manifest** and compare. If the pack set, `packVersion`,
   `skills` array, or `files` array differ in any way for a pack, **exclude
   nothing for that pack** and say so. A legitimate pack upgrade therefore
   gets exactly one full review, which is the correct price: an upgrade
   changes the content being trusted.
3. **Resolve the release** for each baseline pack, by derived tag, and fetch
   its `files.json`.
4. **Hash and compare.** For each path in the baseline pack's `files`, hash
   the content and compare to the published map.

**Hash the git blob, not the checked-out file.** Read the object git records
for that path at the commit under review. A working-tree read can be diverted
by a symlink, by a filter or a line-ending conversion, or by a file the
checkout never produced faithfully. Reject any path whose git object is not a
regular file blob: a symlink, a gitlink, or a submodule entry at a path the
manifest names is an anomaly, not pack content, and it is never excluded.

Excluded only when: the pack identity is unchanged from the baseline, the
release resolved, and the blob hash equals the published hash. Everything
else is in scope.

### The outcomes, which must never print the same result

A check that could not run and a check that found nothing wrong are the same
clean line unless the tool takes care to make them different. Five outcomes,
five distinct messages:

- **`not applicable`** — the project has no `.vendored-skills.json`, or it has
  no packs. Nothing to exclude and nothing wrong. This must not read as a
  failure.
- **`lookup failed`** — `skillstack` could not be reached at all. Refuse to
  exclude anything, loudly, and name the cause. An anonymous caller cannot
  distinguish a private repository from one that does not exist, and does not
  need to: both mean the source is unreachable.
- **`release not found`** — `skillstack` was reachable and the derived tag does
  not exist there. Refuse to exclude anything for that pack, loudly. This is a
  different operator problem from `lookup failed` — a missing release versus a
  missing source — and it is the state every project is in until the first tag
  is cut, so it is the first case to test.
- **`in scope`** — a listed file's hash does not match the published map, or
  the pack identity changed in this pull request, or the manifest failed an
  integrity rule. Reviewed normally, with the reason stated.
- **`excluded`** — say how many files, for which pack, at which version, and
  which release commit the hashes came from. "Why was this excluded" must
  answer with a name, a version and a resolved commit, never with "a manifest
  said so."

A force-pushed pull request is re-evaluated against its new commit. A prior
result is never reused, because the commit it described no longer exists.

### Integrity rules a reader must apply before trusting the file at all

Modeled on the rules kit's own `BUILD-SPEC.md` states for `.kit/manifest.json`,
because the failure mode is identical: a manifest a reader trusts blindly is a
manifest an editor can make say anything.

- **Invalid JSON: reject the whole file, exclude nothing.** Do not guess at a
  partial read.
- **A path is absolute, contains a `..` segment, or fails normalization:
  reject the whole file, exclude nothing.**
- **The same normalized path appears under more than one pack, or twice in
  one pack's `files` array: reject the whole file, exclude nothing.**
  Ownership of a path by two packs at once needs a human decision, not a guess.
- **A path fails the allowed-location rules above: reject the whole file,
  exclude nothing.**
- **A file entry is missing `path` or `sha256`, or carries a `shippedSha256`
  field: reject the whole file, exclude nothing.** The removed field is
  rejected rather than ignored, so a schema 3 manifest mislabeled as schema 4
  fails loudly instead of being read under rules it was not written for.
- **An unrecognized `schemaVersion`: treat as untrusted for this mechanism**
  rather than partially interpreting a shape the reader was not built for.

A manifest that fails any of these means the reader reviews every file
normally — the same posture as if the manifest did not exist. Failing closed
here is the posture kit already takes with its own manifest.

### What this shape does not attempt to solve here

- **How kit implements any of this** — where the gate caches a fetch, whether
  it carries its own hashing logic or shells out to something this repository
  ships, and how it words each of the five outcomes. Kit-side design work,
  out of scope for this repository.
- **Whether `schemaVersion: 1` files need a migration path** written by this
  tool, versus being left alone until the project re-runs the tool and gets
  upgraded. Not decided here.
- **A compromised `skillstack`, or a direct push to a project's target
  branch.** Both defeat this design, and both defeat every alternative
  considered, because each removes the authority the gate is resting on rather
  than tricking it. They are answered by protecting the release-writing path
  and the target branch, not by anything in this file.

## 5. Does skillstack install kit into itself?

**No.**

Two reasons, one about this repository's actual shape and one about the
maintainer's own recorded experience with over-applying kit:

1. **kit's review machinery is sized for a different kind of work.**
   `docs/BUILD-SPEC.md`'s decisions and review-rounds skills, and its
   escalation and adversarial-review-round apparatus, exist for a coding
   agent building a feature with real design decisions and real risk of
   drift across a multi-round build. `skillstack`, at this stage, is a small,
   single-maintainer bash-and-data repository: bundle definitions and a
   layering tool, not a product under active multi-agent construction.
2. **The maintainer's own kit repository already flags over-application of
   this exact kind.** A recorded lesson from 2026-08-18 measured kit at 255
   commits in 11 days against 0 in every actual product repository it was
   meant to serve, the same self-building shape that got a predecessor factory
   tool paused at an 8:1 ratio. A freeze was recommended (not yet ruled)
   specifically to stop pointing kit's machinery at more tooling and meta-work
   before it has been proven against one real build. Installing kit into a
   brand-new tooling repository, before that freeze question is even settled,
   would be the exact pattern the lesson names, one more repo deep.

There is also a narrower, structural reason this repository is not a good kit
installation target yet regardless of the above: `skillstack`'s payload is
itself directories of skill-shaped files (the packs it stores and ships).
Kit's own secrets/opdata scanners and jargon check would need to tell
"skillstack's own tooling" apart from "the third-party skill content
skillstack exists to store" — precisely the exclusion-from-scope problem
section 4 now specifies and kit has not yet built. Installing kit here now
would hit that gap immediately, for no benefit this repository currently
needs.

This is a **reversible** call, not a permanent one: if `skillstack` grows into
multi-agent, multi-round build work, or if kit's exclusion-scope mechanism
gets solved and this repository would benefit from kit's checks over its own
`bin/` scripts, revisit it then. Nothing here forecloses that.

## 6. `vendor-skills.sh` and `soften-tdd.py`: carried forward vs. superseded

Both are copied into `bin/` in this repository, unmodified, and the originals
in the maintainer's personal config repository are untouched. Neither should
be run against a new project from this point forward; they are kept for
reference while the replacement is designed and built as separate work.

### `vendor-skills.sh` — carried forward in mechanism, superseded in design

**Carried forward:** the manifest mechanics are correct and the new tool
should keep them rather than reinvent them:

- recording a per-file sha256 of on-disk content at the moment a file is
  written;
- refusing to overwrite a file whose on-disk hash no longer matches what was
  recorded, and reporting it rather than guessing;
- `--forget` as the one deliberate way past that refusal, which never
  deletes anything and re-records the current on-disk hash so a future run
  can tell the difference between "still hand-edited" and "the maintainer
  chose to give this one up". Schema 4 has one hash per file, so `--forget`
  re-records `sha256` and there is no second field for it to disturb;
- treating orphaned files (upstream stopped shipping something this script
  once wrote) as reported, not deleted.

**Superseded:** the design built around those mechanics does not extend to
what a pack needs:

- it vendors by upstream repository URL as the top-level key, with no notion
  of a named, versioned pack sitting between "upstream" and "this project";
- it copies every skill under the subdirectory or none — no per-skill
  selection;
- it has no correction step at all; that is a separate script
  (`soften-tdd.py`) bolted on afterward, which opens every path matching
  `*/skills/test-driven-development/SKILL.md` (normally three copies under
  `.claude/`, `.cursor/`, and `.agents/`).

### `soften-tdd.py` — fully superseded

Its scope is proven too narrow to trust: it opens every path matching
`*/skills/test-driven-development/SKILL.md`, which in a normal project is
three copies under `.claude/`, `.cursor/`, and `.agents/`, and replaces
exactly three exact phrases in each copy it reaches. Adversarial review of an
actual import found the identical delete-the-code instruction live, untouched,
in three more files this script never opens (`writing-skills/SKILL.md` and
two files beside it), and four more live instances inside each copy it does
open, in wording its own three-phrase list does not match. A correction
mechanism that only proves itself against the exact file and wording it was
written for, with no signal when upstream rewords something or ships the same
instruction somewhere else, is not something to carry forward as-is. The
pack-level correction mechanism described in section 3 needs to generalize:
apply a correction to every file carrying the pattern, across every skill in
the pack, and fail loud — the same posture a vendored-skill guard script in
one existing project takes with minimum corrected counts and required-wording
lists, for the same reason.

## 7. Open questions for the maintainer

1. **REQUIRED: a tag protection rule on this repository.** Section 4 rests
   the whole gate on release tags being immutable, and a tag is only immutable
   if the host enforces it. The rule must forbid rewriting and deleting any
   tag matching `*-v*`. This repository currently has no tags and no rulesets.
   Creating the rule is a repository setting, so it is the maintainer's call,
   not something this document or the tool can do. Until it exists, and until
   the first tag is cut, every project resolves `release not found` and
   nothing is excluded anywhere. That is the correct failure, but it is a
   failure, and it is the state today.

   The manifest shape itself is **settled** and no longer an open question.
   The maintainer ruled on 2026-08-20 that the gate asks `skillstack` for the
   shipped hashes rather than trusting the copy in the repository under
   review, and that a human reading the manifest diff is explicitly not the
   control. Section 4 is written as a contract on that basis.

2. **Whether `.vendored-skills.json`'s filename should change** now that its
   schema is a breaking change from what it holds today (repository-keyed,
   no pack concept) to what section 4 proposes (pack-keyed, with pack version
   and upstream provenance nested). This document recommends keeping the name
   for continuity with the three things that already reference it by that
   name, but that is a recommendation, not a settled call.
