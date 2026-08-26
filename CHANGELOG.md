# Changelog

Every notable change to this repository is listed here, newest at the top.
This file follows the Keep a Changelog format
(https://keepachangelog.com), kept deliberately simple.

An empty `[Unreleased]` section is left genuinely empty, with no placeholder
text under it.

## [Unreleased]

- **`--list` validated no manifest path at all, and exited 0 saying so.** The
  call to `assert_manifest_paths_ok` sat 93 lines above the definition. Bash
  resolves a function name when the call runs, not when the file is parsed, so
  this was never a syntax error: the shell printed `command not found` to
  stderr, SKIPPED the call, and left the status at 127, which nothing in the
  script reads. `--list` then printed an ordinary listing and exited 0 over a
  manifest recording `../../../etc/passwd`. Present since `bin/lay-pack.sh` was
  added on 2026-08-23, so `--list` had never checked a path. The definitions
  now sit above every call site, and the move is content-identical: sorting
  both files and diffing them produces nothing.
- **The suite now catches the class, not this one instance.**
  `test/functions-are-defined-before-use.test.sh` discovers the function names
  in every script under `bin/` and `test/` and refuses any name mentioned above
  its own definition. It discovers those names rather than being handed a list,
  because a list only ever holds the names somebody remembered, and it proves
  it can fire on a known-bad file before any clean verdict from it is read.
  Nothing else catches this: `bash -n` accepts the file, and shellcheck 0.11.0
  reports nothing at its defaults or at `--enable=all`. Both were measured
  against the broken file rather than assumed.
- `run_lay` in `test/helpers.sh` now fails any test whose run leaves
  `command not found` anywhere in the tool's output. That turns every test file
  that runs the tool into a detector for the same shape, for one line and no
  list of names to keep current.
- `test/refuses-doctored-manifest-paths.test.sh` now puts its five doctored
  paths through `--list` as well as through a lay-down. Every check in that file
  passed the whole time the defect existed, because all of them exercised the
  lay-down path, where the same call sits below the definition and ran.
- Measured against every `.vendored-skills.json` on the maintainer's machine
  before merging: the four schema 4 manifests list exactly as they did, and the
  one schema 1 manifest still exits 1 on the schema check, which runs earlier
  and was never affected. Validation that has been dead since it was written
  starts rejecting nothing that currently works.
- **Adds `bin/lay-pack.sh`, the layering tool.** It copies selected skills from
  the corrected pack committed here into a project repository and records what
  it wrote in a schema 4 `.vendored-skills.json`. It never clones upstream,
  never reaches the network, and never corrects anything at lay-down time.
  `--skills` is required and there is deliberately no way to say "all of them":
  taking every skill is how one project ended up with 165 of its 194 tracked
  files being skill copies, and a default of "everything" would recreate that
  on the first hurried run.
- Carries forward, unchanged, the mechanics from `vendor-skills.sh` that were
  already right: a per-file sha256 recorded at write time, a refusal to
  overwrite a file whose on-disk hash has moved, a refusal to touch a file the
  manifest never recorded, `--forget` as the single deliberate override that
  deletes nothing and adopts unrecorded files, orphans reported and never
  deleted, `--dry-run`, `--list`, and exit 2 for finished-but-skipped.
- **Refuses to lay down while the pack tree is dirty.** `packCommit` would
  otherwise name a commit whose content is not what was copied, and the
  disagreement surfaces much later, in another repository, as a hash mismatch
  with no visible cause.
- **Validates every path in a manifest as it is read**, against that pack's own
  recorded skills. Paths this run builds cannot be wrong; entries carried
  forward for a skill not named in `--skills` come off disk and can be. An
  earlier arrangement checked only what survived to be written, and a path
  malformed enough was quietly dropped instead of refused, which fails safe and
  fails silently.
- Reports a skill recorded in the manifest and not named in `--skills` rather
  than dropping it, and exits 2. Silent narrowing would leave its files on disk
  and unrecorded, which is the exact state every future run skips and
  `--forget` exists to dig people out of.
- Prints a distinct line when a run placed nothing at all, so "finished, wrote
  nothing" cannot read like "finished, everything was already correct".
- **Adds `test/`, a suite of 14 test files and 162 checks, and `test/run.sh`,
  which fails rather than reporting an empty pass when it discovers no tests.**
  Every guard above was proven by mutation, with the unmutated control run
  first: apply the mutation, show it landed before reading any result, run the
  test, require it to fail, restore by file copy. That includes the three
  controls added when `--list` was found to be validating nothing.
- **Both superseded scripts now refuse to run**, naming the replacement.
  `vendor-skills.sh` clones upstream's latest default branch and writes a
  schema 1 manifest over a schema 4 one, so leaving it merely discouraged left
  a real hazard one habit away. The refusal is unconditional: no environment
  override, because a hook that lets a test skip a guard becomes the only route
  through once the guarded path rots.
- **Re-measured which skill directories each reader actually loads**, which the
  specification had promised and was carrying forward from an earlier trace.
  Recorded in `docs/decisions/2026-08-23-skill-directories-measured.md`. The
  conclusion held, two directories rather than three, and **the stated reason
  was wrong and is corrected**: Cursor loads all three directories, so
  `.cursor/skills/` is redundant because Cursor reads a superset, not because
  Cursor ignores it. The two readings are identical locally and would have been
  opposite for a cloud agent, which is the next thing the rule was consulted
  for.
- **Measured the Cursor cloud case**, which had never been instrumented and is
  the premise the whole approach rests on. A cloud agent, given a prompt with no
  unusual string in it, fired the skills in `.claude/`, `.agents/` and
  `.cursor/`, and did not fire an identical decoy skill in a directory no loader
  reads. All four were equally findable, so a browsing agent returns four tokens
  and a loader-driven agent returns exactly three: **the decoy is what carries
  the proof, not the tokens.** Cursor cloud behaves exactly like local Cursor, so
  two directories is correct there too, and **a committed skill reaches a cloud
  agent and fires unprompted.**
- Records that the first two cloud probe designs were void, and why. The first
  put the trigger words in the prompt, handing a searching agent a perfect
  query. The second carried a README documenting the instrument, including a
  table of every token against its directory, so **the fixture contained its own
  answer key**. Both were more elaborate than the design that worked; the third
  succeeded because of its control, not its cleverness.
- Records that asking a model to list its own skills failed here as a **false
  negative**, reporting "NONE AVAILABLE" for a skill that demonstrably loaded.
  The same instrument was already known to fail as a false positive. The
  replacement never asks the model about skills: it puts an unguessable token
  in the part a loader injects and reads the tool-call ordering, with an empty
  control showing what searching looks like when nothing was injected.
- Settles the stale open question about tag protection, which said this
  repository had no tags and no rulesets while section 4 described the rule as
  in place. Re-checked against the host rather than taken from a report.

- Publishes `packs/superpowers/files.json`, the hash map a merge gate resolves
  a release against: schema 1, 52 entries covering every tracked file under
  `packs/superpowers/skills`, keys pack-relative, hashes SHA-256 over the
  content git records at `8151d9b`. Generated from git objects rather than the
  working tree, so it matches what a gate computes, and cross-checked against
  `shasum` as an independent tool with a deliberately tampered entry as the
  control. `packCommit` is `83f2e44`, the commit the corrected pack content was
  cut at, verified as an ancestor of `main` with an empty `packs/` diff since.
- Records the tag protection rule that now exists, and **states its limit**: it
  refuses every change arriving through git, including from an administrator
  using git, and it does not stop an administrator disabling the ruleset first.
  Measured with a probe tag rather than assumed. An earlier reading of
  `bypass_actors: []` as absolute was wrong, and "immutable" without the
  qualifier reads stronger than it is.
- Adds a provenance note explaining why this repository's history starts at a
  single root commit, so a later reader does not mistake the 2026-08-19 rebuild
  for a truncated clone.

- Third review round on the section 4 contract, and it converged. No fifth
  defeat, none of the four returned, and closing the previous fourteen
  introduced nothing. **One finding, ruled non-blocking, now closed.** A
  deleted manifest was assigned two outcomes: `identity changed` in the
  procedure and `proposed manifest unreadable` in the outcome list, each
  restated in the other's text. One condition, two labels, so two builders
  would ship different lines. It was ruled non-blocking because a blocking
  finding has to name a concrete failure, and both readings refuse to exclude:
  the verdict is identical and correct in either gate, and only the printed
  name differs. Resolved toward `identity changed`, because going from present
  to absent is the most complete change of identity there is and is a more
  specific statement than "could not read it", leaving
  `proposed manifest unreadable` to mean the file exists and will not parse.
  Both outcomes now say which case is theirs and which is not, so a later
  reader does not re-split them.

- Second review round on the section 4 contract: fourteen findings, none of
  them a live defeat. **The inventory claimed to be exhaustive and was not**,
  missing seven inputs including the published map's own fetch path, the
  location prefixes, the normalization steps and the reachability request.
  None was writable-then-trusted, so nothing was exploitable, but a false
  completeness claim is what let each of the four earlier defeats arrive, so
  the list is completed and the claim is now stated as something to maintain.
  **"Baseline manifest content" was classed authority as a whole file** while
  four of its own fields were classed evidence, so a builder reading the table
  top-down would trust `source` and take a fetch target from a field an
  earlier merged change wrote. The rows are split: only the identity fields
  are authority, and provenance fields are evidence in the baseline too. Pins
  the publishing repository by naming host, owner and repository as literals,
  because a contract that cannot be implemented identically twice is not doing
  its job. Names the reachability request exactly rather than describing it.
  Fixes the filename, which the table pinned as a constant while section 7
  still listed it as open, the permissive reading being the same defeat
  applied to the manifest path. Settles validate-before-identity ordering,
  which the numbered steps and the integrity heading contradicted. Makes a
  naming-grammar failure reject the whole manifest, matching every other
  integrity rule, where one passage had said exclude-nothing-for-that-pack.
  Defines what "differs" means, as sets with list order irrelevant and the
  tool's own `sha256` excluded, and says why excluding it is safe. Adds
  outcomes for an unreadable proposed manifest and for a schema 4 baseline
  whose `packs` key is missing rather than empty, the second reading of which
  would have excluded on a malformed file. Gives `files.json` its own
  `schemaVersion` line, since a gate applying the manifest's rule to it would
  refuse every release forever. States that the gate accepts an annotated or
  lightweight tag and must peel. Drops the one-cause-per-outcome claim, which
  the document contradicted four lines later, and replaces it with the
  property actually required: no two conditions ever print the same line, and
  every outcome names its condition.

- Cross-family review round on the section 4 contract: sixteen findings, of
  which two would each have made the mechanism useless. **The publishing
  repository was never named** anywhere in the document, so a builder needed a
  URL and the only repo-shaped fields available live in the project's own
  manifest; a change could then point the lookup at a repository it controls.
  That is the fourth time this design has been defeated by an unlisted input
  being read as authority, and it is answered by an explicit **input
  inventory** that classes every input as constant, authority or evidence,
  including the transport, the tag name, the manifest path, the target ref and
  the gate's own code. **The hash arithmetic was wrong:** `files.json` stores
  a SHA-256 of file bytes while the text said to hash the git blob, which is a
  SHA-1 over `blob <len>\0` plus content. Measured, and different in length,
  algorithm and input, so a gate built from the old wording would have matched
  nothing, excluded nothing, and reported it as nothing needing exclusion. The
  intent (never read the working tree, which a symlink or filter can divert)
  is kept and the arithmetic corrected: read the object's content at the
  commit under review, then SHA-256 those bytes. Adds a naming grammar so
  `<pack>-v<version>` cannot collide, a reachability probe so `lookup failed`
  and `release not found` are distinguishable behind an anonymous 404, and
  `release incomplete` for a tag whose map is missing or disagrees with it.
  Splits the outcomes so each has exactly one cause, including a real outcome
  for `schemaVersion: 1`, which is what every manifest in existence holds
  today and previously had none. Requires the identity fields at integrity
  time, since a pack without `packVersion` derived the tag `superpowers-v`.
  Stops claiming every mechanism implements one of the three trust rules,
  which was false.

- Section 4 of `docs/SPEC.md` rewritten as a settled contract rather than a
  proposal, implementing the maintainer's 2026-08-20 ruling that the merge
  gate asks this repository for shipped hashes instead of trusting the copy in
  the project under review. Schema moves to version 4: `shippedSha256` is
  removed rather than renamed, leaving one hash per file that belongs to the
  layering tool and that no gate reads. Exclusion scope now comes from the
  target branch's manifest, never the pull request's, because a change can
  leave the version fields untouched and add paths to the `files` array.
  Shipped hashes resolve through an immutable annotated tag named
  `<pack>-v<packVersion>`, derived from pack name and version and never read
  from the manifest, against a new published `packs/<pack>/files.json` whose
  keys are pack-relative so the layout a project chooses cannot invalidate a
  release. `packCommit` is audit-only: this repository's history was rebuilt
  into a single root commit on 2026-08-19, so a recorded sha is not a durable
  reference. Adds git-blob hashing with symlink and gitlink rejection, merge
  and force-push handling, and five outcomes that must each print differently
  (`not applicable`, `lookup failed`, `release not found`, `in scope`,
  `excluded`). Narrows allowed locations to `.claude/skills/` and
  `.agents/skills/`, dropping `.cursor/skills/`, flagged as resting on a
  carried-forward measurement that DAR-157 will re-run. Fixes the manifest
  example, which keyed a pack by a skill name (`test-driven-development`)
  instead of the pack name (`superpowers`), teaching the wrong lookup key for
  the field a gate resolves a release by. Records the ruling and its
  consequences in `docs/decisions/2026-08-20-gate-asks-skillstack-for-shipped-hashes.md`.
- Section 7's first open question is now closed by that ruling and replaced by
  the one thing still outstanding: this repository has no tags and no tag
  protection rule, and a tag is only immutable if the host enforces it.
  Creating that rule is a repository setting and therefore the maintainer's.

- Last spec review round: stated plainly what a `shippedSha256` match does and
  does not prove (bytes match a number in the manifest, not proof the pack
  shipped them), that `shippedSha256`, `files`, and `"skills"` are all
  writable by the same pull request, what the second hash field actually
  stops, and that catching a hostile rewrite needs hashes the pull request
  cannot edit or a human reading the manifest diff as the review of excluded
  files. Marked the source of trustworthy shipped hashes as an open question
  that must be settled with the guardrail toolkit before any gate excludes on
  this manifest. Fixed the allowed-location rule (skill directory is the first
  segment after the prefix, not the fourth path segment). Fixed the section 6
  leftover claiming `soften-tdd.py` is scoped to one file. See `docs/SPEC.md`.
- Reworked the proposed manifest shape to schema version 3: each file entry
  now carries both `shippedSha256` (what the pack shipped, never updated by
  `--forget`) and `sha256` (what the tool last recorded on disk). Merge gates
  must exclude only when on-disk content matches `shippedSha256`. Added path
  normalization, allowed-location rules limiting entries to named skills under
  `.claude/skills/`, `.cursor/skills/`, and `.agents/skills/`, and withdrew
  the single-hash schema 2 proposal. Corrected factual claims about
  `vendor-skills.sh` and `soften-tdd.py`, aligned delete-instruction file
  counts, removed identifying paths and project names from the spec, and
  corrected the decision record's claim about install-time patching. See
  `docs/SPEC.md` and
  `docs/decisions/2026-08-19-store-a-corrected-snapshot.md`.
- Adversarial pack review round 2 (2026-08-20): fixed start-server.sh so the
  pid guard reads the prior instance id from .active-pid/.active-server-id
  before writing a new one; moved the no-guess test-command rule out of a
  bash fence in using-git-worktrees; updated the brainstorm-start-server-safety
  ledger entry to match. Twenty corrections total (unchanged count).
- Adversarial pack review fixes (2026-08-20): restored project-b merge
  losses in writing-skills templates (Delete 200 lines scenario, Red Flags
  Do not delete code closer), aligned corrections.json claims with files,
  scoped pressure-test fixtures and examples, removed guessed test commands
  from using-git-worktrees, fixed subagent example workspace wording,
  hardened start-server.sh pid handling, removed shell from
  BRAINSTORM_OPEN_CMD, and made find-polluter.sh require TEST_CMD with safe
  quoting. Five new corrections.json entries; twenty total.
- First corrected pack: `packs/superpowers/` at version 0.1.0, pinned to
  upstream commit b36e0829c6d0140e93cfef2ca599b1b07d4a7797. Holds one
  reconciled snapshot of all fourteen skills plus `corrections.json`,
  `pack.json`, `THIRD-PARTY-NOTICES.md`, and `writing-skills/package.json`.
  Corrections merge the three project review trees from 2026-08-19.
- Ruled how pack content is held: a corrected snapshot committed here, plus
  a separate record of the corrections. A fork and install-time patching were
  both considered and rejected. See
  `docs/decisions/2026-08-19-store-a-corrected-snapshot.md`.

### Added

- Initial scaffold: `README.md`, this file, `.gitignore`, and `docs/SPEC.md`
  specifying what a skill pack is, what the tool will do, and the proposed
  manifest shape a project carries after a pack is layered in.
- `bin/vendor-skills.sh` and `bin/soften-tdd.py`, copied unmodified from
  the maintainer's personal config repository for reference. See
  `docs/SPEC.md` for which parts each one carries forward and which are
  superseded.
