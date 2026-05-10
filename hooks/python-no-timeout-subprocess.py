#!/usr/bin/env python3
"""
Hook: Detect subprocess.run() without timeout parameter.
Usage: pre-commit hook detects dangerous subprocess patterns.
"""

import re
import sys
from pathlib import Path

UNSAFE_PATTERNS = [
    re.compile(r'subprocess\.run\([^)]*\)', re.MULTILINE),  # Basic check
]


def check_file(path: str) -> bool:
    """Check if file has unsafe subprocess patterns. Return True if violations found."""
    try:
        content = Path(path).read_text()
    except Exception:
        return False

    violations = []
    for i, line in enumerate(content.splitlines(), 1):
        # Skip comments
        if line.strip().startswith('#'):
            continue

        # Check if subprocess.run exists WITHOUT timeout= parameter
        if 'subprocess.run(' in line and 'timeout=' not in line:
            # Heuristic: if line has subprocess.run and NOT timeout, flag it
            # (Allow if it's in a comment or string)
            if not any(x in line[:line.find('subprocess.run')] for x in ['#', '"""', "'''"]):
                violations.append(f"{path}:{i} subprocess.run without timeout")

    if violations:
        for v in violations:
            print(v)
        return True
    return False


if __name__ == "__main__":
    failed = any(check_file(f) for f in sys.argv[1:])
    sys.exit(1 if failed else 0)
