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
   deliberate override that never deletes anything and re-records that one
   hash — closing gap 3 by giving every project the same corrected content,
   recorded the same way, from one source. Schema 4 carries one hash per file
   and it serves the tool alone; no gate reads it, so there is no second
   hash for `--forget` to disturb.
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

### The trust model

Three rules. They constrain **inputs**: what a gate is allowed to believe, and
from where.

1. **Anything the change under review can write is evidence, never
   authority.** Every field in `.vendored-skills.json` lives in the project
   repository, so the same change that edits a skill file can edit any field
   that would have vouched for it. This is true of the file, of any file a
   pull request can reach, and of anything derived from one.
2. **Exclusion scope and pack identity come from the target branch.** What may
   be excluded is decided by the manifest already merged into the branch being
   merged into. The proposed manifest is compared against that baseline and is
   never read as the source of scope or identity.
3. **Shipped hashes come from a publishing repository the gate pins, at a
   release tag the gate derives.** A pull request can edit its own manifest.
   It cannot edit what a repository it does not control published.

**These rules are not self-enforcing, and the mechanisms below do two
different jobs.** Some implement a rule directly (the input inventory, the
baseline comparison, the pinned constants). Others exist because a rule can be
satisfied and the result still be useless or invisible: the naming grammar
stops two different packs resolving to one tag, the hash arithmetic stops a
gate that never matches anything, and the outcomes stop a gate that failed
from reading like a gate that passed. Do not read "it follows from a rule" as
"therefore it is handled."

**Rule 3's "immutable" is an intention until the host enforces it.** See the
tag protection requirement below, which is not yet in place.

This design has now been defeated four times, each time the same way: an input
that nobody had listed turned out to be writable by the change under review,
and it was read as authority. First the per-file hash. Then `shippedSha256`
beside it. Then the `files` array, still read as authority after the version
fields around it had been checked. Then the **publishing repository itself**,
because the document said "ask `skillstack`" and never said where `skillstack`
is, so an implementer would have taken the URL from the only repo-shaped field
available, which lives in the manifest.

That is why the next subsection exists, and why it is a list rather than a
principle. **A principle you agree with does not enumerate. The inventory
does.** If the inventory is not exhaustive, defeat five is already here.

### The input inventory

Every input the gate takes. Each is **constant** (compiled into the gate),
**authority** (trusted, and it must be shown why it cannot be written by the
change), or **evidence** (read, compared, reported, never trusted).

| Input | Source | Class |
| --- | --- | --- |
| Publishing repository host, owner and name | Compiled into the gate | constant |
| Transport and API endpoints used to reach it | Compiled into the gate | constant |
| Tag name grammar and hash algorithm | This document | constant |
| Manifest path `.vendored-skills.json` | Compiled into the gate | constant |
| Baseline manifest content | The target commit being merged into | authority |
| Pack name, `packVersion`, `skills`, `files` | The **baseline** manifest | authority |
| Release tag | Derived from baseline pack name and version | authority |
| `files.json` and its hashes | The pinned repository, at that tag | authority |
| Proposed manifest content | The commit under review | evidence |
| `source`, `packCommit`, `upstream.*`, `installedAt` | Either manifest | evidence |
| File content being checked | The commit under review | evidence |
| Working tree as checked out | Anywhere | never read |
| Target ref of the pull request | The hosting platform | authority |
| The gate's own code and workflow definition | The guardrail toolkit's release | authority |

**The publishing repository is pinned in the gate and is never read from the
project.** No field in `.vendored-skills.json` names it, contributes to
naming it, or redirects it. `source` exists as a human label and is evidence;
a gate that resolves anything from it has reintroduced defeat four. The
transport is an input too: the API base and the URL shapes are pinned, not
assembled from manifest values.

`upstream.repo` in a manifest is provenance for a human, never a fetch target.

**Two inputs on that list are authority the gate cannot verify for itself, and
they are named so that nobody mistakes the list for a closed system.** The
target ref comes from the hosting platform: a pull request author chooses what
to target, so a chain of pull requests can end at a branch whose baseline
manifest the author wrote. What contains that is not this mechanism but the
requirement that the change eventually reach the protected branch through a
pull request reviewed against *its* baseline. The gate's own code and its
workflow definition live in the project repository too, and a change that
edits them defeats every rule above at once; that is the guardrail toolkit's
existing problem and it already answers it by pinning the gate script by
digest. Neither is solved here, both are inputs, and an inventory that omitted
them would be the same omission that produced defeat four.

