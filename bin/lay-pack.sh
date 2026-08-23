#!/bin/bash
# Lay a corrected skill pack from this repository into a project repository.
#
# This replaces vendor-skills.sh. The difference that matters: this copies a
# reviewed snapshot that already lives in this repository, at packs/<pack>/.
# It never clones upstream, never reaches the network, and never corrects
# anything at lay-down time. Corrections are decided once, here, when a pack
# version is cut. See docs/SPEC.md sections 2 and 3.
#
# Why the files are copied into the project at all, rather than installed:
# a cloud coding agent clones the repository into an isolated VM with no
# access to the maintainer's laptop, so anything that has to reach that agent
# has to be committed into the project repository itself.
#
# Usage:
#   bin/lay-pack.sh --pack <name> --skills a,b,c <project>
#   bin/lay-pack.sh --pack <name> --skills a,b,c --dry-run <project>
#   bin/lay-pack.sh --pack <name> --forget <skill> <project>
#   bin/lay-pack.sh --list <project>
#
# --skills is required and has no default. Taking every skill in the pack is
# how one project ended up with 165 of its 194 tracked files being skill
# copies. Refusing to guess is the feature, not an omission.
#
# Exit codes:
#   0  finished, nothing was skipped
#   1  usage, environment, or an integrity refusal; nothing was written
#   2  finished, but one or more files were skipped or left unselected

set -uo pipefail

# ---------------------------------------------------------------- constants

MANIFEST_NAME=".vendored-skills.json"
SCHEMA_VERSION=4
MANIFEST_SOURCE="skillstack"

# THE ONE PLACE DESTINATION DIRECTORIES ARE NAMED.
#
# This list must equal the allowed-location prefixes in docs/SPEC.md section 4.
# A path the gate does not allow is not skipped by it: the whole manifest is
# rejected and nothing is excluded for any pack. So adding a directory here
# without changing the specification turns the exclusion mechanism off
# entirely, silently, for every project.
#
# Which directories each reader actually loads was measured, not read from
# documentation. See docs/decisions/2026-08-23-skill-directories-measured.md.
DEST_DIRS=(".claude/skills" ".agents/skills")

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

# ------------------------------------------------------------ where we live
#
# The pack is resolved next to THIS SCRIPT, never next to the caller. The pack
# content travels with the script, so the script's own location is the correct
# root. Stated because the neighbouring repository has a lesson about a script
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
PACKS_ROOT="$SKILLSTACK_ROOT/packs"

# ---------------------------------------------------------------- arguments

PACK=""
SKILLS_ARG=""
TARGET=""
DRY_RUN=0
FORGET=""
LIST_ONLY=0
SKILLS_GIVEN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --pack)    PACK="${2:-}"; [ -n "$PACK" ] || die "--pack needs a pack name"; shift 2 ;;
    --skills)  SKILLS_ARG="${2:-}"; SKILLS_GIVEN=1
               [ -n "$SKILLS_ARG" ] || die "--skills needs at least one skill name"; shift 2 ;;
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
if [ "$SKILLS_GIVEN" -eq 1 ] && [ -n "$FORGET" ]; then
  die "--skills and --forget do different things; pass one at a time"
fi

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

# --------------------------------------------------------------- manifest io

read_manifest() {
  if [ -f "$MANIFEST" ]; then
    jq -e . "$MANIFEST" >/dev/null 2>&1 \
      || die "$MANIFEST_NAME exists but is not valid JSON. Fix or delete it, then re-run."
    cat "$MANIFEST"
  else
    printf '{"schemaVersion":%s,"packs":{}}' "$SCHEMA_VERSION"
  fi
}

