# skillstack: spec

**Status (2026-10-19):** the layering tool is built (`bin/lay-pack.sh`, tests
in `test/`), and it no longer lays from `packs/`. Skills now come from one
pinned source, the `dep0we/skills` repository at the commit in `source.lock`,
and the manifest it writes is schema 5. Section 3a describes that, and the
decision is in `docs/decisions/2026-10-19-skills-come-from-one-pinned-source.md`.
Sections 2 and 4 below still describe packs and the schema 4 contract. They are
kept because four projects hold a schema 4 manifest and because the merge gate
that reads the manifest has not been told about schema 5; the gate section of
4 says what that means. The merge gate itself is specified here and not built.
The two carried-forward scripts in `bin/` still refuse to run.

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

## 3. What the tool does

`bin/lay-pack.sh` replaces `bin/vendor-skills.sh`. It:

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

Points 1 to 3 are implemented in `bin/lay-pack.sh`. Point 4, propagation, is
partly implemented: a project picks up a new pack version by re-running the
tool against a newer checkout of this repository, and the tool refuses to run
at all while the pack tree is dirty, so `packCommit` cannot record a commit
whose content is not what was copied. What is still missing is the
pack-cutting step itself, which would cut a version and generate
`packs/<pack>/files.json`; today that map was produced once by hand. Nothing
in the tool assumes that step exists.

### What the tool writes into a project

Exactly four things, and nothing else:

1. **Skill files**, under the allowed destination directories named in section
   4. This is the only category a merge gate ever reads, and the only one
   recorded in `files`.
2. **`.vendored-skills.json`** at the project root.
3. **One ignore rule, `.superpowers/`, appended to the project's
   `.gitignore`.** Only when skills are laid.
4. **One managed block in `AGENTS.md`**, only when `--rules` is passed. See
   section 3a. Everything outside its two marker lines is left alone.

The third exists because the skills being copied in write live session state
into the working tree the moment they run, and the project has no way to know
that before it happens. The brainstorming companion server writes a
64-character session key in cleartext to
`.superpowers/brainstorm/.last-token`, and embeds the same key in a `?key=`
URL in that session's `state/server-info` and `server.log`.
`subagent-driven-development` writes plan workspaces under `.superpowers/sdd/`.

Measured on 2026-08-25 in a target repository with no such rule: after
`git add -A` and a commit, the key was tracked in two files, and a credential
scanner over the diff exited 0 and reported a pass. The scanner was not
skipping the path; it was pattern coverage. Its generic rule wants a
`name`/`key`/`token`/`secret` word, then a separator, then a quoted value, and
a bare hex blob in a file of its own has none of that. So this is not a gap one
project's gate closes for the others, and it does not announce itself while it
is open.

The pack's own `skills/brainstorming/visual-companion.md` already says to
"remind the user to add `.superpowers/` to `.gitignore` if it's not already
there". Relying on that reminder is what left the hole: four project
repositories had to fix it by hand after the fact. The tool that copies the
skills in is the only party that knows the writes are coming, which makes it
the party that has to say so.

Four properties, each of which is a test:

- **The rule is unanchored and directory-only.** Unanchored, so a session
  started with `--project-dir` pointing at a subdirectory is covered too.
  Directory-only, so `superpowers/notes.md` and `docs/.superpowers-notes.md`
  are untouched.
- **Presence is asked of `git check-ignore`, never grepped out of the file.**
  Those are different questions. A rule can be present and undone by a later
  negation, and a path can be covered by a rule that is not in this file at
  all. The probe runs with `--no-index`, because a path already in the index
  reports "not ignored" without it, which is true of the index and false of
  the rules, and would make every run append the rule again.
- **The file is appended to, never rewritten**, and a missing final newline is
  repaired first so the rule cannot land on the end of somebody else's line. A
  target that already has the rule is left byte-identical.
- **Session state already committed is reported, not papered over.** An ignore
  rule does not untrack a tracked file, and the credential is already in
  history. The run names the files and exits 2.