**The pinned values themselves live in the gate's source, not in this
document.** What this document fixes is that they are literals there, reviewed
as code, and that no project-supplied string reaches them. Stating the policy
without the literal is deliberate; leaving the policy unstated is what caused
defeat four.

### The manifest (`schemaVersion: 4`)

Filename: `.vendored-skills.json` at the project root — the name
`vendor-skills.sh` already writes and that a vendored-skill guard script in
one existing project and the maintainer's own decision record already
reference. Continuity over a fresh name.

**One hash per file, named `sha256`, and it belongs to the tool, not to the
gate.** It records what the layering tool last wrote or last accepted on disk,
and it is what makes hand-edit detection and `--forget` work with no network.
The gate never reads it. Schema 3's second field, `shippedSha256`, is
**removed** rather than renamed: it was not authoritative, its name asserted
that it was, and two authoritative-looking fields where only one is
authoritative is how an earlier version of this design was defeated.

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

**The key under `"packs"` is the pack name, not a skill name.** Above that is
`superpowers`, matching `packs/superpowers/pack.json`, while
`test-driven-development` is one of the skills that pack contains. Earlier
revisions used a skill name as the key, which taught the wrong lookup key for
the field a gate resolves a release by.

**There is no `packTag` field, deliberately**, and no field naming a
repository. Both would be inputs the change under review can write.

`packCommit`, `source`, `upstream` and `installedAt` are **evidence**: they are
reported for audit and never resolved. The commit a gate reports as
authoritative is the one it resolved from the release tag.

`schemaVersion` history: **1** is the undocumented shape `vendor-skills.sh`
writes today, keyed by repository URL under `"vendored"`, one hash per path,
no pack concept, and it is what every real manifest in existence holds right
now. **2** and **3** were proposals in earlier revisions and are withdrawn.

### Naming grammar

Pack name and version are interpolated into a tag name and a repository path,
so without a grammar two different packs can produce one tag. A gate must
reject anything that does not match, before interpolating.

- **Pack name:** `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`, and additionally **must not
  contain the substring `-v` followed by a digit**.
- **Pack version:** `^[0-9]+\.[0-9]+\.[0-9]+$`. Exactly three numeric
  components, no prefix, no suffix, no pre-release part.

Together these make `<pack>-v<version>` unambiguous: the version always begins
with a digit immediately after `-v`, and a pack name may never contain that
sequence. Without both halves, pack `foo` at version `bar-v1.0` and pack
`foo-vbar` at version `1.0` produce the same string. The version rule alone
rejects the first; the pack-name rule alone rejects the second; both are
needed.

A pack name or version failing its rule is an integrity failure. The gate
excludes nothing for that pack and says which rule failed.

### Path normalization

Before any comparison — duplicate detection, allowed-location checks, or
hash lookup — a reader normalizes every path string the same way:

1. Replace backslashes with forward slashes.
2. If the path is absolute, reject the whole manifest.
3. Strip a leading `./` if present.
4. Collapse every run of two or more `/` characters to a single `/`.
5. Reject if any path segment is `..` or empty.
6. Reject if the path ends with `/` (these entries name files, not
   directories).

Two spellings that normalize to the same string are the same path. Normalize
before deciding whether a path appears twice, and before looking a path up in
the tree of any commit.

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

Anything else — including project source, configuration, or a skill directory
not named in `"skills"` — is not pack content for this mechanism even if
someone added a matching hash.

### Resolving the release

**The publishing repository is a constant in the gate.** For this pack family
it is the repository this document lives in. The gate carries its host, owner
and name as compiled-in literals, alongside the API base and the URL shapes it
uses. Changing any of them is a change to the gate, reviewed as code. Nothing
in a project manifest reaches them, contributes to building them, or redirects
them.

**The release tag** is `<pack>-v<packVersion>`, built from the pack name and
`packVersion` **taken from the baseline manifest**, after both pass the naming
grammar. So pack `superpowers` at `0.1.0` is `refs/tags/superpowers-v0.1.0`.
The gate resolves that exact ref. It does not accept a tag name from any
manifest, does not fall back to a branch, and does not fall back to
`packCommit`.

**Tags are cut on the merged commit, after merge, never before.** This
repository publishes by squash merge, and a squash merge creates a commit that
does not exist until the merge happens. A tag cut on a pre-merge commit names
an object the merge orphans. Not hypothetical: rebuilding this repository's
history on 2026-08-19 orphaned every commit sha existing clones held, and an
unauthenticated fetch of one of those shas returns HTTP 404, the same status
an unreachable repository returns.

