#!/usr/bin/env bash
# Hook: Detect sed without escaping special characters in replacement.
# Flags: sed 's/.../${VAR}/...' where VAR contains special chars but is not escaped.

set -euo pipefail

fail=0
for file in "$@"; do
    [[ -f "$file" ]] || continue

    # Check for sed with variable replacement without escaping
    # Pattern: sed 's|...|${VAR}|...' where VAR is not in a sed escape block
    if grep -E "sed.*'s[|/].*\\\${[A-Z_][A-Z0-9_]*}" "$file" >/dev/null 2>&1; then
        # This line HAS escaping — OK
        :
    elif grep -E "sed.*(s[|/]|s\").+\\\${[A-Z_][A-Z0-9_]*}" "$file" >/dev/null 2>&1; then
        # Found unescaped variable in sed substitution
        echo "$file: WARNING sed with unescaped variable (may fail if VAR contains |,/,&)"
        fail=1
    fi

    # Check for missing delimiter escaping
    # Pattern: sed 's/^VAR=/...'  where VAR might not need escaping but / could be problematic
    if grep -E "sed\s+.s/" "$file" | grep -v "sed\s+.s\|" | grep -v "sed\s+.s;" >/dev/null 2>&1; then
        # Warn if / delimiter used and path-like content exists
        if grep -q '\${.*ROOT.*}' "$file" 2>/dev/null; then
            grep -n "sed\s+.s/" "$file" | while read -r line; do
                if grep -E "\\\${.*ROOT.*}" <<<"$line" >/dev/null 2>&1; then
                    echo "$file:${line%%:*} sed with / delimiter and path variable (use | delimiter or escape)"
                    fail=1
                fi
            done
        fi
    fi
done

exit $fail
