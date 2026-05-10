#!/usr/bin/env python3
"""
Hook: Detect unsafe dict iteration patterns in Python.
Patterns:
  - for k, v in dict.items() where only one is used later
  - dict unpacking without validation
  - Accessing dict keys without .get() or try-except
"""

import re
import sys
from pathlib import Path

UNSAFE_PATTERNS = [
    # Pattern: for k, v in depends.items() but only using k (missing value)
    (r'for\s+(\w+),\s+(\w+)\s+in\s+\w+\.items\(\).*?(?!return|yield)', 'incomplete dict unpacking'),
]


def check_file(path: str) -> bool:
    """Check for unsafe dict iteration."""
    try:
        content = Path(path).read_text()
    except Exception:
        return False

    violations = []
    lines = content.splitlines()

    for i, line in enumerate(lines, 1):
        # Skip comments
        if line.strip().startswith('#'):
            continue

        # Pattern: for k, v in dict.items() where only k is used in the body
        if 'for ' in line and ', ' in line and ' in ' in line and '.items()' in line:
            # Extract variable names
            match = re.search(r'for\s+(\w+),\s+(\w+)\s+in\s+(\w+)\.items\(\)', line)
            if match:
                var1, var2, dict_name = match.groups()
                # Check next few lines for usage
                context = '\n'.join(lines[i:min(i + 5, len(lines))])
                if var2 not in context and 'str(' + var1 in context:
                    violations.append(f"{path}:{i} dict.items() unpacking: {var2} unused, using str({var1})")

        # Pattern: direct dict access without .get()
        if re.search(r'\w+\[', line) and 'get(' not in line:
            if not any(x in line for x in ['#', '"""', "'''"]):
                # This is a heuristic — check for actual key access
                if '.get(' not in line and 'except' not in line:
                    if 'KeyError' not in lines[max(0, i - 2):i]:
                        violations.append(f"{path}:{i} potential unsafe dict access (use .get() or try-except)")

    if violations:
        for v in violations:
            print(v)
        return True
    return False


if __name__ == "__main__":
    failed = any(check_file(f) for f in sys.argv[1:])
    sys.exit(1 if failed else 0)