**REQUIRED, and not yet in place: a tag protection rule on this repository.**
A tag is only immutable if the host enforces it. The rule must forbid both
rewriting and deleting any tag matching `*-v*`. Creating it is a repository
setting and therefore the maintainer's call. As of this writing this
repository has **no tags and no rulesets**, so until that changes every
project resolves `release not found` and nothing is excluded anywhere.

**The published hash map.** At each release tag this repository carries
`packs/<pack>/files.json`:

```json
{
  "schemaVersion": 1,
  "pack": "superpowers",
  "packVersion": "0.1.0",
  "packCommit": "<sha>",
  "files": {
    "test-driven-development/SKILL.md": "<sha256 of the file's content bytes>"
  }
}
```

**Keys are pack-relative, not project-relative.** This keeps the published
list independent of how many directories a project lays skills into: a project
that took two directories and one that took three check against the same map,
and changing the layout cannot invalidate a published pack. A project path
maps to a key by stripping the `.claude/skills/` or `.agents/skills/` prefix.
One fetch per pack, not one per file.

A fetched `files.json` whose `pack` or `packVersion` does not match the tag it
was fetched under is treated as `release incomplete`, not as a hash source.

Release-time validation, an obligation of the pack-cutting step and not of the
gate: `files.json` must be the complete and exact map of everything under
`packs/<pack>/skills`. A file omitted from the map is never excluded by a
gate, so an omission fails safe, but the map is still wrong.

**What a hash in this map proves.** That the bytes checked are the bytes this
repository published at that release. Not that the pack was correctly
reviewed, that its corrections are complete, that it is licence-compliant,
that it really derives from the upstream commit it names, or that this
repository was not itself compromised. Fetching and hashing each remote file
rather than trusting the map adds nothing against those, because bytes and map
come from the same authority.

### The hash: exactly which number

**`files.json` stores the SHA-256 of the file's content bytes. That is also
what the gate computes. It is not a git object id.**

This is stated at length because the earlier wording, "hash the git blob," is
wrong arithmetic for the right intention and would produce a gate that never
matches anything. Git prefixes `blob <length>\0` to the content and, by
default, hashes that with SHA-1. Measured:

    file content                      hello\n
    SHA-256 of those bytes            5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03
    git object id (git hash-object)   ce013625030ba8dba906f756967f9e9ca394464a

Different lengths, different algorithms, different inputs. A gate comparing
one to the other excludes nothing, forever, and reports it as "nothing needed
excluding."

**The intention behind the earlier wording stands and is why this is not
simply "hash the file."** A working-tree read is divertible: by a symlink, by
a clean/smudge filter, by line-ending conversion, or by a checkout that never
produced the file faithfully. So:

1. Read the **content of the object git records for that path at the commit
   under review**, not the working tree.
2. Compute SHA-256 over those bytes.
3. Compare to the map.

Reject any path whose entry at that commit is not a regular file blob. A
symlink, a gitlink or a submodule entry at a path the manifest names is an
anomaly, never pack content, and is never excluded.

### What the gate determines, and in what order

Every tree read below is named explicitly. There is no step that reads "the
project" or "the file" without saying which commit.

1. **Read the baseline manifest** at the actual target commit being merged
   into — not the merge base, not the working tree. For a merge from another
   branch these differ, and the target commit is the one whose contents a
   merge actually accepts. This is the sole source of exclusion scope and pack
   identity.
2. **Read the proposed manifest** at the commit under review, as evidence, and
   compare. For each pack in the baseline: if the pack is absent from the
   proposed manifest, or its `packVersion`, `skills` array or `files` array
   differ in any way, **exclude nothing for that pack** and say so. A
   legitimate pack upgrade therefore gets exactly one full review, which is
   the correct price: an upgrade changes the content being trusted.
   **Deleting the manifest, or replacing it with one that has no packs, is
   this case, not `not applicable`.** `not applicable` is only ever reached
   when the baseline has no packs.
3. **Validate** the baseline pack against the naming grammar, allowed
   locations and integrity rules.
4. **Probe the pinned repository for reachability**, then resolve the derived
   tag, then fetch `files.json` at it. Three separate results; see below.
5. **Hash and compare** each path in the baseline pack's `files`, reading the
   object at the commit under review, per the section above.

### The outcomes, which must never print the same result

