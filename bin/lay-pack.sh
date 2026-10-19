#!/bin/bash
# Lay skills, and the shared rules block, into a project repository.
#
# Skills come from ONE pinned source: the dep0we/skills repository, at the
# commit named in source.lock. The pin is the whole point. Dan's machines
# install skills from that same commit, and a project copy taken from anywhere
# else drifts from them. This tool never fetches, never reads the source
# clone's working tree, and never corrects anything at lay-down time. It reads
# files out of the pinned commit with git. See docs/SPEC.md sections 2 and 3.
#
# Why the files are copied into the project at all, rather than installed:
# a cloud coding agent clones the repository into an isolated VM with no
# access to the maintainer's laptop, so anything that has to reach that agent
# has to be committed into the project repository itself.
#
# Usage:
#   bin/lay-pack.sh --skills a,b,c [--rules] [--targets agents|both] <project>
#   bin/lay-pack.sh --rules <project>
#   bin/lay-pack.sh --skills a,b,c --dry-run <project>
#   bin/lay-pack.sh --forget <skill> <project>
#   bin/lay-pack.sh --list <project>
#
# --skills is required to lay skills and has no "all". Taking every skill is how
#   one project ended up with 165 of its 194 tracked files being skill copies.
#   A name must be listed in primary-set.txt at the pinned commit.
# --targets picks where skills are written. "both" (the default) writes
#   .agents/skills and .claude/skills. "agents" writes .agents/skills only.
# --rules writes the shared rules into a managed block at the top of the
#   project's AGENTS.md, between <!-- shared-rules:begin --> and
#   <!-- shared-rules:end -->. Nothing outside those lines is touched.
# --pack is retired. Packs are replaced by the pinned dep0we/skills source.
#
# Environment:
#   SKILLS_REPO         clone of dep0we/skills (default ~/Projects/skills)
#   SKILLS_LOCK_FILE    pin file (default source.lock beside this script's repo)
#   SHARED_RULES_FILE   rules source (default
#                       $SYSTEMS_ROOT/projects/agent-config/working-with-dan.md)
#
# Exit codes:
#   0  finished, nothing was skipped
#   1  usage, environment, or an integrity refusal; nothing was written
#   2  finished, but something needs a decision: files or the rules block
#      skipped because of a local edit, skills left unselected, or session state
#      already committed under .superpowers/

set -uo pipefail

# ---------------------------------------------------------------- constants

MANIFEST_NAME=".vendored-skills.json"
SCHEMA_VERSION=5
SOURCE_REPO="dep0we/skills"
SOURCE_LOCK_NAME="source.lock"

# THE ONE PLACE DESTINATION DIRECTORIES ARE NAMED.
#
# This list must equal the allowed-location prefixes in docs/SPEC.md section 4.
# A path the gate does not allow is not skipped by it: the whole manifest is
# rejected and nothing is excluded. So adding a directory here without changing
# the specification turns the exclusion mechanism off entirely, silently.
#
# Which directories each reader actually loads was measured, not read from
# documentation. See docs/decisions/2026-08-23-skill-directories-measured.md.
DEST_DIRS=(".claude/skills" ".agents/skills")

# The markers around the managed rules block in a project's AGENTS.md. They
# must equal the markers stated in docs/SPEC.md, "The shared rules block".
RULES_BEGIN="<!-- shared-rules:begin -->"
RULES_END="<!-- shared-rules:end -->"
RULES_TARGET_NAME="AGENTS.md"
RULES_DEFAULT_REL="projects/agent-config/working-with-dan.md"

# THE ONE PLACE THE IGNORE RULE IS NAMED.
#
# This must equal the rule stated in docs/SPEC.md, "What the tool writes into
# a project".
#
# Skills laid down here write live session state into <project>/.superpowers/
# at run time. The brainstorming companion server writes a 64-character
# session key in cleartext to .superpowers/brainstorm/.last-token and embeds
# the same key in a URL in that session's server-info and server.log;
# subagent-driven-development writes plan workspaces under .superpowers/sdd/.
# None of that is skill content, none of it belongs in git, and a commit
# carrying it publishes a live credential.
#
# The skill's own brainstorming/visual-companion.md says to "remind the user to
# add .superpowers/ to .gitignore if it's not already there". That reminder is
# what left the hole: measured on 2026-08-25, four project repositories had to
# fix this by hand after the fact, and the fifth would have been the same
# conversation again. The tool that copies the skills in is the only party
# that knows the writes are coming, so it is the party that has to say so.
#
# Unanchored and directory-only, both deliberate. Unanchored, so a session
# started with --project-dir pointing at a subdirectory is covered too.
# Directory-only, so 'superpowers/notes.md' and 'docs/.superpowers-notes.md'
# are left alone.
IGNORE_RULE=".superpowers/"

# The paths that rule has to actually cover. Pinned by name, never by count.
#
# They are asked of git, never grepped out of .gitignore, because grepping
# answers a different question. A rule can be present in the file and undone
# by a later negation, and a rule can be absent from the file while a parent
# directory's .gitignore or the repository's own exclude file already covers
# the path. git check-ignore is the only thing that knows which.
IGNORE_PROBES=(
  ".superpowers/brainstorm/.last-token"
  ".superpowers/sdd/progress.md"
)

# What the shared rules source is scanned for before it is laid into a project.
# Each entry is "<what it is>|<extended regex>". The rules go into repositories
# that may be shared, so a source that carries a machine path, a credential or
# an address is refused rather than copied. A hit reports the line number and
# the kind, never the matching text.
PRIVACY_CHECKS=(
  "an absolute machine path|(^|[^A-Za-z0-9_.~\$])/(Users|home|Volumes|private|mnt|var/folders)/[A-Za-z0-9._-]+"
  "a Windows drive path|[A-Za-z]:[\\]"
  "a sync-folder path|CloudStorage|Mobile Documents"
  "a private key block|-----BEGIN [A-Z ]*PRIVATE KEY"
  "an API token|(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|lin_api_[A-Za-z0-9]{20,})"
  "a credential assignment|(api[_-]?key|secret|token|passw(or)?d)[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9/+_.-]{12,}"
  "a long hex string|[A-Fa-f0-9]{40,}"
  "an email address|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
  "an IP address|([0-9]{1,3}\.){3}[0-9]{1,3}"
  "a private hostname|[A-Za-z0-9-]+\.(local|internal|lan|corp|ts\.net)([^A-Za-z0-9]|$)"
)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

