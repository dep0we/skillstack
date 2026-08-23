# skillstack: spec

**Status:** spec and scaffold only (Linear DAR-155). Nothing in this document
is built yet except the two carried-forward scripts under `bin/`, copied in
unmodified. The bundle, the corrections, and the new tool are separate,
tracked work.

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
   every on-disk hash check trivially and needs a second hash that does not
   move with the file. Kit's own install manifest stores two per-file hashes
   for exactly this reason; section 4 adopts that vocabulary. Additional
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

**This shape has not been agreed with the kit-side work and must be treated
as a proposal, not a contract, until that happens.** Kit's own
`docs/BUILD-SPEC.md` (read in full for this work) defines `.kit/manifest.json`
for kit's own installed files and states integrity rules for a
maintainer-trusted manifest, but it does not yet mention this file at all —
there is currently no exclusion-from-review-scope mechanism in kit for
vendored skill content. That gap is real and is called out again in the
report for this task.

### Proposed shape

Filename: `.vendored-skills.json` at the project root — the name
`vendor-skills.sh` already writes and that a vendored-skill guard script in
one existing project and the maintainer's own decision record already
reference. Continuity over a fresh name, since three things outside this
repository already look for it by that name. The schema below is a breaking
change to what that file holds today, which is why it carries an explicit
version.

Each file entry carries **two hashes**, modeled on kit's install manifest:
`shippedSha256` records what this pack version shipped and is written once at
lay-down; `sha256` records what the tool last expected on disk and is what
`--forget` may update. A merge gate must use `shippedSha256` alone to decide
exclusion. Matching `sha256` without matching `shippedSha256` means the
maintainer kept a local edit, including after `--forget` re-recorded the
on-disk hash.

**What a `shippedSha256` match does and does not prove.** A field in this
file is a declaration a pull request can write, the same as any other field in
a committed JSON file; nothing about the shape of a JSON field makes it
unforgeable. A match means the bytes on disk match a number recorded in this
file. It does not mean this pack shipped those bytes. `shippedSha256`, the
`files` list, and the `"skills"` list all live in the project repository, so
the same change that edits a skill file can edit all three to agree with it.
A reader that only has this file and the working tree has no copy of what
skillstack published and cannot check them. What the second hash field actually
stops is `--forget` and a re-pin that updates `sha256` only. Catching a
hostile rewrite needs either a copy of the shipped hashes this pull request
cannot edit, or a human treating the manifest diff as the real review of the
files this mechanism would exclude. That a changed hash in this JSON file
appears in the pull request diff is not a hostile read of the skill file
itself; this shape just took that file out of review scope.

```json
{
  "schemaVersion": 3,
  "packs": {
    "test-driven-development": {
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
          "shippedSha256": "<sha256 of pack content at lay-down>",
          "sha256": "<sha256 the tool last recorded for on-disk content>"
        },
        {
          "path": ".cursor/skills/test-driven-development/SKILL.md",
          "shippedSha256": "<sha256 of pack content at lay-down>",
          "sha256": "<sha256 the tool last recorded for on-disk content>"
        },
        {
          "path": ".agents/skills/test-driven-development/SKILL.md",
          "shippedSha256": "<sha256 of pack content at lay-down>",
          "sha256": "<sha256 the tool last recorded for on-disk content>"
        }
      ]
    }
  }
}
```

At lay-down, `shippedSha256` and `sha256` are equal. After a hand edit,
on-disk content no longer matches either hash and the tool refuses to
overwrite. After `--forget`, the tool updates `sha256` to the current on-disk
content but leaves `shippedSha256` unchanged, so the file still does not
match what the pack shipped.

A project that has taken more than one pack carries one entry per pack name
under `"packs"`. `schemaVersion: 1` (undocumented, implicit) is the shape
`vendor-skills.sh` writes today, keyed by repository URL under `"vendored"`
rather than by pack name under `"packs"`, with a single hash per path and no
`shippedSha256`, `packVersion`, or `packCommit` field at all because today
there is no pack, only a direct upstream vendor. `schemaVersion: 2` was an
earlier proposal in this document with the same single-hash-per-path defect;
readers must treat it as withdrawn. A reader must treat a manifest with no
`schemaVersion` field as schema 1 and must not apply the rules below to it.

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

1. It starts with exactly one of `.claude/skills/`, `.cursor/skills/`, or
   `.agents/skills/`.
2. The first path segment after that prefix (the skill directory name) appears
   in that pack's `"skills"` array. For
   `.claude/skills/test-driven-development/SKILL.md` that segment is
   `test-driven-development`, the third segment overall, not the fourth
   (`SKILL.md`).
3. It names a file, not a directory (no trailing `/` after normalization).

Anything else — including project source, configuration, or a skill directory
not named in `"skills"` — is not pack content for this mechanism even if
someone added a matching hash. A reader that finds a disallowed path must
reject the whole manifest and exclude nothing.

### What a reader must be able to determine from this file alone

No network access, no clone of `skillstack` or of upstream, no state other
than this file and the working tree it describes:

1. **The complete set of file paths that belong to a named pack**, after
   normalization and allowed-location filtering. This is the only candidate
   list for exclusion from review scope — nothing outside this list is ever
   excluded by this mechanism, no matter what directory it sits in.