# A schema this tool does not write must not be silently rewritten. Schema 1 is
# what vendor-skills.sh produced and what every real manifest holds today; it is
# keyed by repository URL under "vendored" and has no pack concept, so merging
# into it would produce a file that is neither shape.
assert_supported_schema() {
  local found
  found="$(printf '%s' "$1" | jq -r '.schemaVersion // "none"')"
  [ "$found" = "$SCHEMA_VERSION" ] && return 0
  if [ "$found" = "none" ] || [ "$found" = "1" ]; then
    die "$MANIFEST_NAME is schema ${found/none/1 (unversioned)}, written by the superseded vendor-skills.sh.
This tool writes schema $SCHEMA_VERSION and will not rewrite an older one in place.
Move the old file aside and re-run to lay the pack down fresh."
  fi
  die "$MANIFEST_NAME declares schemaVersion $found, which this tool does not write. Refusing to touch it."
}

# ------------------------------------------------------------------- --list

if [ "$LIST_ONLY" -eq 1 ]; then
  if [ ! -f "$MANIFEST" ]; then
    info "No pack has been laid into $TARGET (no $MANIFEST_NAME)."
    exit 0
  fi
  manifest_json="$(read_manifest)" || exit 1
  assert_supported_schema "$manifest_json"
  assert_manifest_paths_ok "$manifest_json"
  count="$(printf '%s' "$manifest_json" | jq '.packs | length')"
  if [ "$count" -eq 0 ]; then
    info "$MANIFEST_NAME is present and records no packs."
    exit 0
  fi
  printf '%s' "$manifest_json" | jq -r '
    .packs | to_entries[] |
    "\(.key)\n  packVersion: \(.value.packVersion)\n  packCommit:  \(.value.packCommit)\n  upstream:    \(.value.upstream.repo) @ \(.value.upstream.commit)\n  installed:   \(.value.installedAt)\n  skills:      \(.value.skills | join(", "))\n  files:       \(.value.files | length)"'
  exit 0
fi

# ------------------------------------------------------- pack identity rules
#
# Pack name and version are interpolated into a release tag and a repository
# path by the gate that reads the manifest this tool writes. Two packs that
# produce one tag is the failure these rules exist to stop, and both halves are
# needed: the version rule alone rejects "bar-v1.0", the name rule alone
# rejects "foo-vbar". See docs/SPEC.md, "Naming grammar".

valid_pack_name() {
  printf '%s' "$1" | grep -Eq '^[a-z][a-z0-9]*(-[a-z0-9]+)*$' || return 1
  printf '%s' "$1" | grep -Eq -- '-v[0-9]' && return 1
  return 0
}