usage() {
  sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

# ------------------------------------------------------------ where we live
#
# source.lock is resolved next to THIS SCRIPT, never next to the caller. The pin
# travels with the script, so the script's own location is the correct root.
# Stated because the neighbouring repository has a lesson about a script
# deriving its root from its own location when it should not have; this is the
# same mechanism used correctly, and it should not be "fixed" into $PWD.

SCRIPT_PATH="$0"
while [ -L "$SCRIPT_PATH" ]; do
  link_target="$(readlink "$SCRIPT_PATH")"
  case "$link_target" in
    /*) SCRIPT_PATH="$link_target" ;;
    *)  SCRIPT_PATH="$(dirname "$SCRIPT_PATH")/$link_target" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" || die "cannot resolve my own location"
SKILLSTACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || die "cannot resolve the repository root"

# ---------------------------------------------------------------- arguments

SKILLS_ARG=""
TARGET=""
DRY_RUN=0
FORGET=""
LIST_ONLY=0
SKILLS_GIVEN=0
RULES_GIVEN=0
TARGETS_MODE="both"

while [ $# -gt 0 ]; do
  case "$1" in
    --pack)    die "packs are retired. Skills now come from $SOURCE_REPO at the commit pinned in $SOURCE_LOCK_NAME. Use --skills a,b,c instead." ;;
    --skills)  SKILLS_ARG="${2:-}"; SKILLS_GIVEN=1
               [ -n "$SKILLS_ARG" ] || die "--skills needs at least one skill name"; shift 2 ;;
    --rules)   RULES_GIVEN=1; shift ;;
    --targets) TARGETS_MODE="${2:-}"
               case "$TARGETS_MODE" in
                 agents|both) ;;
                 *) die "--targets takes 'agents' or 'both', got '$TARGETS_MODE'" ;;
               esac
               shift 2 ;;
    --forget)  FORGET="${2:-}"; [ -n "$FORGET" ] || die "--forget needs a skill name"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --list)    LIST_ONLY=1; shift ;;
    -h|--help) usage 0 ;;
    -*)        die "unknown option: $1 (try --help)" ;;
    *)
      [ -z "$TARGET" ] || die "only one project path is accepted, got '$TARGET' and '$1'"
      TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || usage 1
[ -d "$TARGET" ] || die "not a directory: $TARGET"

# --list reads and --forget writes. Doing only the read while the caller
# believes the write happened is the worst of the three outcomes, so refuse.
if [ "$LIST_ONLY" -eq 1 ] && [ -n "$FORGET" ]; then
  die "--list and --forget do different things; pass one at a time"
fi
if [ "$LIST_ONLY" -eq 1 ] && { [ "$SKILLS_GIVEN" -eq 1 ] || [ "$RULES_GIVEN" -eq 1 ]; }; then
  die "--list only reads; it cannot be combined with --skills or --rules"
fi
if [ "$SKILLS_GIVEN" -eq 1 ] && [ -n "$FORGET" ]; then
  die "--skills and --forget do different things; pass one at a time"
fi
if [ "$RULES_GIVEN" -eq 1 ] && [ -n "$FORGET" ]; then
  die "--rules and --forget do different things; pass one at a time"
fi

TARGET_DIRS=()
case "$TARGETS_MODE" in
  agents) TARGET_DIRS=(".agents/skills") ;;
  *)      TARGET_DIRS=("${DEST_DIRS[@]}") ;;
esac

# ------------------------------------------------------------- environment

command -v git >/dev/null 2>&1 || die "git is required and was not found"
command -v jq  >/dev/null 2>&1 || die "jq is required and was not found"
if command -v shasum >/dev/null 2>&1; then
  hash_of() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  hash_of() { sha256sum "$1" | awk '{print $1}'; }
else
  die "need shasum or sha256sum to hash files, found neither"
fi

TARGET="$(cd "$TARGET" && pwd)" || die "cannot resolve $TARGET"
MANIFEST="$TARGET/$MANIFEST_NAME"

git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
  || die "$TARGET is not a git repository. Laid-down skills have to be committed to reach a cloud agent."

# Everything staged for a copy lives here, outside the project, and goes away
# when the run ends however it ends.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lay-pack.XXXXXX")" || die "cannot create a scratch directory"
trap 'rm -rf "$STAGE"' EXIT

# A skill name becomes a path segment in three places. Anything that could
# climb out of the destination directory, or collapse two skills onto one
# path, is refused before it is interpolated anywhere.
valid_skill_name() {
  case "$1" in
    ""|.|..) return 1 ;;
    */*|*'\'*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

# --------------------------------------------------------------- manifest io

read_manifest() {
  if [ -f "$MANIFEST" ]; then
    jq -e . "$MANIFEST" >/dev/null 2>&1 \
      || die "$MANIFEST_NAME exists but is not valid JSON. Fix or delete it, then re-run."
    cat "$MANIFEST"
  else
    printf '{"schemaVersion":%s,"source":{"repo":"%s"},"skills":{}}' "$SCHEMA_VERSION" "$SOURCE_REPO"
  fi
}

# Schema 4 is what the retired pack tool wrote, and four real projects hold one.
# It is read and upgraded on the next write. Schema 1 is what vendor-skills.sh
# produced; it is keyed by repository URL under "vendored" and has no skill
# concept, so merging into it would produce a file that is neither shape.
assert_supported_schema() {
  local found
  found="$(printf '%s' "$1" | jq -r '.schemaVersion // "none"')"
  [ "$found" = "$SCHEMA_VERSION" ] && return 0
  [ "$found" = "4" ] && return 0
  if [ "$found" = "none" ] || [ "$found" = "1" ]; then
    die "$MANIFEST_NAME is schema ${found/none/1 (unversioned)}, written by the superseded vendor-skills.sh.
This tool reads schema 4 and writes schema $SCHEMA_VERSION, and will not rewrite an older one in place.
Move the old file aside and re-run to lay the skills down fresh."
  fi
  die "$MANIFEST_NAME declares schemaVersion $found, which this tool does not write. Refusing to touch it."
}

# upgrade_manifest <manifest json>
#
# Brings a schema 4 manifest into the schema 5 shape, in memory. Every recorded
# path and hash is carried over unchanged, which is what keeps hand-edit
# detection working across the upgrade: a file edited under the old tool is
# still an edited file under this one.
#
# Schema 4 grouped skills under a pack name. Schema 5 has no packs, so each
# skill gets its own entry, and the pack it was laid from is kept under
# "legacy" so a reader can still see where an old copy came from. A skill with
# a "legacy" entry has no source folder; it was laid by the retired tool and is
# only tracked, not re-laid, unless it is listed in primary-set.txt.
upgrade_manifest() {
  printf '%s' "$1" | jq '
    if .schemaVersion == 5 then (.skills //= {})
    else
      {
        schemaVersion: 5,
        source: {repo: "dep0we/skills"},
        skills: (
          [ (.packs // {}) | to_entries[] | . as $p
            | ($p.value.skills // [])[] as $s
            | { key: $s,
                value: {
                  legacy: {
                    pack: $p.key,
                    packVersion: $p.value.packVersion,
                    packCommit: $p.value.packCommit,
                    upstream: $p.value.upstream
                  },
                  installedAt: $p.value.installedAt,
                  files: [ ($p.value.files // [])[] | select((.path | split("/")[2]) == $s) ]
                } }
          ] | from_entries
        )
      }
    end'
}

# assert_paths_allowed <json array of {path,sha256}> <allowed skill names...>
#
# Every path about to be recorded has to be <one of DEST_DIRS>/<a skill this
# run accounts for>/<file>. This is the same rule the gate applies, and a path
# failing it is not skipped there: the whole manifest is rejected and nothing
# is excluded, so one bad entry turns exclusion off for the whole project.
#
# It is load-bearing rather than decoration because not every path reaching it
# was built by this run. Entries for skills recorded previously and not named
# in --skills are carried forward from the manifest on disk, which is an
# ordinary file anyone can edit, so a doctored entry arrives here unexamined
# unless something looks at it. Paths this run constructed cannot be wrong;
# those are not the ones this is for.
assert_paths_allowed() {
  local json="$1"; shift
  local allowed=("$@")
  local p seg dir s ok
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in
      /*) die "refusing this manifest: '$p' is absolute, and absolute paths are never skill content" ;;
      ..|../*|*/../*|*/..) die "refusing this manifest: '$p' has a '..' path segment" ;;
      */) die "refusing this manifest: '$p' names a directory, not a file" ;;
    esac
    ok=0
    for dir in "${DEST_DIRS[@]}"; do
      case "$p" in
        "$dir"/*/*)
          seg="${p#"$dir"/}"; seg="${seg%%/*}"
          for s in "${allowed[@]}"; do [ "$seg" = "$s" ] && ok=1 && break; done
          ;;
      esac
      [ "$ok" -eq 1 ] && break
    done
    [ "$ok" -eq 1 ] \
      || die "refusing this manifest: '$p' is not <one of ${DEST_DIRS[*]}>/<a recorded skill>/<file>"
  done < <(printf '%s' "$json" | jq -r '.[].path')
}

# assert_manifest_paths_ok <manifest json, exactly as read from disk>
#
# Applied to the manifest AS READ, before anything is decided from it, and to
# every pack (schema 4) or skill (schema 5) in it rather than only the one
# being laid down.
#
# Reading is the right moment. A check placed later sees only the entries that
# survive to be written, and an entry whose path is malformed enough does not
# survive: the carry-forward matches on the skill segment, so a path with no
# valid skill segment is quietly dropped rather than refused. Dropping fails
# safe, since an unrecorded file is never excluded by a gate, but it fails
# silently, and a manifest that changed under someone without a word is how a
# project stops being able to say what it holds.
assert_manifest_paths_ok() {
  local json="$1" schema k files sk
  local skills
  schema="$(printf '%s' "$json" | jq -r '.schemaVersion // "none"')"
  if [ "$schema" = "4" ]; then
    while IFS= read -r k; do
      [ -z "$k" ] && continue
      files="$(printf '%s' "$json" | jq --arg k "$k" '.packs[$k].files // []')"
      skills=()
      while IFS= read -r sk; do [ -n "$sk" ] && skills+=("$sk"); done \
        < <(printf '%s' "$json" | jq -r --arg k "$k" '.packs[$k].skills // [] | .[]')
      assert_paths_allowed "$files" ${skills[@]+"${skills[@]}"}
    done < <(printf '%s' "$json" | jq -r '.packs // {} | keys[]')
  else
    while IFS= read -r k; do
      [ -z "$k" ] && continue
      valid_skill_name "$k" || die "refusing this manifest: '$k' is not a usable skill name"
      files="$(printf '%s' "$json" | jq --arg k "$k" '.skills[$k].files // []')"
      assert_paths_allowed "$files" "$k"
    done < <(printf '%s' "$json" | jq -r '.skills // {} | keys[]')
  fi
}

# ------------------------------------------------------------------- --list

if [ "$LIST_ONLY" -eq 1 ]; then
  if [ ! -f "$MANIFEST" ]; then
    info "Nothing has been laid into $TARGET (no $MANIFEST_NAME)."
    exit 0
  fi
  raw_json="$(read_manifest)" || exit 1
  assert_supported_schema "$raw_json"
  assert_manifest_paths_ok "$raw_json"
  listed_schema="$(printf '%s' "$raw_json" | jq -r '.schemaVersion')"
  manifest_json="$(upgrade_manifest "$raw_json")"
  info "manifest:    schema $listed_schema"
  [ "$listed_schema" = "4" ] \
    && info "             written by the retired pack tool; the next write upgrades it to schema $SCHEMA_VERSION"
  src_commit="$(printf '%s' "$manifest_json" | jq -r '.source.commit // "none recorded"')"
  info "source:      $(printf '%s' "$manifest_json" | jq -r '.source.repo // "unknown"') @ $src_commit"
  count="$(printf '%s' "$manifest_json" | jq '.skills | length')"
  has_rules="$(printf '%s' "$manifest_json" | jq 'has("rules")')"
  if [ "$count" -eq 0 ] && [ "$has_rules" = "false" ]; then
    info "$MANIFEST_NAME is present and records no skills and no rules."
    exit 0
  fi
  printf '%s' "$manifest_json" | jq -r '
    (.skills | to_entries[] |
      "skill: \(.key)\n"
      + (if .value.legacy then "  from:      retired pack \(.value.legacy.pack) \(.value.legacy.packVersion)\n"
         else "  from:      \(.value.folder // "unknown") @ \(.value.commit // "unknown")\n" end)
      + "  installed: \(.value.installedAt // "unknown")\n"
      + "  files:     \(.value.files | length)"),
    (if has("rules") then
      "rules: \(.rules.file)\n  source:    \(.rules.source)\n  source sha256: \(.rules.sourceSha256)\n  block sha256:  \(.rules.blockSha256)\n  installed: \(.rules.installedAt)"
     else empty end)'
  exit 0
fi

# ------------------------------------------------------- the ignore rule
#
# A laid-down skill writes credentials into the working tree the moment it
# runs, and the project has no way to know that before it happens. See the
# IGNORE_RULE block at the top of this file for what writes what.
#
# This is the one thing the tool writes into a project that is neither skill
# content, the rules block nor the manifest, and it stays outside DEST_DIRS on
# purpose. DEST_DIRS is the allowed-location list a merge gate applies to
# manifest paths; adding an entry to it to hold .gitignore would widen that rule
# for every path in every project's manifest. Nothing about the ignore rule is
# recorded in the manifest either: git check-ignore reports its presence
# directly, which is a stronger answer than a field the change under review
# could have written.

# IGNORE_STATE is the one line for the report, set by ensure_ignore_rule
# below. IGNORE_TRACKED holds committed session state that a new rule
# cannot untrack. Written as full-line comments and not as trailing ones,
# because test/functions-are-defined-before-use.test.sh blanks full-line
# comments before it scans and a trailing comment naming a function above
# its own definition reads to that scan as a use before definition.
IGNORE_STATE=""
IGNORE_TRACKED=()

# path_is_ignored <project-relative path>
#
# --no-index, because a path already in the index reports "not ignored"
# without it. That answer is true of the index and false of the rules, and
# this function is asked about the rules: an already-committed leak would
# otherwise make every run append the rule again, forever.
#
# check-ignore exits 0 for ignored, 1 for not ignored, and something else when
# it could not run at all. The third is not the second. Swallowing it would
# report "no rule covers this" for a repository git could not read, and the
# run would then append a rule and report a protection it never measured.
path_is_ignored() {
  local rc
  git -C "$TARGET" check-ignore --no-index -q -- "$1"
  rc=$?
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) die "git check-ignore exited $rc in $TARGET.
Refusing to guess whether '$1' is ignored, and refusing to write a rule whose effect cannot be measured." ;;
  esac
}

# Unconditional, not scoped to whether the selection happens to include the two
# skills that write there today. A skill name is a proxy for "does this write
# session state", and the proxy goes stale the first time upstream adds a third
# writer, silently and in the unsafe direction. The rule costs a project one
# line and does nothing at all until something writes to that directory.
#
# Append the rule when git says the probe paths are not covered, and prove
# afterwards that they are. Appending, never rewriting: a project's .gitignore
# is somebody's file, and this tool does not own a line it did not write.
ensure_ignore_rule() {
  local gitignore="$TARGET/.gitignore"
  local p sep unprotected=() unverified=()

  for p in "${IGNORE_PROBES[@]}"; do
    path_is_ignored "$p" || unprotected+=("$p")
  done

  # What is already committed is a separate problem with a separate remedy. An
  # ignore rule does not untrack a tracked file, and the credential is already
  # in history, so reporting "protected" over the top of it would be the same
  # false clean result this whole change exists to remove.
  while IFS= read -r p; do
    [ -n "$p" ] && IGNORE_TRACKED+=("$p")
  done < <(git -C "$TARGET" ls-files -- "${IGNORE_RULE%/}" 2>/dev/null)

  if [ "${#unprotected[@]}" -eq 0 ]; then
    IGNORE_STATE="$IGNORE_RULE already covered by an existing rule"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    IGNORE_STATE="would append $IGNORE_RULE to .gitignore"
    return 0
  fi

  # Separate the block from whatever is above it, and repair a missing final
  # newline first so the rule cannot land on the end of somebody else's line.
  sep=""
  if [ -s "$gitignore" ]; then
    [ -n "$(tail -c 1 "$gitignore")" ] && sep=$'\n'
    sep="$sep"$'\n'
  fi

  {
    printf '%s' "$sep"
    printf '# Live session state written by the skills laid down here, added by\n'
    printf '# bin/lay-pack.sh. The brainstorming companion server writes a session\n'
    printf '# key in cleartext under this directory and embeds it in a URL in two\n'
    printf '# more files, so a commit that carries it publishes a live credential.\n'
    printf '%s\n' "$IGNORE_RULE"
  } >> "$gitignore" || die "could not append the ignore rule to $gitignore"

  for p in "${IGNORE_PROBES[@]}"; do
    path_is_ignored "$p" || unverified+=("$p")
  done
  [ "${#unverified[@]}" -eq 0 ] || die "appended $IGNORE_RULE to $gitignore and git still does not ignore: ${unverified[*]}
Something later in that file undoes it. Fix the file by hand before laying skills down."

  IGNORE_STATE="appended $IGNORE_RULE to .gitignore"
}

# ------------------------------------------------------------------ --forget

if [ -n "$FORGET" ]; then
  valid_skill_name "$FORGET" || die "'$FORGET' is not a usable skill name"
  raw_json="$(read_manifest)" || exit 1
  assert_supported_schema "$raw_json"
  assert_manifest_paths_ok "$raw_json"
  manifest_json="$(upgrade_manifest "$raw_json")"

  # "Give up my edits to this skill, take the source's version next run."
  #
  # It does NOT drop the files from the manifest. An unrecorded file is one
  # this script refuses to touch, so dropping them would guarantee the exact
  # opposite of what was asked. Instead each file is re-recorded at its CURRENT
  # hash, which makes the edit invisible to the hand-edit check, so the next
  # run sees a tracked, unmodified file that differs from the source and
  # overwrites it normally. Nothing is deleted here, by any path.
  before="$manifest_json"
  after="$before"
  matched=0; missing=0; adopted=0

  while IFS= read -r p; do
    [ -z "$p" ] && continue
    matched=$((matched+1))
    if [ -f "$TARGET/$p" ]; then
      h="$(hash_of "$TARGET/$p")"
      after="$(printf '%s' "$after" | jq --arg k "$FORGET" --arg p "$p" --arg h "$h" \
        '.skills[$k].files = ((.skills[$k].files // []) | map(if .path == $p then .sha256 = $h else . end))')"
    else
      # Gone from disk. Drop the entry so the next run re-copies it fresh.
      missing=$((missing+1))
      after="$(printf '%s' "$after" | jq --arg k "$FORGET" --arg p "$p" \
        '.skills[$k].files = ((.skills[$k].files // []) | map(select(.path != $p)))')"
    fi
  done < <(printf '%s' "$before" | jq -r --arg k "$FORGET" '.skills[$k].files // [] | .[].path')

  # Also adopt files sitting in this skill's directories that the manifest has
  # never heard of. Without this, --forget cannot reach the very files that
  # send people to it: a file present but unrecorded is skipped by every run,
  # forever, and --forget walking only the manifest would be powerless against
  # exactly the case it advertises. Recording at the CURRENT hash is what makes
  # the next run overwrite it. Nothing is deleted.
  for dir in "${DEST_DIRS[@]}"; do
    [ -d "$TARGET/$dir/$FORGET" ] || continue
    while IFS= read -r f; do
      rel="${f#"$TARGET"/}"
      known="$(printf '%s' "$after" | jq -r --arg k "$FORGET" --arg p "$rel" \
        '(.skills[$k].files // []) | map(select(.path == $p)) | length')"
      [ "$known" != "0" ] && continue
      h="$(hash_of "$f")"
      after="$(printf '%s' "$after" | jq --arg k "$FORGET" --arg p "$rel" --arg h "$h" \
        '.skills[$k].files = ((.skills[$k].files // []) + [{path:$p, sha256:$h}])')"
      matched=$((matched+1)); adopted=$((adopted+1))
    done < <(find "$TARGET/$dir/$FORGET" -type f | sort)
  done

  [ "$matched" -gt 0 ] || die "no files on disk or in $MANIFEST_NAME matched skill '$FORGET'"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] would clear the hand-edit flag on $matched files for '$FORGET'"
    info "[dry-run] nothing was written and $MANIFEST_NAME was not updated"
    exit 0
  fi

  printf '%s\n' "$after" | jq -S . > "$MANIFEST.tmp" || die "could not write $MANIFEST_NAME"
  mv "$MANIFEST.tmp" "$MANIFEST" || die "could not replace $MANIFEST_NAME"

  info "Cleared the hand-edit flag on $matched files for '$FORGET'."
  [ "$adopted" -gt 0 ] && info "($adopted were on disk but unrecorded, and are now tracked.)"
  [ "$missing" -gt 0 ] && info "($missing were already gone from disk and will be re-copied.)"
  info "Nothing was deleted. The next run overwrites them with the pinned source's version."
  exit 0
fi

# ------------------------------------------------- the pinned skills source
#
# Everything below reads from a commit of the dep0we/skills clone, never from
# that clone's working tree. A working tree can be dirty, on another branch, or
# ahead of what Dan's machines install, and none of that is the pin.

SKILLS_REPO="${SKILLS_REPO:-$HOME/Projects/skills}"
SOURCE_LOCK_FILE="${SKILLS_LOCK_FILE:-$SKILLSTACK_ROOT/$SOURCE_LOCK_NAME}"
PIN=""
PS_FOLDERS=()
PS_NAMES=()

# Reads the pinned commit out of source.lock: the first line that is neither a
# comment nor blank. Comments are how the file says it is temporary.
read_pin() {
  [ -f "$SOURCE_LOCK_FILE" ] || die "cannot find the pin file $SOURCE_LOCK_FILE"
  PIN="$(grep -v '^[[:space:]]*#' "$SOURCE_LOCK_FILE" | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]')"
  printf '%s' "$PIN" | grep -Eq '^[0-9a-f]{40}$' \
    || die "$SOURCE_LOCK_FILE must hold one full 40-character commit hash, got '$PIN'"
}

# Stops with a plain message when the pinned commit is not in the clone. It
# never fetches: a tool that quietly moves a clone is a tool whose pin means
# whatever the network said that day.
resolve_source() {
  read_pin
  [ -d "$SKILLS_REPO" ] \
    || die "no clone of $SOURCE_REPO at $SKILLS_REPO. Clone it there, or set SKILLS_REPO to where it is."
  git -C "$SKILLS_REPO" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$SKILLS_REPO is not a git repository. Set SKILLS_REPO to a clone of $SOURCE_REPO."
  git -C "$SKILLS_REPO" cat-file -e "${PIN}^{commit}" 2>/dev/null \
    || die "the pinned commit ${PIN:0:12} is not in the clone at $SKILLS_REPO.
Bring the clone up to date yourself, then run this again:
  git -C $SKILLS_REPO fetch
This tool never fetches."
}

# Reads primary-set.txt at the pinned commit into two parallel arrays, one entry
# per folder. A skill is named by its folder's last path segment, which is also
# how config-sync names it on Dan's machines.
load_primary_set() {
  local listing line folder name i
  listing="$(git -C "$SKILLS_REPO" show "$PIN:primary-set.txt" 2>/dev/null)" \
    || die "primary-set.txt does not exist at commit ${PIN:0:12} of $SKILLS_REPO"
  while IFS= read -r line; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ""|\#*) continue ;; esac
    case "$line" in
      /*|..|../*|*/../*|*/..|*/) die "primary-set.txt lists an unusable folder: '$line'" ;;
    esac
    folder="$line"
    name="${folder##*/}"
    valid_skill_name "$name" || die "primary-set.txt lists a folder whose name is not a usable skill name: '$folder'"
    for i in ${PS_NAMES[@]+"${!PS_NAMES[@]}"}; do
      [ "${PS_NAMES[$i]}" = "$name" ] \
        && die "primary-set.txt lists two folders named '$name': ${PS_FOLDERS[$i]} and $folder"
    done
    PS_FOLDERS+=("$folder")
    PS_NAMES+=("$name")
  done <<< "$listing"
  [ "${#PS_NAMES[@]}" -gt 0 ] || die "primary-set.txt at commit ${PIN:0:12} lists no folders"
}

# folder_of <skill name> -- prints the folder, or nothing when not listed.
folder_of() {
  local i
  for i in "${!PS_NAMES[@]}"; do
    [ "${PS_NAMES[$i]}" = "$1" ] && { printf '%s' "${PS_FOLDERS[$i]}"; return 0; }
  done
  return 1
}

# stage_skill <name> <folder>
#
# Copies every file of the folder, as it is recorded in the pinned commit, into
# the scratch directory under <name>/. Raw blob bytes, no filters. A symlink or
# a submodule entry is never skill content and stops the run.
stage_skill() {
  local name="$1" folder="$2" entry meta path mode type oid rel dest n=0
  while IFS= read -r -d '' entry; do
    meta="${entry%%$'\t'*}"
    path="${entry#*$'\t'}"
    mode="${meta%% *}"
    type="${meta#* }"; type="${type%% *}"
    oid="${meta##* }"
    if [ "$type" != "blob" ] || [ "$mode" = "120000" ]; then
      die "'$path' in $SOURCE_REPO is a $type (mode $mode), not a plain file. Refusing to copy it."
    fi
    [ "$path" != "$folder" ] || die "'$folder' in $SOURCE_REPO is a file, not a skill folder"
    rel="${path#"$folder"/}"
    dest="$STAGE/$name/$rel"
    mkdir -p "$(dirname "$dest")" || die "could not stage $rel"
    git -C "$SKILLS_REPO" cat-file blob "$oid" > "$dest" || die "could not read $path from commit ${PIN:0:12}"
    [ "$mode" = "100755" ] && chmod +x "$dest"
    n=$((n+1))
  done < <(git -C "$SKILLS_REPO" ls-tree -r -z "$PIN" -- "$folder")
  [ "$n" -gt 0 ] || die "folder '$folder' has no files at commit ${PIN:0:12} of $SOURCE_REPO"
}

# ------------------------------------------------------- the shared rules
#
# --rules keeps one managed block at the top of the project's AGENTS.md. The
# block is whatever the rules source file says, and the markers are the only
# thing this tool trusts to find it again. Content outside the markers is never
# read for meaning and never changed.
#
# The decision is made up front, read-only, so that a refusal happens before
# any skill file has been written. apply_rules then carries it out.

RULES_STATE=""
RULES_ACTION=""
RULES_SKIPPED=0
RULES_JSON="null"
RULES_BLOCK_FILE="$STAGE/rules-block"
RULES_AGENTS="$TARGET/$RULES_TARGET_NAME"
RULES_BEGIN_LINE=0
RULES_END_LINE=0

# Finds SYSTEMS_ROOT without executing the roots file: only its one export line
# is read, never sourced.
systems_root() {
  local v="${SYSTEMS_ROOT:-}" f="$HOME/.config/data-roots.env"
  if [ -z "$v" ] && [ -f "$f" ]; then
    v="$(grep -E '^[[:space:]]*(export[[:space:]]+)?SYSTEMS_ROOT=' "$f" | tail -1 | sed -E 's/^[^=]*=//; s/^["'"'"']//; s/["'"'"']$//')"
  fi
  printf '%s' "$v"
}

# scan_rules_source <file> -- stops the run when the file looks private.
scan_rules_source() {
  local c label re hits found=0 report=""
  for c in "${PRIVACY_CHECKS[@]}"; do
    label="${c%%|*}"
    re="${c#*|}"
    hits="$(LC_ALL=C grep -nEi -e "$re" "$1" 2>/dev/null | cut -d: -f1 | tr '\n' ' ')"
    if [ -n "$hits" ]; then
      found=1
      report="$report  $label, on line(s): $hits"$'\n'
    fi
  done
  [ "$found" -eq 0 ] || die "the rules source looks like it holds private data, so it was not laid:
$report(Lines only, not the text. Fix the source file, or point SHARED_RULES_FILE at a clean one.)"
}

# Works out what --rules would do and stores the answer in RULES_ACTION:
# create, insert, unchanged, replace, or skip (a hand-edited block). Reads
# only. Dies on anything it cannot place safely.
prepare_rules() {
  local src root label begin_n end_n cur_hash rec_block
  src="${SHARED_RULES_FILE:-}"
  root="$(systems_root)"
  if [ -z "$src" ]; then
    [ -n "$root" ] || die "SYSTEMS_ROOT is not set and is not in ~/.config/data-roots.env, so the default rules source cannot be found. Set SHARED_RULES_FILE to the rules file."
    src="$root/$RULES_DEFAULT_REL"
  fi
  [ -f "$src" ] || die "the rules source does not exist: $src"
  [ -s "$src" ] || die "the rules source is empty: $src"
  [ -L "$RULES_AGENTS" ] && die "$RULES_TARGET_NAME in the project is a symlink. Refusing to write through it."
  [ -e "$RULES_AGENTS" ] && [ ! -f "$RULES_AGENTS" ] && die "$RULES_TARGET_NAME in the project is not a regular file"

  scan_rules_source "$src"
  grep -qF -e "shared-rules:begin" -e "shared-rules:end" "$src" \
    && die "the rules source contains the managed-block markers itself, which would corrupt the block"

  # The label is recorded in a committed file, so it never carries a machine
  # path: a path under SYSTEMS_ROOT is written with that name, anything else as
  # a bare file name.
  if [ -n "$root" ] && [ "${src#"$root"/}" != "$src" ]; then
    label="\$SYSTEMS_ROOT/${src#"$root"/}"
  else
    label="$(basename "$src")"
  fi
  RULES_SRC_LABEL="$label"
  RULES_SRC_SHA="$(hash_of "$src")"

  {
    printf '%s\n' "$RULES_BEGIN"
    printf '%s\n' "<!-- Managed by skillstack bin/lay-pack.sh --rules. Edit the source, not this block. -->"
    cat "$src"
    [ -n "$(tail -c 1 "$src")" ] && printf '\n'
    printf '%s\n' "$RULES_END"
  } > "$RULES_BLOCK_FILE" || die "could not build the rules block"
  RULES_BLOCK_SHA="$(hash_of "$RULES_BLOCK_FILE")"

  rec_block="$(printf '%s' "$manifest_json" | jq -r '.rules.blockSha256 // ""')"

  if [ ! -f "$RULES_AGENTS" ]; then
    RULES_ACTION="create"
    return 0
  fi

  begin_n="$(grep -cxF -e "$RULES_BEGIN" "$RULES_AGENTS")"
  end_n="$(grep -cxF -e "$RULES_END" "$RULES_AGENTS")"
  if [ "$begin_n" -eq 0 ] && [ "$end_n" -eq 0 ]; then
    RULES_ACTION="insert"
    return 0
  fi
  if [ "$begin_n" -ne 1 ] || [ "$end_n" -ne 1 ]; then
    die "$RULES_TARGET_NAME has $begin_n begin and $end_n end markers for the rules block; there must be exactly one of each. Fix the file by hand, then run again."
  fi
  RULES_BEGIN_LINE="$(grep -nxF -e "$RULES_BEGIN" "$RULES_AGENTS" | cut -d: -f1)"
  RULES_END_LINE="$(grep -nxF -e "$RULES_END" "$RULES_AGENTS" | cut -d: -f1)"
  [ "$RULES_BEGIN_LINE" -lt "$RULES_END_LINE" ] \
    || die "the end marker comes before the begin marker in $RULES_TARGET_NAME. Fix the file by hand, then run again."

  tail -n +"$RULES_BEGIN_LINE" "$RULES_AGENTS" | head -n $((RULES_END_LINE - RULES_BEGIN_LINE + 1)) > "$STAGE/current-block"
  cur_hash="$(hash_of "$STAGE/current-block")"

  if [ "$cur_hash" = "$RULES_BLOCK_SHA" ]; then
    RULES_ACTION="unchanged"
  elif [ -n "$rec_block" ] && [ "$cur_hash" = "$rec_block" ]; then
    RULES_ACTION="replace"
  else
    RULES_ACTION="skip"
    RULES_SKIPPED=1
    if [ -z "$rec_block" ]; then
      RULES_STATE="skipped: the block in $RULES_TARGET_NAME is not recorded in $MANIFEST_NAME"
    else
      RULES_STATE="skipped: the block in $RULES_TARGET_NAME was edited since it was laid down"
    fi
  fi
}

# Carries out RULES_ACTION and fills RULES_JSON (the manifest entry).
apply_rules() {
  local tmp="$STAGE/agents-new" stamp
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  case "$RULES_ACTION" in
    skip)
      # Keep what the manifest already says. Recording the edited hash would
      # silence the warning, so the old entry stays and the warning persists.
      RULES_JSON="$(printf '%s' "$manifest_json" | jq -c '.rules // null')"
      return 0 ;;
    unchanged)
      RULES_STATE="unchanged: $RULES_TARGET_NAME already holds this block"
      # Leave the recorded time alone when the record already says the same.
      stamp="$(printf '%s' "$manifest_json" | jq -r --arg s "$RULES_SRC_SHA" --arg b "$RULES_BLOCK_SHA" \
        'if (.rules.sourceSha256 == $s and .rules.blockSha256 == $b) then .rules.installedAt else "" end')"
      [ -n "$stamp" ] || stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" ;;
    create)
      RULES_STATE="created $RULES_TARGET_NAME with the rules block"
      [ "$DRY_RUN" -eq 1 ] && RULES_STATE="would create $RULES_TARGET_NAME with the rules block"
      [ "$DRY_RUN" -eq 1 ] || cat "$RULES_BLOCK_FILE" > "$RULES_AGENTS" || die "could not write $RULES_AGENTS" ;;
    insert)
      RULES_STATE="added the rules block at the top of $RULES_TARGET_NAME"
      [ "$DRY_RUN" -eq 1 ] && RULES_STATE="would add the rules block at the top of $RULES_TARGET_NAME"
      if [ "$DRY_RUN" -eq 0 ]; then
        { cat "$RULES_BLOCK_FILE"; printf '\n'; cat "$RULES_AGENTS"; } > "$tmp" || die "could not build the new $RULES_TARGET_NAME"
        cat "$tmp" > "$RULES_AGENTS" || die "could not write $RULES_AGENTS"
      fi ;;
    replace)
      RULES_STATE="updated the rules block in $RULES_TARGET_NAME"
      [ "$DRY_RUN" -eq 1 ] && RULES_STATE="would update the rules block in $RULES_TARGET_NAME"
      if [ "$DRY_RUN" -eq 0 ]; then
        {
          head -n $((RULES_BEGIN_LINE - 1)) "$RULES_AGENTS"
          cat "$RULES_BLOCK_FILE"
          tail -n +$((RULES_END_LINE + 1)) "$RULES_AGENTS"
        } > "$tmp" || die "could not build the new $RULES_TARGET_NAME"
        cat "$tmp" > "$RULES_AGENTS" || die "could not write $RULES_AGENTS"
      fi ;;
  esac

  RULES_JSON="$(jq -cn --arg f "$RULES_TARGET_NAME" --arg s "$RULES_SRC_LABEL" --arg sh "$RULES_SRC_SHA" \
    --arg bh "$RULES_BLOCK_SHA" --arg at "$stamp" \
    '{file:$f, source:$s, sourceSha256:$sh, blockSha256:$bh, installedAt:$at}')"
}

