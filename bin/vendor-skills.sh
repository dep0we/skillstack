#!/bin/bash
# Vendor a third-party agent skill stack into a project repository.
#
# Copies a skills folder out of an upstream git repo into the three skill
# directories a project needs, so the skills travel with the code:
#
#   .claude/skills/    read by Claude Code
#   .cursor/skills/    read by Cursor
#   .agents/skills/    read by Cursor cloud agents and Codex
#
# Why copy instead of installing a plugin: a Cursor cloud agent clones the
# repository into an isolated VM with no access to your home directory, so a
# plugin installed on a laptop never reaches it. Anything that must reach a
# cloud agent has to be committed into the project repo.
#
# Always takes upstream's latest commit on the default branch. It does not pin,
# because vendoring already is the pin: once the copied files are committed,
# that project's skills are frozen in its git history until this script is run
# again. What it does instead is RECORD the commit it took, in a manifest at
# the project root, so you can always tell what a project actually has.
#
# Hand edits are never overwritten. The manifest stores a hash of every file at
# the moment it was vendored. On a later run, a destination file whose hash no
# longer matches is reported and skipped, and the script exits non-zero.
# --forget <skill> is the deliberate way past it: it clears the hand-edit flag
# on that skill so the next run overwrites it with upstream's version. Nothing
# is ever deleted, by either path.
#
# This script names its upstream default on purpose and lives here on purpose.
# It does not belong in the kit repo: kit is agnostic about what runs alongside
# it and its repo never names a third-party stack. The current pairing is
# recorded in the vault at system/kit/stack.md.
#
# Usage: ./bin/vendor-skills.sh <path-to-project>
#        ./bin/vendor-skills.sh --dry-run <path-to-project>
#        ./bin/vendor-skills.sh --repo <git-url> --subdir <path> <path-to-project>
#        ./bin/vendor-skills.sh --forget <skill-name> <path-to-project>
#        ./bin/vendor-skills.sh --list <path-to-project>
#
# Exit codes: 0 all good, 1 usage or environment error, 2 finished but one or
# more files were skipped because they were hand-edited.

set -uo pipefail

# ---------------------------------------------------------------- SUPERSEDED
#
# This script is kept as a readable reference for the manifest mechanics that
# were carried forward, and it must not be run against a project again.
#
# Two reasons it is dangerous now rather than merely out of date. It clones
# upstream's latest default branch, so what it copies is whatever upstream said
# today and nobody reviewed it. And it writes the schema 1 manifest, keyed by
# repository URL with no pack concept, straight over a schema 4 manifest,
# destroying the record that a gate resolves published hashes against.
#
# Use bin/lay-pack.sh instead.
# There is deliberately no way past this. An environment override "so the tests
# can still exercise it" is a bypass wearing a test's clothes: the guarded path
# rots, the override becomes the only route through, and every test takes it.
cat >&2 <<'SUPERSEDED'
error: vendor-skills.sh is superseded and refuses to run.

It clones upstream's latest default branch rather than copying the reviewed
pack in this repository, and it writes a schema 1 manifest over a schema 4 one.

Use instead:
  bin/lay-pack.sh --pack <name> --skills a,b,c <project>

Run bin/lay-pack.sh with no --skills to see what a pack contains.
SUPERSEDED
exit 1

DEFAULT_REPO="https://github.com/obra/superpowers"
DEFAULT_SUBDIR="skills"
MANIFEST_NAME=".vendored-skills.json"
SKILL_DIRS=(".claude/skills" ".cursor/skills" ".agents/skills")

REPO="$DEFAULT_REPO"
SUBDIR="$DEFAULT_SUBDIR"
TARGET=""
DRY_RUN=0
FORGET=""
LIST_ONLY=0
TMPDIR_CLONE=""

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

cleanup() {
  [ -n "$TMPDIR_CLONE" ] && [ -d "$TMPDIR_CLONE" ] && rm -rf "$TMPDIR_CLONE"
}
trap cleanup EXIT

