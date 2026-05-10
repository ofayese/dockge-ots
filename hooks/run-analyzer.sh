#!/usr/bin/env bash
# Hook runner: Execute inventory static analyzer
# Runs before commit when compose files or inventory.py change.
# Exit 1 on failure to block commit.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Check if analyzer exists
if [[ ! -f "docs/hive/tools/inventory.py" ]]; then
	echo "run-analyzer.sh: inventory.py not found — skipping."
	exit 0
fi

# Check if python3 is available
if ! command -v python3 &>/dev/null; then
	echo "run-analyzer.sh: python3 not found — skipping." >&2
	exit 0
fi

echo "Running inventory static analyzer..."
python3 docs/hive/tools/inventory.py --all --analyze --stdout >/dev/null 2>&1 || {
	echo "run-analyzer.sh: analyzer failed" >&2
	exit 1
}

echo "Inventory analyzer validation passed."
exit 0