**The rule is not recorded in the manifest, and `.gitignore` is not a
destination directory.** Both would be the wrong shape. The allowed-location
list in section 4 is the rule a gate applies to every manifest path, so adding
a third entry to hold `.gitignore` would widen it for every path in every
project. And schema 4 is a contract with a reader in another repository, which
should not have to change for this: `git check-ignore` reports the rule's
presence directly, which is a stronger answer than a field the change under
review could have written.

**What this does not solve** is the key sitting on disk. `stop-server.sh` does
not delete a persistent session directory, and the server reads the token back
on the next start, so the key persists indefinitely and is reused across
restarts with no rotation. `.gitignore` keeps it out of git; it does nothing
about a copied, archived or snapshotted working directory, which is exactly
what a cloud agent's working directory is. That is upstream behaviour and it is
not corrected here.

## 3a. Where skills come from now, and the schema 5 manifest

**Added 2026-10-19.** Dan's machines install skills from one pinned source, the
`dep0we/skills` repository. A copy laid into a project has to come from the same
place, or the two drift. So `bin/lay-pack.sh` no longer reads `packs/`. The
reasoning and the alternatives are in
`docs/decisions/2026-10-19-skills-come-from-one-pinned-source.md`.

### Command line

```
bin/lay-pack.sh --skills a,b,c [--rules] [--targets agents|both] <project>
bin/lay-pack.sh --rules <project>
bin/lay-pack.sh --dry-run ... | --list <project> | --forget <skill> <project>
```

- `--skills` names the full set to keep current. There is still no "all".
- `--targets both` is the default and writes `.agents/skills` and
  `.claude/skills`, the two directories measured to cover every reader.
  `--targets agents` writes `.agents/skills` only. Entries a skill already has
  in the directory not targeted are carried forward in the manifest untouched,
  and files there are not examined, overwritten or flagged by that run.
- `--pack` is retired. Passing it stops the run with a message saying so.
- Exit codes are unchanged: 0 finished, 1 refusal with nothing written, 2
  finished but something needs a decision.

### The source

- **The pin** is `source.lock` at this repository's root: one full commit hash,
  and comment lines. A comment says the pin moves to claude-config's
  `skills.lock` once that exists. `SKILLS_LOCK_FILE` overrides the path, for
  tests.
- **The clone** is at `SKILLS_REPO`, default `~/Projects/skills`. If the pinned
  commit is not in it, the run stops and prints the `git -C <path> fetch` to
  run. The tool never fetches and never moves the clone.
- **Names** resolve against `primary-set.txt` at the pinned commit. A name is
  the last path segment of a listed folder. A name not listed is refused even if
  a folder with that name exists in the repository. Two listed folders with one
  name stop the run.
- **Bytes** are read from the commit with `git ls-tree` and `git cat-file`,
  never from the clone's working tree and with no filters. A symlink or a
  submodule entry inside a skill folder stops the run. The executable bit is
  kept.
- Nothing is corrected at lay-down time. Corrections live in the source.

### The shared rules block

`--rules` writes one managed block at the top of the project's `AGENTS.md`
(created if absent):

```
<!-- shared-rules:begin -->
<!-- Managed by skillstack bin/lay-pack.sh --rules. Edit the source, not this block. -->
...the contents of the rules source...
<!-- shared-rules:end -->
```

- **Source for this release:** the file at `SHARED_RULES_FILE`, default
  `$SYSTEMS_ROOT/projects/agent-config/shared-rules.md`. `SYSTEMS_ROOT` is
  read from the environment, else from the one `export SYSTEMS_ROOT=` line in
  `~/.config/data-roots.env`. That file is read, never executed. `--rules` alone
  does not need the skills clone.
- **Refused before anything is written:** a source holding an absolute machine
  path, a sync-folder path, a Windows path, a credential or token shape, a
  private key block, an email address, an IP address, a private hostname or a
  40-character hex string. The report gives the kind and the line number, never
  the matching text. A source that itself contains the markers is refused.
- **Re-running** with an unchanged source leaves `AGENTS.md` byte-identical, and
  the manifest too.
