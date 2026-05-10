#!/usr/bin/env bash
# Hook runner: Execute Python unit tests (pytest or unittest)
# Runs before commit. Exit 1 on failure to block commit.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Check if tests exist
if [[ ! -d "tests" ]]; then
	echo "run-pytest.sh: no tests/ directory found — skipping."
	exit 0
fi

# Try pytest first, fall back to unittest
if command -v pytest &>/dev/null; then
	echo "Running pytest..."
	pytest tests/ -v --tb=short 2>&1 || exit 1
elif command -v python3 &>/dev/null && python3 -m pytest --version &>/dev/null 2>&1; then
	echo "Running python3 -m pytest..."
	python3 -m pytest tests/ -v --tb=short 2>&1 || exit 1
elif command -v python3 &>/dev/null; then
	echo "Running python3 -m unittest discover..."
	python3 -m unittest discover -s tests -p 'test_*.py' -v 2>&1 || exit 1
else
	echo "run-pytest.sh: pytest and python3 not found — skipping."
	exit 0
fi

echo "All Python tests passed."
exit 0
