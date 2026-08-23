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

## What's here right now

This repository currently holds a specification and a scaffold, not the
finished tool. See `docs/SPEC.md` for the full design, including:

- what a "skill pack" is
- what the (not-yet-built) tool will do
- the manifest shape a project carries after a pack is layered in, which a
  separate reader (the `kit` merge gate, in a different repository) needs to
  be able to validate on its own
- which parts of the existing vendoring script are carried forward and which
  are superseded

`bin/` carries forward, unmodified, the two scripts this replaces:

- `bin/vendor-skills.sh` — the current working vendoring tool, copied from
  the maintainer's personal config repository. Its per-file hash and
  hand-edit-refusal mechanics are the foundation the new tool builds on. Its
  all-or-nothing, no-selection, no-corrections design is what it replaces. Do
  not run it against a new project going forward; see `docs/SPEC.md`.
- `bin/soften-tdd.py` — the current, too-narrow correction script (three
  skill-directory copies of one file, three phrases each), copied from the
  same place. Fully superseded; kept for reference only.

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
