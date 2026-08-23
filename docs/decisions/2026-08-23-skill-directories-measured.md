# Which skill directories a pack is laid into, measured

**Date:** 2026-08-23
**Status:** accepted for local readers. The cloud case is open and is tracked
separately; see "What is still unmeasured" below.
**Supersedes:** nothing. It supplies the measurement `docs/SPEC.md` promised at
its allowed-locations rule, and corrects the reason that rule gave.
**Reversible:** yes, cheaply. The destination list is one named constant in
`bin/lay-pack.sh` and one rule in `docs/SPEC.md`, and they have to change
together.

## The question

A pack was laid into three directories, `.claude/skills/`, `.cursor/skills/`
and `.agents/skills/`, which is three copies of every file. Measured in one
project, that was 165 of 194 tracked files and roughly 520KB of skill copies in
a repository whose own content was 29 files.

`docs/SPEC.md` narrowed that to two, dropping `.cursor/skills/`, and gave this
reason: Cursor and Codex both read `.agents/skills/`, which makes a third copy
redundant. It also recorded that the narrowing rested on a loader trace from
2026-08-17 and 2026-08-18 that had been carried forward rather than re-run, and
committed to re-running it, in these words: **if the re-measurement contradicts
it, this rule is what changes.**

This is that re-measurement.

## What was measured

Four throwaway git repositories, each holding the same fixture skills in one
location only, plus an empty control:

| repo | skills live in |
| --- | --- |
| control | nowhere |
| A | `.claude/skills/` |
| B | `.agents/skills/` |
| C | `.cursor/skills/` |

The fixture skills are named with a nonsense token that exists nowhere else, so
a reader naming one cannot be naming something it already knew.

## The result

| reader | `.claude/skills/` | `.agents/skills/` | `.cursor/skills/` |
| --- | --- | --- | --- |
| Claude Code 2.1.241 | **loads** | no | no |
| Codex CLI 0.147.0 | no | **loads** | no |
| Cursor CLI 2026.08.11, local | **loads** | **loads** | **loads** |

Minimum set covering all three local readers: **`.claude/skills/` and
`.agents/skills/`**. Two directories, which is the conclusion the
specification already carried.

## The conclusion held. The stated reason did not.

The specification says `.cursor/skills/` is redundant because Cursor reads
`.agents/skills/`. That is true and it is not the whole fact. **Local Cursor
reads all three directories, `.cursor/skills/` included.** So `.cursor/` is
redundant because Cursor reads a superset, not because Cursor ignores it.

Locally the two readings support the same decision, which is why the wrong one
survived. They come apart completely for a cloud agent: "Cursor reads a
superset" says nothing about which directory a cloud agent reads, while "Cursor
ignores `.cursor/`" would have settled it. Anyone deciding the cloud question
from the specification's reason would have derived a conclusion the evidence
does not support. The reason is corrected in `docs/SPEC.md` in the same change
as this record.

## The instruments, and the one that lied

**Claude Code** exposes its own loader trace. `claude --debug-file <path>`
prints `Loading skills from: ... project=[...]` and a `project: N` count. The
empty control reported `project: 0` and `project=[]`; repo A reported
`project: 3` with its path named, matching the fixture count exactly; repos B
and C reported `project: 0`. A positive control firing at the exact fixture
count is what makes the zeroes mean "looked and found nothing" rather than
"the instrument was not working".

**Codex** renders the model-visible prompt with `codex debug prompt-input`. All
three fixture skills appear there by name, description and path in repo B, and
in none of the other three.

**Cursor has no loader-trace flag, and the obvious substitute produced a
confident wrong answer.** Asked directly, in read-only mode with tools
forbidden, to list the skills in its context, it named the fixture skills in
repos A and B and answered **"NONE AVAILABLE"** in repo C. That answer is
false: the replacement instrument below shows repo C's skill loads.

A prior record already establishes that asking a model to list its own skills
is an invalid instrument, having caught it naming skills that were not loaded.
That is a false positive. This is the same instrument failing as a **false
negative**, and the false negative is the more dangerous of the two, because an
over-claim invites suspicion while a clean negative result invites none. It
would have been reported as measured.

**The replacement never asks the model about skills at all.** The trigger word
and an unguessable answer token live in the skill's `description`, which is the
part a loader injects. The prompt is the single trigger word. **The evidence is
the tool-call ordering, not the answer:**

| repo | first file-touching tool calls |
| --- | --- |
| control | glob, glob `**/*`, grep for the trigger, read README, grep two config directories. Never found it. |
| A | **first call**: read `.claude/skills/<fixture>/SKILL.md` |
| B | **first call**: read `.agents/skills/<fixture>/SKILL.md` |
| C | **first call**: read `.cursor/skills/<fixture>/SKILL.md` |

In all three loaded cases the first call is a direct read of a path containing
a skill name the model had no way to guess, with no glob, grep or listing
before it. The control shows what searching looks like when nothing was
injected, and it looks nothing like a direct read. That control could have come
out the other way, and it did.

## What is still unmeasured, and why it matters more than it looks

**Whether a Cursor cloud agent loads committed skills, and from which
directory.** Neither is known. Two separate questions:

1. *Does a committed skill reach a cloud agent at all?* This is the premise the
   whole approach rests on: skills are committed rather than installed because
   a cloud agent clones the repository into an isolated VM with no access to
   the maintainer's laptop. Nobody has instrumented it. There is one prior
   observation that it appeared to work, which is an observation and not an
   instrument.
2. *Which directory does cloud read?* This is what decides whether the
   narrowing to two is safe.

**Local Cursor cannot answer either, and this is exactly why the corrected
reason matters.** Locally Cursor reads all three, so every layout works and
local behaviour distinguishes nothing. The earlier successful observation was
made against a repository carrying all three directories, so it is blind for
the same reason.

Until question 2 is answered, the narrowing to two ships on local evidence
only. The exposure is bounded: no project has been laid down with this tool
yet, so the window is between now and that measurement, with nothing in it. If
cloud turns out to read `.cursor/skills/`, the allowed-locations rule is what
changes, exactly as the specification already provides for.

## What was asked for and not done

The originating issue also asked, if three copies really were needed, that a
symlink be tested as a way to satisfy three readers from one tracked object.
**Not tested, because the measurement made it moot**, and it is recorded here
rather than left silent so that nobody assumes it was tried and worked.

Two independent reasons it would have been refused anyway. The guardrail
toolkit's installer treats a symlinked skill directory as a security case and
refuses to write through one, so a symlinked layout risks the installer
refusing its own output. And a per-skill symlink makes git track one object
where the manifest names many files, which breaks the gate that reads a diff.

## How to disbelieve this

Everything above is reproducible from the method as written: four repositories,
one skill location each, an empty control, an unguessable token in the
description, and the tool-call ordering read rather than the answer.

The raw transcripts and the scripts that produced them were kept, and are
recorded in the maintainer's notes rather than here. They are absolute
filesystem paths from end to end, which do not belong in a public repository,
and the path to them is machine-specific detail that would not help a reader
anyway. Nothing in them is needed to re-run this: the method above is. They
exist for anyone who would rather check the original than take the table on
trust.