A check that could not run and a check that found nothing wrong are the same
clean line unless the tool makes them different. Each outcome below has
**exactly one cause**. Where a condition has several causes they are separate
outcomes, because "which of three things went wrong" is the operator's next
question and a shared label deletes the answer.

Kit words these lines, but that it must be able to tell them apart is part of
this contract, not an implementation detail left to the reader.

**Nothing to do:**

- **`not applicable — no packs`** — the baseline manifest is absent, or is
  present with an empty `packs` object. Nothing to exclude and nothing wrong.
- **`unsupported schema`** — the baseline manifest has `schemaVersion` other
  than 4, or none (which means schema 1). Not an error and not a pass:
  schema 1 is what every real manifest holds today, and it is outside this
  mechanism entirely. Excludes nothing, reports the version found.

**Refused, and why:**

- **`manifest rejected`** — an integrity rule, naming grammar rule or
  allowed-location rule failed. Names the rule and the offending value.
- **`identity changed`** — the proposed manifest differs from the baseline for
  this pack. Names which field.
- **`lookup failed`** — the reachability probe against the pinned repository
  did not succeed. The source could not be consulted. Never conflated with any
  answer the source might have given.
- **`release not found`** — reachability proved, and the derived tag does not
  exist in the pinned repository. A missing release, not a missing source.
- **`release incomplete`** — the tag exists and `files.json` is missing,
  unparseable, or names a `pack` or `packVersion` that disagrees with the tag.

**The reachability probe exists so those last three are distinguishable.** An
anonymous 404 covers a missing tag, a private repository and a repository that
does not exist, so a gate that reads only the tag request cannot tell them
apart. Probe the repository itself first, by a request that returns a distinct
success when the repository is visible. Only after that succeeds may a 404 on
the tag be read as `release not found`. If the probe fails, the outcome is
`lookup failed` regardless of what any later request returns, and the gate
does not guess whether the repository is private or absent: both mean the
source is unusable and neither is actionable differently.

**Per file:**

- **`in scope — hash mismatch`** — the path is in the published map and the
  computed SHA-256 differs.
- **`in scope — not published`** — the path is in the baseline `files` and
  absent from the published map.
- **`in scope — not a regular file`** — the entry at that path is a symlink,
  gitlink or submodule.
- **`in scope — deleted`** — the baseline names the path and the commit under
  review has no entry for it.
- **`excluded`** — all checks passed. Reports the count, the pack, the version,
  and the release commit the tag resolved to. "Why was this excluded" answers
  with a name, a version and a resolved commit, never "a manifest said so."

A force-pushed pull request is re-evaluated against its new commit. A prior
result is never reused, because the commit it described no longer exists.

### Integrity rules a reader applies before trusting a manifest at all

A manifest failing any of these means every file is reviewed normally — the
same posture as if it did not exist.

- **Invalid JSON: reject.** Do not guess at a partial read.
- **A required field is missing: reject.** For each pack, all of `source`,
  `packVersion`, `skills` and `files` must be present, and every file entry
  must have `path` and `sha256`. A pack missing `packVersion` would otherwise
  derive the tag `superpowers-v` with nothing after it and resolve nothing.
- **A file entry carries `shippedSha256`: reject.** The removed field is
  rejected rather than ignored, so a schema 3 manifest mislabeled as schema 4
  fails loudly instead of being read under rules it was not written for.
- **A path is absolute, contains `..`, or fails normalization: reject.**
- **The same normalized path appears under more than one pack, or twice in one
  pack's `files`: reject.** Ownership by two packs needs a human decision.
- **A path fails the allowed-location rules: reject.**
- **Pack name or `packVersion` fails the naming grammar: reject.**

### What this shape does not attempt to solve here

- **How kit implements this** — caching, retry and backoff, and the exact
  wording of each outcome line. The set of outcomes and their distinctness is
  contract; the phrasing is not.
- **Whether `schemaVersion: 1` files need a migration path** written by this
  tool, versus being left alone until the project re-runs the tool. Not
  decided here. Until then they report `unsupported schema`.
- **A compromised `skillstack`, or a direct push to a project's target
  branch.** Both defeat this design, and both defeat every alternative
  considered, because each removes the authority the gate rests on rather than
  tricking it. They are answered by protecting the release-writing path and
  the target branch, not by anything in this file.

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
   no pack concept) to the pack-keyed schema 4 that section 4 sets out. This
   document recommends keeping the name for continuity with the three things
   that already reference it by that name, but that is a recommendation, not
   a settled call. It is the only part of section 4 still open; the shape
   itself is settled.