# ------------------------------------------------------------ what to do

if [ "$SKILLS_GIVEN" -eq 0 ] && [ "$RULES_GIVEN" -eq 0 ]; then
  resolve_source
  load_primary_set
  info "Refusing to guess which skills you want."
  info ""
  info "$SOURCE_REPO at ${PIN:0:12} lists ${#PS_NAMES[@]} skills in primary-set.txt:"
  for s in "${PS_NAMES[@]}"; do info "  $s"; done
  info ""
  info "Name the ones this project needs:"
  info "  $0 --skills <a,b,c> $TARGET"
  info "or lay the shared rules only:"
  info "  $0 --rules $TARGET"
  info ""
  info "There is deliberately no way to say 'all of them'. Taking every skill is"
  info "how one project ended up with 165 of its 194 tracked files being skill copies."
  exit 1
fi

# Validate the names before anything reads the source, so a bad name is refused
# the same way whether or not a clone is present.
SELECTED=()
if [ "$SKILLS_GIVEN" -eq 1 ]; then
  IFS=',' read -r -a raw_selected <<< "$SKILLS_ARG"
  for s in "${raw_selected[@]}"; do
    # Tolerate spaces after commas; refuse anything else unusual.
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    [ -z "$s" ] && continue
    valid_skill_name "$s" || die "'$s' is not a usable skill name"
    # Refuse a repeat rather than deduplicating it silently: a repeated name in
    # a hand-typed list usually means one of the names is wrong.
    for already in ${SELECTED[@]+"${SELECTED[@]}"}; do
      [ "$already" = "$s" ] && die "'$s' is named twice in --skills"
    done
    SELECTED+=("$s")
  done
  [ "${#SELECTED[@]}" -gt 0 ] || die "--skills named no usable skills"

  resolve_source
  load_primary_set
  for s in "${SELECTED[@]}"; do
    folder="$(folder_of "$s")" \
      || die "'$s' is not listed in primary-set.txt at commit ${PIN:0:12} of $SOURCE_REPO. Run without --skills to see the list."
    stage_skill "$s" "$folder"
  done
