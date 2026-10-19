# packs/: superseded

**SUPERSEDED 2026-10-19.** `bin/lay-pack.sh` no longer reads this directory.
Skills now come from `dep0we/skills` at the commit in `source.lock`, so a copy in
a project matches what the maintainer's machines install. See
`docs/decisions/2026-10-19-skills-come-from-one-pinned-source.md`.

Nothing here is deleted, for three reasons:

- Schema 4 manifests in existing projects, and the schema 4 merge-gate contract,
  point at the `superpowers-v0.1.0` release and `packs/superpowers/files.json`.
- `packs/superpowers/corrections.json` is the record of why each correction
  exists. `dep0we/skills` carries the corrected text.
- `packs/superpowers/THIRD-PARTY-NOTICES.md` is the upstream copyright notice.

Do not edit files here to change what projects receive. That is done in
`dep0we/skills`.
