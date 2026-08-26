#!/bin/bash
# No function in these scripts may be called above its own definition.
#
# Bash resolves a function name when the call runs, not when the file is
# parsed. A call placed above its definition is therefore legal text: the shell
# prints "command not found" to stderr, SKIPS the call, and leaves the status
# at 127. Nothing in these scripts reads that status, so the command carries on
# and exits 0, and the caller sees a check that passed while examining nothing.
#
# That is exactly what --list did from 2026-08-23, when bin/lay-pack.sh was
# added, until this change: it called assert_manifest_paths_ok 93 lines above
# the definition, and listed a manifest holding "../../../etc/passwd" with an
# exit code of 0.
#
# Nothing else catches it. bash -n accepts the file. shellcheck 0.11.0 says
# nothing, at its defaults and at --enable=all, because it does not model
# definition order. Both were measured against the broken file, not assumed.
#
# Two decisions in how this is written:
#
# It DISCOVERS the function names from each file rather than being handed a
# list to check. A list only ever holds the names somebody remembered, which
# makes it a proxy for the property rather than the property.
#
# It is deliberately STRICTER than bash requires: a name may not appear
# anywhere above its own definition, including inside another function's body,
# where bash would resolve it correctly at call time. The strict rule is the
# one a reader can confirm by eye, and the cost of obeying it is moving a
# definition up.
#
# Full-line comments are blanked before the scan, since the documentation block
# above a function names the function it documents.
source "$(dirname "$0")/helpers.sh"

# violations_in <shell file> -- prints one line per violation, none when clean.
violations_in() {
  local f="$1" stripped name defline firstuse
  stripped="$(mktemp "${TMPDIR:-/tmp}/skillstack-scan.XXXXXX")" || return 1
  sed 's/^[[:space:]]*#.*$//' "$f" > "$stripped"
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    # The FIRST definition line, because a function defined twice on different
    # branches of an if (hash_of, for one) is mentioned by its own earlier
    # definition and would otherwise read as a use before the later one.
    defline="$(grep -nE "^[[:space:]]*${name}\(\)[[:space:]]*\{" "$stripped" | head -1 | cut -d: -f1)"
    firstuse="$(grep -nE "(^|[^A-Za-z0-9_])${name}([^A-Za-z0-9_]|\$)" "$stripped" | head -1 | cut -d: -f1)"
    if [ -z "$defline" ] || [ -z "$firstuse" ]; then
      printf '%s: could not locate '"'"'%s'"'"', so this file was not really scanned\n' "$f" "$name"
      continue
    fi
    if [ "$firstuse" -lt "$defline" ]; then
      printf "%s: '%s' is used on line %s and not defined until line %s\n" \
        "$f" "$name" "$firstuse" "$defline"
    fi
  done < <(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\(\)' "$stripped" \
             | sed 's/^[[:space:]]*//; s/()$//' | sort -u)
  rm -f "$stripped"
}

# ---------------------------------------------------------- the detector runs
#
# A scan that cannot fire and a scan that found nothing print the same empty
# result, so the detector is pointed at a known-bad file and a known-good one
# before any verdict about the real scripts is read.

probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/skillstack-probe.XXXXXX")"

# Built with printf and not a heredoc, on purpose. A heredoc would put a
# function definition at the start of a line IN THIS FILE, and the scan below
# reads every script in test/ including this one, so the probe would report
# itself as a violation. As printf arguments the same text never begins a line.
printf '%s\n' \
  '#!/bin/bash' \
  'early_caller "x"' \
  'early_caller() { echo hi; }' > "$probe_dir/bad.sh"

printf '%s\n' \
  '#!/bin/bash' \
  'late_caller() { echo hi; }' \
  'late_caller "x"' > "$probe_dir/good.sh"

bad_report="$(violations_in "$probe_dir/bad.sh")"
check_eq "the detector fires on a call above its definition" \
  1 "$(printf '%s' "$bad_report" | grep -c 'early_caller')"
check_eq "and stays quiet when the definition comes first" \
  "" "$(violations_in "$probe_dir/good.sh")"

rm -rf "$probe_dir"

# ------------------------------------------------------- the real scripts
#
# Discovered with find rather than asked of git, so a script added and not yet
# committed is scanned on the run that adds it.

FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  find "$SKILLSTACK_ROOT/bin" "$SKILLSTACK_ROOT/test" -maxdepth 1 -name '*.sh' -type f | sort
)
check "the scan found shell scripts to examine" test "${#FILES[@]}" -gt 3

# A named positive control for the one function this test exists because of. If
# the extraction stops seeing it, every clean result below is worthless.
if grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\(\)' "$LAY" \
     | sed 's/^[[:space:]]*//; s/()$//' | grep -qx 'assert_manifest_paths_ok'; then
  pass "the scan's own extraction still finds assert_manifest_paths_ok in lay-pack.sh"
else
  fail "the scan no longer finds assert_manifest_paths_ok, so it is examining the wrong thing"
fi

for f in "${FILES[@]}"; do
  rel="${f#"$SKILLSTACK_ROOT"/}"
  report="$(violations_in "$f")"
  if [ -n "$report" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && fail "${line#"$SKILLSTACK_ROOT"/}"
    done <<< "$report"
  else
    pass "$rel: every function is defined above its first mention"
  fi
done

finish