valid_pack_version() {
  printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

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

# assert_paths_allowed <json array of {path,sha256}> <allowed skill names...>
#
# Every path about to be recorded has to be <one of DEST_DIRS>/<a skill this
# run accounts for>/<file>. This is the same rule the gate applies, and a path
# failing it is not skipped there: the whole manifest is rejected and nothing
# is excluded for any pack, so one bad entry turns exclusion off for the whole
# project.
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
      /*) die "refusing this manifest: '$p' is absolute, and absolute paths are never pack content" ;;
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

# assert_manifest_paths_ok <manifest json>
#
# Applied to the manifest AS READ, before anything is decided from it, and to
# every pack in it rather than only the one being laid down.
#
# Reading is the right moment. A check placed later sees only the entries that
# survive to be written, and an entry whose path is malformed enough does not
# survive: the carry-forward matches on the skill segment, so a path with no
# valid skill segment is quietly dropped rather than refused. Dropping fails
# safe, since an unrecorded file is never excluded by a gate, but it fails
# silently, and a manifest that changed under someone without a word is how a
# project stops being able to say what it holds.
assert_manifest_paths_ok() {
  local json="$1" k files sk
  local skills
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    files="$(printf '%s' "$json" | jq --arg k "$k" '.packs[$k].files // []')"
    skills=()
    while IFS= read -r sk; do [ -n "$sk" ] && skills+=("$sk"); done \
      < <(printf '%s' "$json" | jq -r --arg k "$k" '.packs[$k].skills // [] | .[]')
    assert_paths_allowed "$files" ${skills[@]+"${skills[@]}"}
  done < <(printf '%s' "$json" | jq -r '.packs // {} | keys[]')
}

[ -n "$PACK" ] || die "--pack is required. Available: $(ls -1 "$PACKS_ROOT" 2>/dev/null | tr '\n' ' ')"
valid_pack_name "$PACK" \
  || die "pack name '$PACK' fails the naming grammar (lowercase, digits and single hyphens, and never '-v' followed by a digit)"

PACK_DIR="$PACKS_ROOT/$PACK"
[ -d "$PACK_DIR" ] || die "no such pack: $PACK (looked in $PACKS_ROOT)"
PACK_JSON="$PACK_DIR/pack.json"
[ -f "$PACK_JSON" ] || die "$PACK has no pack.json"
jq -e . "$PACK_JSON" >/dev/null 2>&1 || die "$PACK/pack.json is not valid JSON"

PACK_VERSION="$(jq -r '.packVersion // ""' "$PACK_JSON")"
[ -n "$PACK_VERSION" ] || die "$PACK/pack.json has no packVersion"
valid_pack_version "$PACK_VERSION" \
  || die "packVersion '$PACK_VERSION' fails the naming grammar (exactly three numeric components, no prefix or suffix)"

UPSTREAM_REPO="$(jq -r '.upstream.repo // ""' "$PACK_JSON")"
UPSTREAM_SUBDIR="$(jq -r '.upstream.subdir // ""' "$PACK_JSON")"
UPSTREAM_COMMIT="$(jq -r '.upstream.commit // ""' "$PACK_JSON")"
[ -n "$UPSTREAM_REPO" ] && [ -n "$UPSTREAM_SUBDIR" ] && [ -n "$UPSTREAM_COMMIT" ] \
  || die "$PACK/pack.json is missing part of its upstream block"

PACK_SKILLS_DIR="$PACK_DIR/skills"
[ -d "$PACK_SKILLS_DIR" ] || die "$PACK has no skills/ directory"

# --------------------------------------------------- the pack commit is real
#
# packCommit records the commit this pack version was cut from, and a gate
# resolves published hashes against a release built from that content. With
# uncommitted changes under packs/, that field names a commit whose content is
# not what was just copied, and the disagreement surfaces later as a hash
# mismatch in someone else's repository.

PACK_COMMIT="$(git -C "$SKILLSTACK_ROOT" rev-parse HEAD 2>/dev/null)" \
  || die "cannot read the current commit of $SKILLSTACK_ROOT"

if [ -n "$(git -C "$SKILLSTACK_ROOT" status --porcelain -- "packs/$PACK" 2>/dev/null)" ]; then
  die "packs/$PACK has uncommitted changes.
packCommit would record $PACK_COMMIT, which is not the content about to be copied.
Commit the pack first, then lay it down."
fi

# ------------------------------------------------------------------ --forget

if [ -n "$FORGET" ]; then
  valid_skill_name "$FORGET" || die "'$FORGET' is not a usable skill name"
  manifest_json="$(read_manifest)" || exit 1
  assert_supported_schema "$manifest_json"
  assert_manifest_paths_ok "$manifest_json"

  # "Give up my edits to this skill, take the pack's version next run."
  #
  # It does NOT drop the files from the manifest. An unrecorded file is one
  # this script refuses to touch, so dropping them would guarantee the exact
  # opposite of what was asked. Instead each file is re-recorded at its CURRENT
  # hash, which makes the edit invisible to the hand-edit check, so the next
  # run sees a tracked, unmodified file that differs from the pack and
  # overwrites it normally. Nothing is deleted here, by any path.
  before="$manifest_json"
  after="$before"
  matched=0; missing=0; adopted=0

  while IFS= read -r p; do
    [ -z "$p" ] && continue
    # The skill directory name is the third segment: <dir>/skills/<name>/<file>
    [ "$(printf '%s' "$p" | cut -d/ -f3)" = "$FORGET" ] || continue
    matched=$((matched+1))
    if [ -f "$TARGET/$p" ]; then
      h="$(hash_of "$TARGET/$p")"
      after="$(printf '%s' "$after" | jq --arg k "$PACK" --arg p "$p" --arg h "$h" \
        '.packs[$k].files = ((.packs[$k].files // []) | map(if .path == $p then .sha256 = $h else . end))')"
    else
      # Gone from disk. Drop the entry so the next run re-copies it fresh.
      missing=$((missing+1))
      after="$(printf '%s' "$after" | jq --arg k "$PACK" --arg p "$p" \
        '.packs[$k].files = ((.packs[$k].files // []) | map(select(.path != $p)))')"
    fi
  done < <(printf '%s' "$before" | jq -r --arg k "$PACK" '.packs[$k].files // [] | .[].path')

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
      known="$(printf '%s' "$after" | jq -r --arg k "$PACK" --arg p "$rel" \
        '(.packs[$k].files // []) | map(select(.path == $p)) | length')"
      [ "$known" != "0" ] && continue
      h="$(hash_of "$f")"
      after="$(printf '%s' "$after" | jq --arg k "$PACK" --arg p "$rel" --arg h "$h" \
        '.packs[$k].files = ((.packs[$k].files // []) + [{path:$p, sha256:$h}])')"
      matched=$((matched+1)); adopted=$((adopted+1))
    done < <(find "$TARGET/$dir/$FORGET" -type f | sort)
  done

  [ "$matched" -gt 0 ] || die "no files on disk or in $MANIFEST_NAME matched skill '$FORGET' for pack '$PACK'"

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
  info "Nothing was deleted. The next run overwrites them with the pack's version."
  exit 0
fi

# ------------------------------------------------------------ skill selection

AVAILABLE=()
while IFS= read -r d; do AVAILABLE+=("$(basename "$d")"); done \
  < <(find "$PACK_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
[ "${#AVAILABLE[@]}" -gt 0 ] || die "pack '$PACK' contains no skill directories"

if [ "$SKILLS_GIVEN" -eq 0 ]; then
  info "Refusing to guess which skills you want."
  info ""
  info "Pack '$PACK' at $PACK_VERSION contains ${#AVAILABLE[@]} skills:"
  for s in "${AVAILABLE[@]}"; do info "  $s"; done
  info ""
  info "Name the ones this project needs:"
  info "  $0 --pack $PACK --skills <a,b,c> $TARGET"
  info ""
  info "There is deliberately no way to say 'all of them'. Taking every skill is"
  info "how one project ended up with 165 of its 194 tracked files being skill copies."
  exit 1
fi

SELECTED=()
IFS=',' read -r -a raw_selected <<< "$SKILLS_ARG"
for s in "${raw_selected[@]}"; do
  # Tolerate spaces after commas; refuse anything else unusual.
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  [ -z "$s" ] && continue
  valid_skill_name "$s" || die "'$s' is not a usable skill name"
  [ -d "$PACK_SKILLS_DIR/$s" ] \
    || die "pack '$PACK' has no skill named '$s'. Run without --skills to see the list."
  # Refuse a repeat rather than deduplicating it silently: a repeated name in
  # a hand-typed list usually means one of the names is wrong.
  for already in "${SELECTED[@]:-}"; do
    [ "$already" = "$s" ] && die "'$s' is named twice in --skills"
  done
  SELECTED+=("$s")
done
[ "${#SELECTED[@]}" -gt 0 ] || die "--skills named no usable skills"

# ------------------------------------------------------------------ lay down

manifest_json="$(read_manifest)" || exit 1
assert_supported_schema "$manifest_json"
assert_manifest_paths_ok "$manifest_json"

PREV_FILES="$(printf '%s' "$manifest_json" | jq --arg k "$PACK" '.packs[$k].files // []')"
PREV_SKILLS="$(printf '%s' "$manifest_json" | jq -r --arg k "$PACK" '.packs[$k].skills // [] | .[]')"

recorded_hash_for() {  # $1 = project-relative path, "" when not recorded
  printf '%s' "$PREV_FILES" | jq -r --arg p "$1" \
    'map(select(.path == $p)) | if length == 0 then "" else .[0].sha256 end'
}

NEW_FILES="[]"
copied=0; unchanged=0; skipped=0
SKIPPED_PATHS=()

for skill in "${SELECTED[@]}"; do
  while IFS= read -r srcfile; do
    rel_in_skill="${srcfile#"$PACK_SKILLS_DIR"/}"
    srchash="$(hash_of "$srcfile")"
    for dir in "${DEST_DIRS[@]}"; do
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
          NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg p "$relpath" --arg h "$recorded" \
            '. + [{path:$p, sha256:$h}]')"
          SKIPPED_PATHS+=("$relpath (edited since it was laid down)")
          skipped=$((skipped+1))
          continue
        elif [ "$diskhash" = "$srchash" ]; then
          NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg p "$relpath" --arg h "$srchash" \
            '. + [{path:$p, sha256:$h}]')"
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
      NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg p "$relpath" --arg h "$landed" \
        '. + [{path:$p, sha256:$h}]')"
      copied=$((copied+1))
    done
  done < <(find "$PACK_SKILLS_DIR/$skill" -type f | sort)
done

# ---------------------------------------------- recorded but no longer chosen
#
# --skills names the full set for this pack, so a skill the manifest records
# and this run did not name is reported and KEPT, never silently dropped.
# Dropping it would leave its files on disk and unrecorded, which is the exact
# state every future run skips and --forget exists to dig people out of.

UNSELECTED=()
while IFS= read -r s; do
  [ -z "$s" ] && continue
  chosen=0
  for sel in "${SELECTED[@]}"; do [ "$sel" = "$s" ] && chosen=1 && break; done
  [ "$chosen" -eq 1 ] && continue
  UNSELECTED+=("$s")
  # Carry its recorded entries forward untouched.
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ "$(printf '%s' "$p" | cut -d/ -f3)" = "$s" ] || continue
    h="$(recorded_hash_for "$p")"
    NEW_FILES="$(printf '%s' "$NEW_FILES" | jq --arg p "$p" --arg h "$h" '. + [{path:$p, sha256:$h}]')"
  done < <(printf '%s' "$PREV_FILES" | jq -r '.[].path')
done <<< "$PREV_SKILLS"

# Files a previous run wrote that this pack version no longer ships. Reported,
# never deleted: the tool does not remove what it cannot prove is safe to
# remove, and a stale skill file is a smaller problem than a silent delete.
ORPHANS=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  still="$(printf '%s' "$NEW_FILES" | jq -r --arg p "$p" 'map(select(.path == $p)) | length')"
  [ "$still" != "0" ] && continue
  [ -f "$TARGET/$p" ] && ORPHANS+=("$p")
done < <(printf '%s' "$PREV_FILES" | jq -r '.[].path')

# ------------------------------------------------------------------- report

PREFIX=""
[ "$DRY_RUN" -eq 1 ] && PREFIX="[dry-run] "

recorded_total="$(printf '%s' "$NEW_FILES" | jq 'length')"

info "${PREFIX}pack:      $PACK $PACK_VERSION (${PACK_COMMIT:0:12})"
info "${PREFIX}skills:    ${#SELECTED[@]} selected, into ${#DEST_DIRS[@]} directories"
info "${PREFIX}written:   $copied"
info "${PREFIX}unchanged: $unchanged"
info "${PREFIX}skipped:   $skipped"
info "${PREFIX}recorded:  $recorded_total"

# A run that placed nothing must not read like a run that placed something.
# "Finished, wrote nothing" and "finished, everything was already correct" have
# different causes and different remedies, and the counts above are identical
# in the one case a reader most needs to tell apart.
if [ "$copied" -eq 0 ] && [ "$unchanged" -eq 0 ]; then
  info ""
  info "${PREFIX}NOTHING WAS PLACED. No file was written and none was already in place."
  info "${PREFIX}Every candidate file was skipped, or the selected skills contain no files."
fi

if [ "${#SKIPPED_PATHS[@]}" -gt 0 ]; then
  info ""
  info "Skipped, because overwriting would have destroyed a local change:"
  for p in "${SKIPPED_PATHS[@]}"; do info "  $p"; done
  info ""
  info "To take the pack's version of a skill and lose your edits to it:"
  info "  $0 --pack $PACK --forget <skill-name> $TARGET"
fi

if [ "${#UNSELECTED[@]}" -gt 0 ]; then
  info ""
  info "Recorded in $MANIFEST_NAME and NOT named in --skills:"
  for s in "${UNSELECTED[@]}"; do info "  $s"; done
  info "They are still tracked and their files were left alone. --skills names the"
  info "full set for a pack, so if you meant to keep them, name them next time."
fi

if [ "${#ORPHANS[@]}" -gt 0 ]; then
  info ""
  info "This pack version no longer ships these, and they were left in place:"
  for p in "${ORPHANS[@]}"; do info "  $p"; done
  info "Delete them by hand if you want them gone."
fi

if [ "$DRY_RUN" -eq 1 ]; then
  info ""
  info "Dry run. Nothing was written and $MANIFEST_NAME was not updated."
  { [ "$skipped" -gt 0 ] || [ "${#UNSELECTED[@]}" -gt 0 ]; } && exit 2
  exit 0
fi

# ------------------------------------------------------------ write manifest

ALL_SKILLS="$(printf '%s\n' "${SELECTED[@]}" "${UNSELECTED[@]:-}" | grep -v '^$' | sort -u | jq -R . | jq -s .)"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

printf '%s' "$manifest_json" | jq -S \
  --arg k "$PACK" \
  --arg source "$MANIFEST_SOURCE" \
  --arg pv "$PACK_VERSION" \
  --arg pc "$PACK_COMMIT" \
  --arg ur "$UPSTREAM_REPO" \
  --arg us "$UPSTREAM_SUBDIR" \
  --arg uc "$UPSTREAM_COMMIT" \
  --arg at "$STAMP" \
  --argjson skills "$ALL_SKILLS" \
  --argjson files "$(printf '%s' "$NEW_FILES" | jq 'sort_by(.path)')" \
  --argjson schema "$SCHEMA_VERSION" \
  '.schemaVersion = $schema
   | .packs[$k] = {
       source: $source,
       packVersion: $pv,
       packCommit: $pc,
       upstream: {repo: $ur, subdir: $us, commit: $uc},
       installedAt: $at,
       skills: $skills,
       files: $files
     }' > "$MANIFEST.tmp" || die "could not write $MANIFEST_NAME"

# The removed schema 3 field is rejected by a reader rather than ignored, so a
# manifest carrying it fails loudly. Never write one.
if jq -e '[.packs[].files[] | select(has("shippedSha256"))] | length > 0' "$MANIFEST.tmp" >/dev/null 2>&1; then
  rm -f "$MANIFEST.tmp"
  die "refusing to write a manifest carrying shippedSha256"
fi

mv "$MANIFEST.tmp" "$MANIFEST" || die "could not replace $MANIFEST_NAME"

info ""
info "Recorded $PACK $PACK_VERSION at ${PACK_COMMIT:0:12} in $MANIFEST_NAME."
info "Commit the skill directories and $MANIFEST_NAME so they reach a cloud agent."

{ [ "$skipped" -gt 0 ] || [ "${#UNSELECTED[@]}" -gt 0 ]; } && exit 2
exit 0