usage() {
  sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

# ---------------------------------------------------------------- arguments

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --repo)    REPO="${2:-}"; [ -n "$REPO" ] || die "--repo needs a git URL"; shift 2 ;;
    --subdir)  SUBDIR="${2:-}"; [ -n "$SUBDIR" ] || die "--subdir needs a path"; shift 2 ;;
    --forget)  FORGET="${2:-}"; [ -n "$FORGET" ] || die "--forget needs a skill name"; shift 2 ;;
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
  || die "$TARGET is not a git repository. Vendored skills must be committed to travel."

# ------------------------------------------------------- manifest accessors
# Shape:
# { "vendored": { "<repo-url>": {
#     "subdir": "skills", "commit": "<sha>", "vendoredAt": "<iso8601>",
#     "files": { "<path relative to project root>": "<sha256>" } } } }

read_manifest() {
  if [ -f "$MANIFEST" ]; then
    jq -e . "$MANIFEST" >/dev/null 2>&1 \
      || die "$MANIFEST_NAME exists but is not valid JSON. Fix or delete it, then re-run."
    cat "$MANIFEST"
  else
    echo '{"vendored":{}}'
  fi
}

# --list reads, --forget writes. Silently doing only the read while the caller
# believes the write happened is the worst of the three options, so refuse.
if [ "$LIST_ONLY" -eq 1 ] && [ -n "$FORGET" ]; then
  die "--list and --forget do different things; pass one at a time"
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  if [ ! -f "$MANIFEST" ]; then
    info "No skills vendored into $TARGET (no $MANIFEST_NAME)."
    exit 0
  fi
  read_manifest | jq -r '
    .vendored | to_entries[] |
    "\(.key)\n  subdir:     \(.value.subdir)\n  commit:     \(.value.commit)\n  vendored:   \(.value.vendoredAt)\n  files:      \(.value.files | length)"'
  exit 0
fi

if [ -n "$FORGET" ]; then
  # "Give up my edits to this skill, take upstream's version next run."
  #
  # It does NOT drop the files from the manifest. An unrecorded file is one
  # this script refuses to touch, so dropping them would guarantee the exact
  # opposite of what was asked. Instead it re-records each file at its CURRENT
  # hash, which makes the edit invisible to the hand-edit check. The next
  # vendor run then sees a tracked, unmodified file that differs from upstream
  # and overwrites it normally. Nothing is deleted here.
  before="$(read_manifest)"
  matched=0; missing=0; adopted=0
  after="$before"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ "$(printf '%s' "$p" | cut -d/ -f3)" = "$FORGET" ] || continue
    matched=$((matched+1))
    if [ -f "$TARGET/$p" ]; then
      h="$(hash_of "$TARGET/$p")"
      after="$(printf '%s' "$after" | jq --arg r "$REPO" --arg p "$p" --arg h "$h" \
        '.vendored[$r].files[$p]=$h')"
    else
      # Gone from disk. Drop it so the next run re-copies it fresh.
      missing=$((missing+1))
      after="$(printf '%s' "$after" | jq --arg r "$REPO" --arg p "$p" \
        'del(.vendored[$r].files[$p])')"
    fi
  done < <(printf '%s' "$before" | jq -r --arg r "$REPO" '.vendored[$r].files // {} | keys[]')

  # Also adopt files sitting in this skill's directories that the manifest has
  # never heard of. Without this, --forget cannot reach the very files that
  # send people to it. Two ways a file gets into that state: upstream dropped
  # it (so a previous run removed it from the manifest and left it on disk)
  # and then shipped it again, or it was copied in by some other means. Either
  # way the vendor run reports it as "present but not in the manifest" and
  # skips it forever, and a --forget that only walked the manifest was
  # powerless against exactly the case it advertises.
  #
  # Recording at the CURRENT hash is what makes the next run overwrite it. It
  # does not delete anything, and a file upstream does not ship is untouched
  # by the copy loop regardless.
  for dir in "${SKILL_DIRS[@]}"; do
    [ -d "$TARGET/$dir/$FORGET" ] || continue
    while IFS= read -r f; do
      rel="${f#"$TARGET"/}"
      known="$(printf '%s' "$after" | jq -r --arg r "$REPO" --arg p "$rel" '.vendored[$r].files[$p] // ""')"
      [ -n "$known" ] && continue
      h="$(hash_of "$f")"
      after="$(printf '%s' "$after" | jq --arg r "$REPO" --arg p "$rel" --arg h "$h" \
        '.vendored[$r].files[$p]=$h')"
      matched=$((matched+1)); adopted=$((adopted+1))
    done < <(find "$TARGET/$dir/$FORGET" -type f | sort)
  done

  [ "$matched" -gt 0 ] || die "no files on disk or in the manifest matched skill '$FORGET'"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] would clear the hand-edit flag on $matched files for '$FORGET'"
    exit 0
  fi
  printf '%s\n' "$after" > "$MANIFEST"
  info "Cleared the hand-edit flag on $matched files for '$FORGET'."
  [ "$adopted" -gt 0 ] && info "($adopted were on disk but unrecorded, and are now tracked.)"
  [ "$missing" -gt 0 ] && info "($missing were already gone from disk and will be re-copied.)"
  info "Nothing was deleted. The next run overwrites them with upstream's version."
  exit 0
