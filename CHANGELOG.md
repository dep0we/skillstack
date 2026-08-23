# Changelog

Every notable change to this repository is listed here, newest at the top.
This file follows the Keep a Changelog format
(https://keepachangelog.com), kept deliberately simple.

An empty `[Unreleased]` section is left genuinely empty, with no placeholder
text under it.

## [Unreleased]

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
