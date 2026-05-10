#!/usr/bin/env python3
"""
Hook: Detect a narrow unsafe depends_on pattern — str(k) in else branch
when iterating dict.items() (value should be str(v) when v is not a dict).
"""

import re
import sys
from pathlib import Path


def check_file(path: str) -> bool:
    """Return True if violations found."""
    try:
        content = Path(path).read_text()
    except OSError:
        return False

    violations: list[str] = []
    lines = content.splitlines()

    for i, line in enumerate(lines, 1):
        if line.strip().startswith("#"):
            continue

        if re.search(r"for\s+\w+,\s+\w+\s+in\s+\w+\.items\(\)", line):
            context = "\n".join(lines[i : min(i + 8, len(lines))])
            # Original review: else branch used str(k) instead of str(v)
            if "isinstance" in context and "str(" in context and ".items()" in line:
                if re.search(r"else\s+str\(\w+\)", context) and not re.search(
                    r"else\s+str\(v\)", context
                ):
                    if "str(v)" not in context:
                        violations.append(
                            f"{path}:{i} depends_on formatting: prefer str(v) when value is not a dict"
                        )

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