- **A changed source** replaces the block in place. Lines outside the markers
  are never read for meaning and never changed, including a missing final
  newline.
- **A hand-edited block** (its hash differs from the manifest's) is reported and
  skipped, and the run exits 2. So is a block the manifest has no record of.
  The way to take the shared version back is to delete the block, markers
  included, and run again; nothing else is needed. This is the same rule as a
  hand-edited skill file, with the deletion standing in for `--forget`.
- **Broken markers** (one without the other, two of a kind, end before begin)
  are an integrity refusal with exit 1.

### The manifest (`schemaVersion: 5`)

```json
{
  "schemaVersion": 5,
  "source": {"repo": "dep0we/skills", "commit": "<pin used by the latest skills run>"},
  "skills": {
    "test-driven-development": {
      "folder": "vendor/superpowers/test-driven-development",
      "commit": "<pin this skill was laid from>",
      "installedAt": "<ISO 8601 timestamp>",
      "files": [
        {"path": ".claude/skills/test-driven-development/SKILL.md", "sha256": "<what the tool last recorded>"},
        {"path": ".agents/skills/test-driven-development/SKILL.md", "sha256": "<what the tool last recorded>"}
      ]
    }
  },
  "rules": {
    "file": "AGENTS.md",
    "source": "$SYSTEMS_ROOT/projects/agent-config/shared-rules.md",
    "sourceSha256": "<sha256 of the rules source>",
    "blockSha256": "<sha256 of the block, markers included>",
    "installedAt": "<ISO 8601 timestamp>"
  }
}
```

- There is no pack concept. The key under `skills` is the skill name.
- `commit` is per skill, because a later run can name only some skills and move
  them to a newer pin while the rest stay where they were. `source.commit` is
  the pin of the latest run that laid skills.
- `rules.source` is a label. A path under `SYSTEMS_ROOT` is written with the
  literal `$SYSTEMS_ROOT` in front, anything else as a bare file name. No
  machine path is ever recorded.
- The per-file `sha256` is the tool's, as in schema 4: it drives hand-edit
  detection and `--forget`, and nothing else.
- Everything in this file is evidence, never authority, under the trust model in
  section 4. `folder`, `commit` and `source` name no fetch target for a reader.

**Licence notices.** When a laid skill's folder has no licence file of its own
(`LICENSE`, `LICENSE.md`, `LICENSE.txt`, `COPYING`), the tool copies the nearest
ancestor folder's licence at the pinned commit into the skill as `LICENSE`, so
`vendor/<set>/LICENSE` reaches every destination directory. It is recorded in
`files` with its hash like any other laid file. The walk stops before the
repository root, and a skill with no ancestor licence gets none.

**Reading a schema 4 manifest.** The tool reads one and lists it (`--list` says
it is schema 4), and `--dry-run` works over it. **A write run does not rewrite
it.** Any write run (`--skills`, `--rules`, `--forget`) against a schema 4
project stops with exit 1, writes nothing, and says the repo was laid by the old
tool, that its own checks read the old format, and that those checks must be
upgraded first (a separate change in that repo) before re-running with
`--upgrade-manifest`. The reason is concrete: one project's setup check reads only
`manifest.packs`, so a schema 5 rewrite drops its checked files to zero with no
error, and a default both-directories lay can create a directory that check
rejects. With `--upgrade-manifest` the write upgrades it: each skill becomes its
own entry, every recorded path and hash is carried over unchanged, and the pack
it came from is kept under `legacy` (pack name, pack version, pack commit,
upstream). A skill with `legacy` and no `folder` is tracked but not re-laid. If
it is listed in `primary-set.txt` it is re-laid from the source and the marker
is dropped. If it is not listed, it stays recorded, runs report it as not named,
and its files are left alone. Schema 1 and unknown versions are still refused.

**What this does to the merge gate in section 4.** Section 4 is the contract for
schema 4, and nothing in it has been rewritten. A reader that implements only
schema 4 reports a schema 5 manifest as `unsupported schema — unrecognised`,
which excludes nothing, so those files get a full review. That is safe and it is
also a regression: a project only becomes schema 5 when someone runs `--upgrade-manifest`,
and its vendored files lose their exclusion from then until the gate learns
schema 5. The gate would take the publishing repository (`dep0we/skills`) as a
constant, the commit from the baseline manifest, the folder from
`primary-set.txt` at that commit rather than from the manifest, and the hashes
from the blobs at that commit. A commit hash needs no tag protection rule. This
is recorded as an update to the ruling in
`docs/decisions/2026-08-20-gate-asks-skillstack-for-shipped-hashes.md` and is
not built here.

## 4. The manifest shape

**Since 2026-10-19 this section is the schema 4 contract.** The tool writes
schema 5 now (section 3a). The trust model below carries over unchanged. The
release tag, `files.json` and the outcomes are schema 4 mechanics for packs that
no longer ship from here, and a gate for schema 5 needs the update described at
the end of section 3a.

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

Every input the gate takes. Each is **constant** (a literal in the gate,
changed only by changing the gate), **authority** (trusted, and it must be
shown why the change under review cannot write it), or **evidence** (read,
compared, reported, never trusted).

This list is meant to be exhaustive, and the claim is load-bearing: each of
the four defeats above was an input nobody had written down. If something the
gate consumes is missing here, add it before relying on the table.

**Constants, compiled into the gate:**

| Input | Note |
| --- | --- |
| Publishing repository host, owner, name | See below; literal values given |
| API base and the URL shape of every request | Never assembled from manifest values |
| The reachability request | Exact request named under "Resolving the release" |
| Manifest path `.vendored-skills.json` | A configurable path is a redirect |
| Path of the published map, `packs/<pack>/files.json` | Interpolated; same class as the tag, so same grammar |
| Release tag grammar `<pack>-v<version>` | With the naming grammar below |
| Allowed location prefixes | `.claude/skills/`, `.agents/skills/` |
| The path normalization steps | Both sides must normalize identically or lookups miss |
| Hash algorithm, SHA-256 over object content | Not a git object id; see below |
| Schema version this gate implements, 4 | The gate's own, not read from anywhere |

**Authority:**

| Input | Source | Why the change cannot write it |
| --- | --- | --- |
| Target ref of the pull request | The hosting platform | Not in the repository; see the caveat below |
| Baseline manifest: `packVersion`, `skills`, `files` paths, pack names, `schemaVersion` | The target commit | Already merged and reviewed |
| Release tag | Derived from baseline name and version | Never read from a manifest |
| `files.json` and its hashes, and its own `schemaVersion` | The pinned repository at that tag | Different repository, not writable from here |
| The gate's own code and workflow | The guardrail toolkit's release | See the caveat below |

**Evidence, never trusted, whichever manifest it appears in:**

| Input | Source |
| --- | --- |
| Proposed manifest, in full | The commit under review |
| `source`, `packCommit`, `upstream.*`, `installedAt` | **Either** manifest, baseline included |
| Per-file `sha256` | Either manifest |
| Head commit of the pull request | The hosting platform |
| Content of each file being checked | The commit under review |

**Never read:** the working tree as checked out.

**The baseline manifest is not authority as a whole file, and that distinction
is the point of splitting the rows.** Only the identity fields listed above
are trusted, and only for scope and for deriving the tag. `source`,
`packCommit`, `upstream` and `installedAt` are evidence **even in the
baseline**, because they were written by some earlier change and are carried
forward unexamined. A gate that trusted the baseline file as a unit, and then
took a fetch target from `source`, would have reintroduced defeat four one
merge later. **No field of any manifest, baseline or proposed, ever names,
contributes to, or redirects a fetch target.** `upstream.repo` is provenance
for a human to read, never something to fetch.

**Two inputs are authority the gate cannot verify for itself**, named rather
than omitted, because an omitted input is what produced defeat four. The
target ref comes from the hosting platform, and a pull request author chooses
what to target, so a chain of pull requests can end at a branch whose baseline
that author wrote; what contains it is not this mechanism but the requirement
that the change still reach the protected branch through a review against
*that* branch's baseline. The gate's own code and workflow live in the project
repository, and a change editing them defeats every rule at once; that is the
guardrail toolkit's existing problem, already answered there by pinning the
gate script by digest. Neither is solved here.

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

A pack name or version failing its rule is an integrity failure, and it has
**one consequence, the same as every other integrity failure: the whole
manifest is rejected and nothing is excluded for any pack.** An earlier
revision said "exclude nothing for that pack" here and "reject the whole file"
under the integrity rules, which are different behaviours for one condition,
and two builders would have split on it. Manifest-wide rejection is the
stricter of the two and matches how every other integrity rule already
behaves.

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

**`.cursor/skills/` is not an allowed location in schema 4.** The re-measurement
this rule was waiting on was run on 2026-08-23 and is recorded in
`docs/decisions/2026-08-23-skill-directories-measured.md`. It confirmed the
conclusion and **corrected the reason**, which an earlier revision of this
document stated wrongly.

Measured: Claude Code loads `.claude/skills/` only. Codex loads
`.agents/skills/` only. **Cursor loads all three, `.cursor/skills/` included,
and does so both locally and as a cloud agent.** So two directories cover every
reader, and `.cursor/` is redundant because Cursor reads a **superset**, not
because Cursor ignores it.

The earlier wording said Cursor and Codex both read `.agents/skills/`, "which
makes a third copy redundant". True, and not the whole fact. The two readings
are indistinguishable locally and would have been opposite for a cloud agent: a
superset says nothing about which directory cloud reads, while "Cursor ignores
`.cursor/`" would have settled it. The wrong reason is corrected here rather
than left standing behind a surviving conclusion, because the cloud question is
the next thing this rule was consulted for.

**The cloud case is measured, not assumed, and it agrees.** A cloud agent given
a prompt containing no unusual string fired the skills in `.claude/`, `.agents/`
and `.cursor/`, and did not fire an identical decoy skill placed in a directory
no loader reads. All four were equally findable, so a browsing agent returns
four and a loader-driven agent returns exactly three. That also settles the
premise underneath this whole approach: **a committed skill reaches a cloud
agent and fires unprompted.**

Anything else — including project source, configuration, or a skill directory
not named in `"skills"` — is not pack content for this mechanism even if
someone added a matching hash.

### Resolving the release

**The publishing repository is a constant in the gate, and here it is:**

    host   github.com
    owner  dep0we
    name   skillstack

The gate carries those three as compiled-in literals, alongside the API base
`https://api.github.com` and the URL shapes it builds from them. Changing any
of them is a change to the gate, reviewed as code. Nothing in a project
manifest reaches them, contributes to building them, or redirects them.

**Naming them here is deliberate, and an earlier revision's silence was a
defect, not discretion.** A contract that does not say which repository to pin
cannot be implemented the same way twice: each builder supplies the three
strings from memory or from a README, and the result is two gates that
disagree about their own root of trust while the project can redirect neither.
The values disclose nothing, since this document is served from that
repository at that URL.

**The release tag** is `<pack>-v<packVersion>`, built from the pack name and
`packVersion` **taken from the baseline manifest**, after both pass the naming
grammar. So pack `superpowers` at `0.1.0` is `refs/tags/superpowers-v0.1.0`.
The gate resolves that exact ref. It does not accept a tag name from any
manifest, does not fall back to a branch, and does not fall back to
`packCommit`.

**The pack-cutting step creates an annotated tag. The gate accepts either an
annotated or a lightweight tag and must peel.** Resolving a ref returns an
object that is either a tag object (annotated) or a commit (lightweight); an
annotated tag must be dereferenced to the commit it points at before that
commit is used or reported. A gate that skipped peeling would report a tag
object's own sha as the release commit, which names nothing anyone can check
out. Accepting both and peeling is stated because "annotated" alone leaves a
builder to guess what to do with the other kind, and refusing the other kind
outright would fail a release over a detail invisible in the published
content.

**Tags are cut on the merged commit, after merge, never before.** This
repository publishes by squash merge, and a squash merge creates a commit that
does not exist until the merge happens. A tag cut on a pre-merge commit names
an object the merge orphans. Not hypothetical: rebuilding this repository's
history on 2026-08-19 orphaned every commit sha existing clones held, and an
unauthenticated fetch of one of those shas returns HTTP 404, the same status
an unreachable repository returns.

**The tag protection rule, and exactly how far it goes.** A tag is only
immutable if the host enforces it. This repository carries a repository
ruleset, "release tags are immutable", created 2026-08-23 on the maintainer's
authorisation, targeting tags matching `refs/tags/*-v*` and forbidding
deletion, non-fast-forward and update, with an empty bypass list.

**It stops every change that arrives through git, and it does not stop an
administrator who turns it off first.** Measured, not assumed: a probe tag was
created, and attempts to move and delete it were refused with
`Cannot update this protected ref` and `Cannot delete this tag`; the probe was
then removed by setting the ruleset's enforcement to disabled, deleting it,
and setting enforcement back to active. So `bypass_actors: []` and
`current_user_can_bypass: never` are both true and both describe the git path
only.

This is written down rather than left as folklore because "immutable" without
it reads as stronger than it is, and somebody will eventually build on the
stronger reading. What it means in practice: a mistaken release tag can only
be withdrawn by deliberately switching the protection off, which is an act
visible to everyone and one that trains people to treat the rule as advisory.
So a release tag is cut once, after its content is merged and verified, and
never speculatively.

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

**Provenance note on the commits this map names.** This repository's history
begins at a single root commit because it was rebuilt on 2026-08-19 to strip
private paths and names before being published. Every sha predating that
rebuild is unresolvable, which is the defect that made the pack version rather
than a commit the lookup key. A `packCommit` recorded here is therefore always
post-rebuild, and a reader who finds history starting abruptly is looking at
that event and not at a truncated clone.

**Keys are pack-relative, not project-relative.** This keeps the published
list independent of how many directories a project lays skills into: a project
that took two directories and one that took three check against the same map,
and changing the layout cannot invalidate a published pack. A project path
maps to a key by stripping the `.claude/skills/` or `.agents/skills/` prefix.
One fetch per pack, not one per file.

**`files.json` has its own `schemaVersion` line, unrelated to the manifest's.**
It is `1`, and that is current and correct. The manifest's schema rules do not
apply to it: a gate that took "reject any `schemaVersion` other than 4" from
the manifest section and applied it here would refuse every release forever,
while reporting a source problem. The two numbering lines move independently
and neither constrains the other.

A fetched `files.json` whose `pack` or `packVersion` does not match the tag it
was fetched under is `release incomplete — map disagrees`, not a hash source.
One that is absent or unparseable is `release incomplete — no map`.

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

**The order is fixed, and validation comes before identity.** An invalid
baseline cannot be compared against anything, so comparing first would mean
reading fields that the next step is about to reject.

1. **Read the baseline manifest** at the actual target commit being merged
   into — not the merge base, not the working tree. For a merge from another
   branch these differ, and the target commit is the one whose contents a
   merge actually accepts. This is the sole source of exclusion scope and pack
   identity.
2. **Validate the baseline** against the integrity rules, which include the
   naming grammar and the allowed locations. Failure ends here with
   `manifest rejected`, naming the rule. Nothing later runs.
3. **Read the proposed manifest** at the commit under review, as evidence, and
   compare each baseline pack against it. A pack absent from the proposed
   manifest, or differing per the definition below, is `identity changed` and
   excludes nothing for that pack. A legitimate pack upgrade therefore gets
   exactly one full review, which is the correct price: an upgrade changes the
   content being trusted.
4. **Probe the pinned repository for reachability**, then resolve the derived
   tag, then fetch and validate `files.json` at it. Three separate results.
5. **Hash and compare** each path in the baseline pack's `files`, reading the
   object at the commit under review, per the section above.

**What "differs" means, exactly.** For a baseline pack, compare against the
proposed manifest's pack of the same name: `packVersion` as a string;
`skills` as a **set** of strings; and the `files` entries as a **set of
normalized paths**. List order is not a difference in either case, because
nothing about ordering changes what is being trusted, and treating a reorder
as an upgrade would make the gate noisy in a way that trains people to ignore
it.

**The per-file `sha256` is explicitly excluded from this comparison.** It is
tool-owned evidence that no gate reads. If a change edits `sha256` and leaves
content alone, the content still matches the published map and is still
excluded, correctly. If it edits content, the hash of the object fails against
the published map regardless of what `sha256` claims. So a `--forget` re-record
does not spuriously turn exclusion off, and a doctored `sha256` buys nothing.

**Three cases that look like "nothing to do" and are not:**

- **Deleting the manifest, or replacing it with one whose `packs` is empty**,
  while the baseline had packs, is `identity changed` for every baseline pack.
  `not applicable` is reached only when the **baseline** has no packs.
- **A baseline that is schema 4 with no `packs` key at all** is a missing
  required field: `manifest rejected`, never `not applicable — empty packs`.
  The two readings differ in what they permit, and the permissive one excludes
  files on the strength of a malformed file.
- **A proposed manifest that is present and unparseable** cannot be compared,
  so it is `proposed manifest unreadable` and excludes nothing. It is not
  `manifest rejected`, which is about the baseline. **An absent proposed
  manifest is not this case**; deletion is `identity changed`, per the first
  bullet above. The line between them is whether the file is there: present
  and unreadable is one condition, gone is another, and each has exactly one
  outcome.

### The outcomes, which must never print the same result

A check that could not run and a check that found nothing wrong are the same
clean line unless the tool makes them different.

**The rule is not that each outcome has one cause; it is that no two
conditions ever produce the same line.** An earlier revision claimed one cause
per outcome and then listed four outcomes that bundle several, which is a
claim the document itself contradicted. Some conditions genuinely share a
remedy and differ only in detail, and splitting those into separate outcome
names would be ceremony. What must hold instead: **every outcome names the
specific condition that produced it**, in its output, in words an operator can
act on. `manifest rejected` naming the failed rule and the offending value is
one outcome doing that job; `manifest rejected` on its own is not.

Kit words these lines. That it must be able to tell every condition apart is
contract, not an implementation detail left to the reader.

**Nothing to do:**

- **`not applicable — no manifest`** — no `.vendored-skills.json` at the
  target commit.
- **`not applicable — empty packs`** — present, schema 4, valid, with `packs`
  present and containing no entries. A `packs` key that is **missing** is a
  different condition and is `manifest rejected`.
- **`unsupported schema — legacy`** — the baseline has no `schemaVersion`, or
  has `1`. This is what every real manifest holds today. Not an error and not
  a pass; outside this mechanism entirely. Reports the version found.
- **`unsupported schema — unrecognised`** — the baseline names a version this
  gate does not implement (anything not 1 and not 4, including a future 5).
  Distinct from legacy because the remedies differ: legacy needs the project
  re-run through the tool, unrecognised needs the gate upgraded.

**Refused, and why:**

- **`manifest rejected`** — the **baseline** failed an integrity rule. Names
  the rule and the offending value. This covers every rule in the integrity
  list, including the naming grammar, the allowed locations and a missing
  required field; they share this outcome because they share a remedy, and
  they are told apart by the named rule in the output, which is required.
- **`proposed manifest unreadable`** — the manifest **exists** at the commit
  under review and is not valid JSON, so no comparison was possible. Distinct
  from `manifest rejected`, which is about the baseline. A manifest that is
  **absent** is not this outcome; see `identity changed`.
- **`identity changed`** — the proposed manifest differs from the baseline for
  this pack, per the definition above. Names which field, and for a set
  difference, which members. **A deleted manifest reaches this outcome**, and
  neither `not applicable` nor `proposed manifest unreadable`: going from
  present to absent is the most complete change of identity there is, and it
  is a more specific statement about what happened than "could not read it."
  Stated here so the two are not re-split by a later reader.
- **`lookup failed`** — the reachability request against the pinned repository
  did not return its expected success. The source could not be consulted.
  Never conflated with any answer the source might have given.
- **`release not found`** — reachability proved, and the derived tag does not
  exist. A missing release, not a missing source.
- **`release incomplete — no map`** — the tag resolves and `packs/<pack>/files.json`
  is absent or unparseable at it.
- **`release incomplete — map disagrees`** — the map parses and its `pack` or
  `packVersion` does not match the tag it was fetched under. Separate from
  `no map` because this one means the release is internally inconsistent,
  which is a publishing bug here rather than a missing artifact.

**The reachability request, named exactly, because "a request that returns a
distinct success" forks two builders.** The gate issues
`GET https://api.github.com/repos/<pinned owner>/<pinned repo>` and requires
HTTP 200. Anything else, including any network failure, is `lookup failed`.
Only after that 200 may a 404 on the tag request be read as
`release not found`.

An anonymous 404 covers a missing tag, a private repository and a repository
that does not exist, which is why the tag request alone cannot carry this.
The gate does not try to tell a private repository from an absent one: an
anonymous caller cannot, both mean the source is unusable, and neither is
actionable differently.

**Per file:**

- **`in scope — hash mismatch`** — the path is in the published map and the
  computed SHA-256 differs.
- **`in scope — not published`** — the path is in the baseline `files` and
  absent from the published map.
- **`in scope — not a regular file`** — the entry at that path, at the commit
  under review, is a symlink, gitlink or submodule.
- **`in scope — deleted`** — the baseline names the path and the commit under
  review has no entry for it.
- **`excluded`** — every check passed. Reports the count, the pack, the
  version, and the release commit the tag resolved to. "Why was this excluded"
  answers with a name, a version and a resolved commit, never "a manifest said
  so."

A force-pushed pull request is re-evaluated against its new head commit. A
prior result is never reused, because the commit it described no longer
exists.

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

Both are in `bin/` in this repository, and the originals in the maintainer's
personal config repository are untouched. **Both now refuse to run**, with a
message naming `bin/lay-pack.sh`. They were previously described here as
scripts that "should not be run", which is a preference rather than a control:
`vendor-skills.sh` in particular clones upstream's latest default branch and
writes a schema 1 manifest straight over a schema 4 one, so someone running it
by habit destroys the record a gate resolves published hashes against. They
are kept, unrun, as the readable reference for what was carried forward and
what was not.

The refusal is unconditional. There is deliberately no environment override
"so the tests can still exercise the old path": a hook that lets a test skip a
guard becomes the only route through once the guarded path rots, and then
every test takes it and the guard has never run.

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

1. **Settled: the tag protection rule exists.** This item asked for one and
   said the repository had no tags and no rulesets, which stopped being true
   on 2026-08-23 and contradicted section 4, which describes the rule as in
   place. Re-checked against the host on 2026-08-23 rather than taken from
   the earlier report: the ruleset "release tags are immutable" is active,
   targets `refs/tags/*-v*`, forbids deletion, non-fast-forward and update,
   and has an empty bypass list with `current_user_can_bypass: never`. The
   first release tag, `superpowers-v0.1.0`, is cut and annotated and peels to
   a commit on `main`. Section 4 states how far that protection goes and
   where it stops, which is at an administrator who disables it first.

   The manifest shape itself is **settled** and no longer an open question.
   The maintainer ruled on 2026-08-20 that the gate asks `skillstack` for the
   shipped hashes rather than trusting the copy in the repository under
   review, and that a human reading the manifest diff is explicitly not the
   control. Section 4 is written as a contract on that basis.

2. **The filename is settled: `.vendored-skills.json`.** It was listed here
   as open in earlier revisions while section 4 simultaneously pinned it as a
   gate constant, which is a contradiction, and the permissive reading of it
   is defeat four applied to the filename: a configurable manifest path lets a
   change point the gate at a different file. It stays, both for continuity
   with the three things that already reference it by that name and because a
   pinned constant is what the trust model requires. Nothing in section 4
   remains open.