fi

# -------------------------------------------------------------- fetch upstream

TMPDIR_CLONE="$(mktemp -d "${TMPDIR:-/tmp}/vendor-skills.XXXXXX")" \
  || die "could not create a temporary directory"

info "Fetching $REPO ..."
git clone --quiet --depth 1 "$REPO" "$TMPDIR_CLONE/src" \
  || die "clone failed: $REPO"

COMMIT="$(git -C "$TMPDIR_CLONE/src" rev-parse HEAD)" || die "could not read upstream commit"
SRC="$TMPDIR_CLONE/src/$SUBDIR"
[ -d "$SRC" ] || die "'$SUBDIR' does not exist in $REPO"

# Skills are directories directly under the subdir. A loose file there is not a
# skill and is skipped rather than silently flattened into every target.
SKILLS=()
while IFS= read -r d; do SKILLS+=("$(basename "$d")"); done < <(find "$SRC" -mindepth 1 -maxdepth 1 -type d | sort)
[ "${#SKILLS[@]}" -gt 0 ] || die "no skill directories found under $REPO/$SUBDIR"

info "Upstream commit ${COMMIT:0:12}, ${#SKILLS[@]} skills."
info ""

# ------------------------------------------------------------------- vendor

MANIFEST_JSON="$(read_manifest)"
PREV_FILES="$(printf '%s' "$MANIFEST_JSON" | jq --arg r "$REPO" '.vendored[$r].files // {}')"
PREV_COMMIT="$(printf '%s' "$MANIFEST_JSON" | jq -r --arg r "$REPO" '.vendored[$r].commit // ""')"

if [ -n "$PREV_COMMIT" ] && [ "$PREV_COMMIT" = "$COMMIT" ]; then
  info "Already at this commit. Re-copying anyway to repair any missing files."
  info ""
fi

NEW_FILES="{}"
copied=0; unchanged=0; skipped=0
SKIPPED_PATHS=()

