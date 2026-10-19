# Skills come from one pinned source, dep0we/skills

- **Status:** accepted
- **Date:** 2026-10-19
- **Approved by:** the maintainer
- **Supersedes:** the source half of `2026-08-19-store-a-corrected-snapshot.md`.
  That record's reasoning about corrections (review the finished bundle once,
  keep the corrections as a record) still holds. It now applies to the
  `dep0we/skills` repository instead of to `packs/` here.
- **Reversible:** yes. The lock file, the clone path and the source reader are
  small. Reversing means re-pointing the tool at `packs/`, which is still in the
  repository.

## Context

`lay-pack.sh` used to copy skills out of `packs/<name>/` in this repository.
Since then the maintainer's machines have moved to installing skills from one
place: `dep0we/skills`, at a commit that config-sync pins. That repository holds
the vendored sets (superpowers with this repository's corrections, OpenSpec,
Jev), carried skills and his own, and a `primary-set.txt` that lists exactly
which folders get installed.

Two sources for the same skills means two copies that drift. A project would
carry a skill from `packs/` while his machines run a different one from
`dep0we/skills`, and nothing would say which was current.

## Decision

`lay-pack.sh` copies skills only from `dep0we/skills`, at the commit in
`source.lock`.

- **The pin lives in `source.lock`** at this repository's root, as one commit
  hash plus comments. It moves to claude-config's `skills.lock` once that
  exists, so there is one pin for everything and this file goes away.
- **The clone is `SKILLS_REPO`**, default `~/Projects/skills`. If it lacks the
  pinned commit, the tool stops and prints the `fetch` command. It does not
  fetch. A tool that quietly moves the clone makes the pin mean whatever the
  network said that day.
- **Names come from `primary-set.txt` at the pinned commit**, by the last path
  segment of a listed folder, which is how config-sync names them. A folder in
  the repository that is not listed is not installable.
- **Files are read from the commit**, not the working tree. A clone can be dirty
  or on another branch.
- **`--pack` is retired** and stops with a message saying so. `packs/` stays in
  the repository, marked superseded (`packs/README.md`), because schema 4
  manifests and the schema 4 gate contract refer to it.
- **The manifest is schema 5.** No pack concept. Each skill records its source
  folder and commit, each file its hash. Schema 4 manifests are read and listed,
  and upgraded only on request (see the next item), with every recorded hash kept
  so hand-edit detection survives the upgrade.
- **A write run never rewrites a schema 4 manifest by itself.** A project's own
  setup check can read only the schema 4 shape (headwaters'
  `scripts/verify-setup.mjs` reads only `manifest.packs`). After a schema 5
  rewrite it would see 0 checked files instead of 23, without any error, and a
  default `--targets both` lay can create `.claude/skills`, which that check
  rejects. So any write run (`--skills`, `--rules`, `--forget`) against a schema 4
  project stops with exit 1, writes nothing, and says the repo was laid by the old
  tool and its checks must be taught schema 5 first, in a separate change in that
  repo. `--upgrade-manifest` is the one explicit way through. `--list` and
  `--dry-run` still read schema 4. Tested in
  `test/reads-and-upgrades-schema-4.test.sh`.
- **`--rules` is added** in the same change, because the same projects need the
  shared working rules in `AGENTS.md`, and the same drift argument applies. It
  writes a marked block and nothing else. Its source for this release is a file
  on the maintainer's machine; the contents are scanned for machine paths,
  credentials and addresses first.
- **`--targets agents|both`** is added. The default stays both directories.

## What this costs

- **The merge gate contract is affected.** See the update appended to
  `2026-08-20-gate-asks-skillstack-for-shipped-hashes.md`. A gate that knows only
  schema 4 will report schema 5 as unrecognised and exclude nothing. That is
  safe, and it is a loss: files that were excluded from adversarial review get
  full review again, from the moment a project is re-run with this tool.
- **The licence notice is handled in the tool.** The old pack carried
  `THIRD-PARTY-NOTICES.md`, because the licence requires the upstream notice to
  accompany a copy. In `dep0we/skills` the notice sits above the skill folders
  (`vendor/<set>/LICENSE`). So when a laid skill's folder has no licence file of
  its own, the tool copies the nearest ancestor's `LICENSE` at the pinned commit
  into the skill as `LICENSE`, in every destination directory, and records it
  with its hash like any other laid file (so a hand edit to it is caught too).
  The walk stops before the repository root. A skill with no ancestor licence
  (the maintainer's own) gets none. A folder that has its own licence keeps it.
  Tested in `test/licence-notice-travels.test.sh`.
- **Skills outside the new source cannot be re-laid.** Pack skills that were
  never carried into `dep0we/skills` (for example `brainstorming`) stay tracked
  in an upgraded manifest and are reported on every run until they are named or
  removed by hand.
- **The tool now depends on a second repository being cloned and current.** A
  stale clone stops the run with a plain message instead of laying old content.

## Why not the alternatives

- **Keep `packs/` and re-sync it from `dep0we/skills` here.** Adds a copy step
  that can also drift, and puts a third copy of every skill on disk.
- **Fetch from GitHub at run time.** Puts the network in the lay-down path and
  lets the source move between two runs. The pinned local commit is the point.
- **Read the clone's working tree.** Cheap, and wrong whenever the clone has
  uncommitted work or sits on another branch.

## Not decided here

- Where the rules text finally lives. For this release the default source is
  `$SYSTEMS_ROOT/projects/agent-config/shared-rules.md`, the repo-safe rules with
  the personal context split out. The tool never defaults to the personal file.
  The source moves to claude-config `user/shared-rules.md` when that lands, and
  `SHARED_RULES_FILE` is a stopgap until then.
- The gate update. Written down in the gate decision record, not built.
