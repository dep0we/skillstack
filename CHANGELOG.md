# Changelog

Every notable change to this repository is listed here, newest at the top.
This file follows the Keep a Changelog format
(https://keepachangelog.com), kept deliberately simple.

An empty `[Unreleased]` section is left genuinely empty, with no placeholder
text under it.

## [Unreleased]

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