fi

# ------------------------------------------------------------------ lay down

raw_json="$(read_manifest)" || exit 1
assert_supported_schema "$raw_json"
assert_manifest_paths_ok "$raw_json"
manifest_json="$(upgrade_manifest "$raw_json")"

if [ "$RULES_GIVEN" -eq 1 ]; then
  prepare_rules
fi

# Before the first file lands, not after. The window between a skill being on
# disk and the working tree being ignored is a window in which a session can
# start and write a key into a directory git is watching.
if [ "$SKILLS_GIVEN" -eq 1 ]; then
  ensure_ignore_rule
fi

PREV_FILES="$(printf '%s' "$manifest_json" | jq '[.skills[]?.files[]?]')"

recorded_hash_for() {  # $1 = project-relative path, "" when not recorded
  printf '%s' "$PREV_FILES" | jq -r --arg p "$1" \
    'map(select(.path == $p)) | if length == 0 then "" else .[0].sha256 end'
}

NEW_FILES="[]"
copied=0; unchanged=0; skipped=0
SKIPPED_PATHS=()
UNSELECTED=()

if [ "$SKILLS_GIVEN" -eq 1 ]; then
  for skill in "${SELECTED[@]}"; do
    while IFS= read -r srcfile; do
      rel_in_skill="${srcfile#"$STAGE"/}"
      srchash="$(hash_of "$srcfile")"
      for dir in "${TARGET_DIRS[@]}"; do
        relpath="$dir/$rel_in_skill"
        dest="$TARGET/$relpath"
        recorded="$(recorded_hash_for "$relpath")"

        if [ -f "$dest" ]; then
          diskhash="$(hash_of "$dest")"
          if [ -z "$recorded" ]; then
            # Present but never recorded by this tool. Could be a hand-written
            # skill, or a copy made some other way. Refuse either way: this tool
            # only overwrites what it can prove it wrote.
            SKIPPED_PATHS+=("$relpath (present but not in $MANIFEST_NAME)")
            skipped=$((skipped+1))
            continue
          elif [ "$diskhash" != "$recorded" ]; then
            # Keep the ORIGINAL recorded hash, not the hash of the edited file.
            # Two things depend on that: the file stays tracked instead of
            # falling out of the manifest and being reported as an orphan, and
            # the mismatch persists, so every later run keeps warning until the
            # edit is resolved with --forget.
            NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg s "$skill" --arg p "$relpath" --arg h "$recorded" \
              '. + [{skill:$s, path:$p, sha256:$h}]')"
            SKIPPED_PATHS+=("$relpath (edited since it was laid down)")
            skipped=$((skipped+1))
            continue
          elif [ "$diskhash" = "$srchash" ]; then
            NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg s "$skill" --arg p "$relpath" --arg h "$srchash" \
              '. + [{skill:$s, path:$p, sha256:$h}]')"
            unchanged=$((unchanged+1))
            continue
          fi
        fi

        if [ "$DRY_RUN" -eq 0 ]; then
          mkdir -p "$(dirname "$dest")" || die "could not create $(dirname "$dest")"
          cp "$srcfile" "$dest" || die "could not write $dest"
          # Record the hash of what actually landed on disk, not the hash of the
          # source. They are the same unless the copy was diverted, and if it was
          # diverted the manifest has to say what is really there.
          landed="$(hash_of "$dest")"
        else
          landed="$srchash"
        fi
        NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg s "$skill" --arg p "$relpath" --arg h "$landed" \
          '. + [{skill:$s, path:$p, sha256:$h}]')"
        copied=$((copied+1))
      done
    done < <(find "$STAGE/$skill" -type f | sort)
  done

  # ------------------------------------------- recorded in a directory not targeted
  #
  # --targets agents writes one directory. Entries a selected skill already has
  # in the other directory are carried forward untouched, so narrowing the
  # target never drops a recorded file and turns it into an orphan.
  while IFS=$'\t' read -r sk p h; do
    [ -z "$p" ] && continue
    in_target=0
    for dir in "${TARGET_DIRS[@]}"; do
      case "$p" in "$dir"/*) in_target=1 ;; esac
    done
    [ "$in_target" -eq 1 ] && continue
    chosen=0
    for sel in "${SELECTED[@]}"; do [ "$sel" = "$sk" ] && chosen=1 && break; done
    [ "$chosen" -eq 1 ] || continue
    NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg s "$sk" --arg p "$p" --arg h "$h" '. + [{skill:$s, path:$p, sha256:$h}]')"
  done < <(printf '%s' "$manifest_json" | jq -r '.skills | to_entries[] | .key as $k | .value.files[]? | [$k, .path, .sha256] | @tsv')

  # ---------------------------------------------- recorded but no longer chosen
  #
  # --skills names the full set to keep current, so a skill the manifest records
  # and this run did not name is reported and KEPT, never silently dropped.
  # Dropping it would leave its files on disk and unrecorded, which is the exact
  # state every future run skips and --forget exists to dig people out of.
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    chosen=0
    for sel in "${SELECTED[@]}"; do [ "$sel" = "$s" ] && chosen=1 && break; done
    [ "$chosen" -eq 1 ] && continue
    UNSELECTED+=("$s")
  done < <(printf '%s' "$manifest_json" | jq -r '.skills | keys[]')
fi

# Files a previous run wrote that the source no longer ships. Reported, never
# deleted: the tool does not remove what it cannot prove is safe to remove, and
# a stale skill file is a smaller problem than a silent delete.
ORPHANS=()
if [ "$SKILLS_GIVEN" -eq 1 ]; then
  while IFS=$'\t' read -r sk p; do
    [ -z "$p" ] && continue
    chosen=0
    for sel in "${SELECTED[@]}"; do [ "$sel" = "$sk" ] && chosen=1 && break; done
    [ "$chosen" -eq 1 ] || continue
    still="$(printf '%s' "$NEW_FILES" | jq -r --arg p "$p" 'map(select(.path == $p)) | length')"
    [ "$still" != "0" ] && continue
    [ -f "$TARGET/$p" ] && ORPHANS+=("$p")
  done < <(printf '%s' "$manifest_json" | jq -r '.skills | to_entries[] | .key as $k | .value.files[]? | [$k, .path] | @tsv')
fi

if [ "$RULES_GIVEN" -eq 1 ]; then
  apply_rules
fi

# ------------------------------------------------------------------- report

PREFIX=""
[ "$DRY_RUN" -eq 1 ] && PREFIX="[dry-run] "

if [ "$SKILLS_GIVEN" -eq 1 ]; then
  recorded_total="$(printf '%s' "$NEW_FILES" | jq 'length')"

  info "${PREFIX}source:    $SOURCE_REPO @ ${PIN:0:12}"
  info "${PREFIX}skills:    ${#SELECTED[@]} selected, into ${#TARGET_DIRS[@]} directories (${TARGET_DIRS[*]})"
  info "${PREFIX}written:   $copied"
  info "${PREFIX}unchanged: $unchanged"
  info "${PREFIX}skipped:   $skipped"
  info "${PREFIX}recorded:  $recorded_total"
  info "${PREFIX}ignored:   $IGNORE_STATE"
fi
if [ "$RULES_GIVEN" -eq 1 ]; then
  info "${PREFIX}rules:     $RULES_STATE"
fi

# A run that placed nothing must not read like a run that placed something.
# "Finished, wrote nothing" and "finished, everything was already correct" have
# different causes and different remedies, and the counts above are identical
# in the one case a reader most needs to tell apart.
if [ "$SKILLS_GIVEN" -eq 1 ] && [ "$copied" -eq 0 ] && [ "$unchanged" -eq 0 ]; then
  info ""
  info "${PREFIX}NOTHING WAS PLACED. No file was written and none was already in place."
  info "${PREFIX}Every candidate file was skipped, or the selected skills contain no files."
fi

if [ "${#IGNORE_TRACKED[@]}" -gt 0 ]; then
  info ""
  info "ALREADY COMMITTED under ${IGNORE_RULE%/}, and an ignore rule does not untrack a file:"
  for p in "${IGNORE_TRACKED[@]}"; do info "  $p"; done
  info "Treat anything these hold as published. Rotate it, remove the files from"
  info "the branch, and decide separately what to do about the history."
fi

if [ "${#SKIPPED_PATHS[@]}" -gt 0 ]; then
  info ""
  info "Skipped, because overwriting would have destroyed a local change:"
  for p in "${SKIPPED_PATHS[@]}"; do info "  $p"; done
  info ""
  info "To take the pinned source's version of a skill and lose your edits to it:"
  info "  $0 --forget <skill-name> $TARGET"
fi

if [ "$RULES_SKIPPED" -eq 1 ]; then
  info ""
  info "The rules block in $RULES_TARGET_NAME was left alone, because it does not match what this tool last wrote."
  info "To take the shared version and lose your edits to the block, delete everything"
  info "from the begin marker to the end marker (both lines included) and run again."
fi

if [ "${#UNSELECTED[@]}" -gt 0 ]; then
  info ""
  info "Recorded in $MANIFEST_NAME and NOT named in --skills:"
  for s in "${UNSELECTED[@]}"; do info "  $s"; done
  info "They are still tracked and their files were left alone. If you meant to"
  info "keep them current, name them next time."
fi

if [ "${#ORPHANS[@]}" -gt 0 ]; then
  info ""
  info "The source no longer ships these, and they were left in place:"
  for p in "${ORPHANS[@]}"; do info "  $p"; done
  info "Delete them by hand if you want them gone."
fi

needs_decision() {
  [ "$skipped" -gt 0 ] || [ "${#UNSELECTED[@]}" -gt 0 ] || [ "${#IGNORE_TRACKED[@]}" -gt 0 ] || [ "$RULES_SKIPPED" -eq 1 ]
}

if [ "$DRY_RUN" -eq 1 ]; then
  info ""
  info "Dry run. Nothing was written and $MANIFEST_NAME was not updated."
  needs_decision && exit 2
  exit 0
fi

# ------------------------------------------------------------ write manifest

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SELECTED_ENTRIES="{}"
if [ "$SKILLS_GIVEN" -eq 1 ]; then
  for skill in "${SELECTED[@]}"; do
    SELECTED_ENTRIES="$(jq -n --argjson acc "$SELECTED_ENTRIES" --argjson nf "$NEW_FILES" \
      --arg k "$skill" --arg folder "$(folder_of "$skill")" --arg commit "$PIN" --arg at "$STAMP" \
      '$acc + {($k): {
         folder: $folder,
         commit: $commit,
         installedAt: $at,
         files: ([$nf[] | select(.skill == $k) | {path, sha256}] | sort_by(.path))
       }}')"
  done
fi

printf '%s' "$manifest_json" | jq -S \
  --arg repo "$SOURCE_REPO" \
  --arg commit "$PIN" \
  --argjson skillsrun "$([ "$SKILLS_GIVEN" -eq 1 ] && echo true || echo false)" \
  --argjson entries "$SELECTED_ENTRIES" \
  --argjson rules "$RULES_JSON" \
  --argjson schema "$SCHEMA_VERSION" \
  '.schemaVersion = $schema
   | del(.packs)
   | .source = ((.source // {}) + {repo: $repo})
   | (if $skillsrun then .source.commit = $commit else . end)
   | .skills = ((.skills // {}) + $entries)
   | (if $rules != null then .rules = $rules else . end)' > "$MANIFEST.tmp" || die "could not write $MANIFEST_NAME"

# The removed schema 3 field is rejected by a reader rather than ignored, so a
# manifest carrying it fails loudly. Never write one.
if jq -e '[.skills[].files[]? | select(has("shippedSha256"))] | length > 0' "$MANIFEST.tmp" >/dev/null 2>&1; then
  rm -f "$MANIFEST.tmp"
  die "refusing to write a manifest carrying shippedSha256"
fi

mv "$MANIFEST.tmp" "$MANIFEST" || die "could not replace $MANIFEST_NAME"

info ""
if [ "$SKILLS_GIVEN" -eq 1 ]; then
  info "Recorded ${#SELECTED[@]} skills from $SOURCE_REPO at ${PIN:0:12} in $MANIFEST_NAME."
else
  info "Recorded the rules block in $MANIFEST_NAME."
fi
info "Commit what was written and $MANIFEST_NAME so it reaches a cloud agent."

needs_decision && exit 2
exit 0