for skill in "${SKILLS[@]}"; do
  while IFS= read -r srcfile; do
    rel_in_skill="${srcfile#"$SRC"/}"
    for dir in "${SKILL_DIRS[@]}"; do
      relpath="$dir/$rel_in_skill"
      dest="$TARGET/$relpath"
      newhash="$(hash_of "$srcfile")"
      recorded="$(printf '%s' "$PREV_FILES" | jq -r --arg p "$relpath" '.[$p] // ""')"

      if [ -f "$dest" ]; then
        diskhash="$(hash_of "$dest")"
        if [ -z "$recorded" ]; then
          # Present but never recorded by this script. Could be a hand-written
          # skill, or a copy made some other way. Refuse either way.
          SKIPPED_PATHS+=("$relpath (present but not in $MANIFEST_NAME)")
          skipped=$((skipped+1))
          continue
        elif [ "$diskhash" != "$recorded" ]; then
          # Keep the ORIGINAL recorded hash in the manifest, not the hash of
          # the edited file. Two things depend on this: the file stays tracked
          # instead of silently falling out and being reported as removed
          # upstream, and the mismatch persists, so every later run keeps
          # warning until the edit is resolved with --forget.
          NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg p "$relpath" --arg h "$recorded" '.[$p]=$h')"
          SKIPPED_PATHS+=("$relpath (edited since it was vendored)")
          skipped=$((skipped+1))
          continue
        elif [ "$diskhash" = "$newhash" ]; then
          NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg p "$relpath" --arg h "$newhash" '.[$p]=$h')"
          unchanged=$((unchanged+1))
          continue
        fi
      fi

      if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$(dirname "$dest")" || die "could not create $(dirname "$dest")"
        cp "$srcfile" "$dest" || die "could not write $dest"
      fi
      NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg p "$relpath" --arg h "$newhash" '.[$p]=$h')"
      copied=$((copied+1))
    done
  done < <(find "$SRC/$skill" -type f | sort)
done

# Files this script wrote on a previous run that upstream no longer ships.
# Reported, never deleted: the script does not remove what it cannot prove is
# safe to remove, and a stale skill is a smaller problem than a silent delete.
ORPHANS=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  still="$(printf '%s' "$NEW_FILES" | jq -r --arg p "$p" '.[$p] // ""')"
  [ -n "$still" ] && continue
  [ -f "$TARGET/$p" ] && ORPHANS+=("$p")
done < <(printf '%s' "$PREV_FILES" | jq -r 'keys[]')

# ------------------------------------------------------------------- report

PREFIX=""
[ "$DRY_RUN" -eq 1 ] && PREFIX="[dry-run] "

info "${PREFIX}written:   $copied"
info "${PREFIX}unchanged: $unchanged"
info "${PREFIX}skipped:   $skipped"

if [ "${#SKIPPED_PATHS[@]}" -gt 0 ]; then
  info ""
  info "Skipped, because overwriting would have destroyed a local change:"
  for p in "${SKIPPED_PATHS[@]}"; do info "  $p"; done
  info ""
  info "To take upstream's version of a skill and lose your edits to it:"
  info "  $0 --forget <skill-name> $TARGET"
fi

if [ "${#ORPHANS[@]}" -gt 0 ]; then
  info ""
  info "Upstream no longer ships these, and they were left in place:"
  for p in "${ORPHANS[@]}"; do info "  $p"; done
  info "Delete them by hand if you want them gone."
fi

if [ "$DRY_RUN" -eq 1 ]; then
  info ""
  info "Dry run. Nothing was written and $MANIFEST_NAME was not updated."
  [ "$skipped" -gt 0 ] && exit 2
  exit 0
fi

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s' "$MANIFEST_JSON" | jq \
  --arg repo "$REPO" --arg subdir "$SUBDIR" --arg commit "$COMMIT" \
  --arg at "$STAMP" --argjson files "$NEW_FILES" \
  '.vendored[$repo] = {subdir:$subdir, commit:$commit, vendoredAt:$at, files:$files}' \
  > "$MANIFEST.tmp" || die "could not write $MANIFEST_NAME"
mv "$MANIFEST.tmp" "$MANIFEST" || die "could not replace $MANIFEST_NAME"

info ""
info "Recorded ${COMMIT:0:12} in $MANIFEST_NAME."
info "Commit the skill directories and $MANIFEST_NAME so they reach cloud agents."

[ "$skipped" -gt 0 ] && exit 2
exit 0
