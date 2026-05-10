#!/usr/bin/env python3
"""
Hook: Detect subprocess.run() without timeout= in the call (may span lines).
"""

import sys
from pathlib import Path


def check_file(path: str) -> bool:
    """Return True if violations found."""
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return False

    violations: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip().startswith("#"):
            i += 1
            continue
        if "subprocess.run(" not in line:
            i += 1
            continue
        # Gather a small window — timeout= often appears on following lines.
        chunk = "\n".join(lines[i : min(i + 16, len(lines))])
        if "timeout=" not in chunk:
            violations.append(f"{path}:{i + 1} subprocess.run without timeout=")
        i += 1

    if violations:
        for v in violations:
            print(v)
        return True
    return False


if __name__ == "__main__":
    # Evaluate every file; any() short-circuits and would hide later violations.
    failed = False
    for f in sys.argv[1:]:
        if check_file(f):
            failed = True
    sys.exit(1 if failed else 0)
