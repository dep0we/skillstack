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

## Laying a pack into a project

```
bin/lay-pack.sh --pack superpowers --skills a,b,c /path/to/project
```

Run it without `--skills` to see what a pack contains. There is deliberately
no way to say "all of them": taking every skill is how one project ended up
with 165 of its 194 tracked files being skill copies.

Files are written into `.claude/skills/` and `.agents/skills/`, which is the
minimum set covering Claude Code, Codex and Cursor. Which reader loads which
directory was measured, not read from documentation; see
`docs/decisions/2026-08-23-skill-directories-measured.md`.

For a Cursor Cloud and Codex-only project, add `--targets agents`. It writes
only `.agents/skills/`, so the project carries one copy. Local Claude Code
still reads `CLAUDE.md`, but it does not load those skills in that layout.

The tool records every file it writes, with a hash, in `.vendored-skills.json`
at the project root. On a later run, a file whose hash has moved since it was
laid down is reported and skipped rather than overwritten, and the run exits 2.
`--forget <skill>` is the one deliberate way past that, and it deletes nothing.
Nothing this tool does ever deletes a file.

It also appends one ignore rule, `.superpowers/`, to the project's
`.gitignore`. The skills being copied in write live session state into the
working tree the moment they run, including a session key in cleartext, and
laying them down without that rule leaves a project one `git add -A` away from
committing a live credential. Four repositories had to add the rule by hand
before this was the tool's job. It is appended, never rewritten, a target that
already has the rule is left byte-identical, and session state that is
**already committed** is named in the report rather than papered over, because
an ignore rule does not untrack a file. See "What the tool writes into a
project" in `docs/SPEC.md`.

Other flags: `--dry-run` writes nothing at all, and `--list` reports what a
project already holds.

## What's here

- `packs/<name>/` — the corrected snapshot that ships, its corrections as a
  separate record, and the upstream copyright notice the licence requires to
  travel with a copy.
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
