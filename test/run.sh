#!/bin/bash
# Run every test in this directory.
#
# The runner names each file it ran, and refuses to report success when it
# discovered nothing. A suite that found no tests and a suite whose tests all
# passed otherwise print the same encouraging total, which is the single
# failure this repository's neighbour has paid for most often.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"

FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$TEST_DIR" -maxdepth 1 -name '*.test.sh' -type f | sort)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "STOPPED: no *.test.sh files found in $TEST_DIR"
  echo "Nothing was checked. This is a failure, not an empty pass."
  exit 1
fi

echo "Running ${#FILES[@]} test files from $TEST_DIR"
echo ""

failed=0
for f in "${FILES[@]}"; do
  name="$(basename "$f")"
  echo "== $name"
  bash "$f"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    failed=$((failed+1))
    echo "  -> FAILED (exit $rc)"
  fi
  echo ""
done

echo "----------------------------------------"
echo "test files run:    ${#FILES[@]}"
echo "test files failed: $failed"

if [ "$failed" -gt 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