2. **Whether a listed file's on-disk bytes match `shippedSha256`.** Hash the
   file as it exists in the working tree and compare to `shippedSha256`, not
   to `sha256`. See the limit stated above: a match proves agreement with a
   number in this file, not that skillstack shipped those bytes. A gate may
   treat a match as grounds to exclude only after the open question below is
   settled with the guardrail toolkit.
   - On-disk hash matches `shippedSha256` → bytes match the number in this
     file. Not proof the pack shipped them; not safe to exclude on that
     strength alone until trustworthy shipped hashes have a settled source.
   - On-disk hash differs from `shippedSha256` → the file is not unmodified
     pack content, even if it matches `sha256`. **This must never be
     excluded.** This covers hand edits, `--forget` re-records, and any
     same-change re-pin that updated `sha256` without restoring the shipped
     bytes. A file in that state needs the same scrutiny as any other change
     in the diff, not less.
   - A file the manifest names that no longer exists on disk is neither
     excluded nor silently ignored; a reader should treat it as it would any
     other deleted tracked file and say so.
3. **Which pack, at which version and commit, produced the file**, for audit
   trail — "why was this excluded" must answer with a name, a version, and a
   commit, not just "a manifest said so."
4. **Which upstream repository, subdirectory, and commit the pack itself was
   cut from**, for provenance beyond `skillstack` — this is what lets someone
   eventually go compare a pack's corrections against a specific upstream
   snapshot.

The `sha256` field exists so the layering tool can keep working: detect hand
edits, refuse to overwrite them, and let `--forget` re-record on-disk content
without losing what the pack originally shipped. A merge gate must not treat
a `sha256` match as grounds for exclusion.

### Integrity rules a reader must apply before trusting the file at all

Modeled directly on the rules kit's own `BUILD-SPEC.md` already states for
`.kit/manifest.json`, because the failure mode is identical: a manifest a
reader trusts blindly is a manifest an editor can make say anything.

- **Invalid JSON: reject the whole file, exclude nothing.** Do not guess at a
  partial read.
- **A path is absolute, contains a `..` segment, or fails normalization:
  reject the whole file, exclude nothing.** A manifest is meant to describe
  only this project's own working tree; one that names a path outside it is
  not describing the tool's own writes and cannot be trusted for any purpose,
  the same reasoning kit's own manifest rule uses for `../`.
- **The same normalized path appears under more than one pack, or twice in
  one pack's `files` array: reject the whole file, exclude nothing.**
  Ownership of a path by two packs at once cannot be resolved by a reader
  that only sees this file; it needs a human decision, not a guess.
- **A path fails the allowed-location rules above: reject the whole file,
  exclude nothing.**
- **A file entry is missing `shippedSha256` or `sha256`: reject the whole
  file, exclude nothing.** Both hashes must be present for every entry; a
  reader cannot infer shipped content from `sha256` alone.
- **An unrecognized `schemaVersion`: treat as untrusted for this mechanism.**
  A future schema 4 reader encountering schema 3 should refuse to apply
  schema-3-specific rules to it rather than partially interpreting a shape it
  was not built for.

A manifest that fails any of these rules means the reader falls back to
reviewing every file normally — the same posture as if the manifest did not
exist at all. Failing closed here is the same posture kit already takes with
its own manifest.

### What this shape does not attempt to solve here

- **Where kit's gate reads this from**, whether it needs its own copy of the
  hashing logic or can shell out to something `skillstack` ships, and how a
  project with no `skillstack`-managed packs at all is told apart from one
  whose manifest failed integrity — all kit-side design work, out of scope
  for this repository.
- **Whether `schemaVersion: 1` files need a migration path** written by this
  tool, versus simply being left alone until the project re-runs vendoring
  and gets upgraded. Not decided here.
- **OPEN QUESTION — source of trustworthy shipped hashes.** This document
  proposes comparing on-disk bytes to `shippedSha256` in
  `.vendored-skills.json`, but that field, the `files` list, and the
  `"skills"` list are all writable by the pull request under review. Where
  shipped hashes come from that a gate can trust is unsettled. It must be
  settled with the guardrail toolkit before any gate excludes files on the
  strength of this manifest. This document does not pick a mechanism.

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
section 4 raises and has not yet been solved on the kit side. Installing kit
here now would hit that unsolved problem immediately, for no benefit this
repository currently needs.

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
  chose to give this one up". In schema 3 the new tool must re-record only
  `sha256`, never `shippedSha256`;
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

1. **The manifest shape in section 4 needs to be agreed with the kit-side
   work before it is final.** Kit's `BUILD-SPEC.md` currently has no
   exclusion-from-review-scope mechanism at all; this document proposes one
   from the `skillstack` side only. Whoever does that kit-side design work
   needs to accept, reject, or revise this shape — in particular the field
   names, the reject-and-fall-back-closed integrity rules in section 4, and
   whether kit wants its own copy of the hashing logic or to shell out to
   something this repository ships. That work must also settle the open
   question in section 4 about where trustworthy shipped hashes come from;
   no gate should exclude on `shippedSha256` alone until it is.
2. **Whether `.vendored-skills.json`'s filename should change** now that its
   schema is a breaking change from what it holds today (repository-keyed,
   no pack concept) to what section 4 proposes (pack-keyed, with pack version
   and upstream provenance nested). This document recommends keeping the name
   for continuity with the three things that already reference it by that
   name, but that is a recommendation, not a settled call.
