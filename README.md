# skillstack

One place that owns the corrected third-party agent-skill bundles the
maintainer layers into his project repositories, and (once built) the tool
that does the layering.

## Why this exists

A cloud coding agent clones a project repository into an isolated VM with no
access to the maintainer's laptop. Anything that must reach that agent has to
be committed into the project repository itself. Skills therefore get copied
in, not installed as a plugin.

Doing that by hand across four repos on 2026-08-18 cost most of a day, and the
four copies disagreed with each other: three divergent copies of the same
upstream commit, differing in sixteen files, only one carrying the upstream
copyright notice its licence requires, only one carrying the package
declaration that keeps a shipped script running on a current Node runtime.

`skillstack` exists so that work happens once, in one place, and every project
gets the same result.

## Laying skills into a project

```
bin/lay-pack.sh --skills a,b,c [--rules] [--targets agents|both] /path/to/project
bin/lay-pack.sh --rules /path/to/project
```

Skills come from one place: the `dep0we/skills` repository, at the commit named
in `source.lock`. Dan's machines install from the same commit, so a copy in a
project matches what runs on them. The tool reads a clone at `SKILLS_REPO`
(default `~/Projects/skills`), takes names from `primary-set.txt` at the pinned
commit, and reads the files from that commit, not from the clone's working tree.
If the clone lacks the pinned commit, the run stops and prints the fetch command
to run. It never fetches. `--pack` is retired and says so.

Run it with neither `--skills` nor `--rules` to see which skills are listed.
There is deliberately no way to say "all of them": taking every skill is how one
project ended up with 165 of its 194 tracked files being skill copies.

`--targets both` (the default) writes `.agents/skills/` and `.claude/skills/`,
the minimum set covering Claude Code, Codex and Cursor. `--targets agents`
writes `.agents/skills/` only. Which reader loads which directory was measured,
not read from documentation; see
`docs/decisions/2026-08-23-skill-directories-measured.md`.

`--rules` keeps a managed block at the top of the project's `AGENTS.md`, between
`<!-- shared-rules:begin -->` and `<!-- shared-rules:end -->`, and touches
nothing outside those lines. The text comes from `SHARED_RULES_FILE` (default
`$SYSTEMS_ROOT/projects/agent-config/working-with-dan.md`). A source that holds a
machine path, a credential or an address is refused. Re-running with an
unchanged source changes nothing. A block edited by hand is reported and skipped.

The tool records every file it writes, with a hash, in `.vendored-skills.json`
at the project root (schema 5). It still reads the schema 4 files that the old
pack tool wrote, and upgrades them on the next write without losing a recorded
hash. On a later run, a file whose hash has moved since it was laid down is
reported and skipped rather than overwritten, and the run exits 2.
`--forget <skill>` is the one deliberate way past that, and it deletes nothing.
Nothing this tool does ever deletes a file.

When skills are laid it also appends one ignore rule, `.superpowers/`, to the
project's `.gitignore`. The skills being copied in write live session state into
the working tree the moment they run, including a session key in cleartext, and
laying them down without that rule leaves a project one stage-everything commit
away from committing a live credential. Four repositories had to add the rule by
hand before this was the tool's job. It is appended, never rewritten, a target
that already has the rule is left byte-identical, and session state that is
**already committed** is named in the report rather than papered over, because
an ignore rule does not untrack a file. See "What the tool writes into a
project" in `docs/SPEC.md`.

Other flags: `--dry-run` writes nothing at all, and `--list` reports what a
project already holds.

## What's here

- `source.lock` — the commit of `dep0we/skills` that every skill is laid from.
- `packs/<name>/` — **superseded 2026-10-19.** The old corrected snapshot, kept
  because schema 4 manifests and the schema 4 gate contract refer to it. See
  `packs/README.md`.
- `bin/lay-pack.sh` — the layering tool, and `test/` its suite.
- `docs/SPEC.md` — the full design, including the manifest shape a project
  carries afterwards, which a separate reader in another repository (a merge
  gate) has to be able to validate on its own.
- `docs/decisions/` — the rulings, each with what it cost and what was
  accepted.

`bin/` also holds the two superseded scripts this replaces. **Both refuse to
run.** They are kept because they are the readable reference for what was
carried forward and what was not:

- `bin/vendor-skills.sh` — the previous vendoring tool. Its per-file hash and
  hand-edit-refusal mechanics are the foundation `lay-pack.sh` builds on. It
  clones upstream's latest default branch and writes a schema 1 manifest,
  which is why it refuses rather than merely being discouraged.
- `bin/soften-tdd.py` — the previous correction script, matching three exact
  phrases in one file name. Review of a real import found the same instruction
  live in three files it never opens. Corrections are applied once now, when a
  pack version is cut, so nothing corrects at lay-down time.

## Upstream default

The default skill stack this tooling vendors from is
[obra/superpowers](https://github.com/obra/superpowers), the same default
`vendor-skills.sh` already uses. Naming it here is deliberate: this repository
is where the pairing with a specific third-party stack belongs.

## Status

Local only. No remote exists yet — the maintainer creates that himself.
Everything in this repository so far is scaffolding for Linear issue DAR-155:
spec and scaffold, not the finished bundle or corrections. That is separate,
tracked work.

## A note on `foundBy`

`packs/*/corrections.json` records which project's adversarial review found
each correction, as `project-a` through `project-d`. Those are neutral labels
for private repositories, kept because the attribution is real and worth
having, not because the names matter. The corrections themselves stand on
their own.

## History

This repository was rebuilt as a single commit when it was made public. Its
private predecessor holds the commit-by-commit review history: three review
rounds on the pack and two on the specification, and what each round found.
