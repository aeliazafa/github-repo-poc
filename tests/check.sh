#!/usr/bin/env bash
# Tiny stand-in for a real test suite so CI has something to pass or fail.
set -euo pipefail

test -f app/index.html || { echo "app/index.html is missing"; exit 1; }
grep -q "<title>PoC App</title>" app/index.html || { echo "page title is wrong"; exit 1; }

# Fail on leftover merge-conflict markers anywhere in the app.
if grep -rnE '^(<<<<<<<|>>>>>>>)' app; then
  echo "merge conflict markers found"
  exit 1
fi

echo "All checks passed."
