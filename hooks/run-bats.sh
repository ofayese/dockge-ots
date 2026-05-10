#!/usr/bin/env bash
# Hook runner: Execute shell integration tests (bats)
# Runs before commit. Exit 1 on failure to block commit.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Check if bats tests exist
if [[ ! -d "tests/shell" ]] || [[ -z "$(find tests/shell -name '*.bats' 2>/dev/null)" ]]; then
    echo "run-bats.sh: no tests/shell/*.bats files found — skipping."
    exit 0
fi

# Check if bats is installed
if ! command -v bats &>/dev/null; then
    echo "run-bats.sh: bats not found — skipping (install with: brew install bats-core or npm install -g bats)" >&2
    exit 0
fi

echo "Running bats shell integration tests..."
bats tests/shell/*.bats --verbose 2>&1 || exit 1

echo "All shell integration tests passed."
exit 0
