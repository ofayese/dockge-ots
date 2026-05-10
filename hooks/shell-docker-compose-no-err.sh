#!/usr/bin/env bash
# Hook: Detect docker compose calls without explicit error handling.
# Flags: docker compose ... && exit commands where an inline failure is not caught.
# Issue: docker compose can fail silently in scripts that don't use set -e or explicit error checks.

set -euo pipefail

fail=0
for file in "$@"; do
    [[ -f "$file" ]] || continue

    # Check for docker compose calls that don't have error propagation
    # Patterns to flag:
    #   docker compose ... (standalone, not piped, not followed by ||, &&, or ; set -e)
    #   docker compose ... | something (piping can hide errors; use 'set -o pipefail')
    #
    # The script should have: set -euo pipefail (recommended)
    # Or each docker compose call should have: || { echo ERR; exit 1; }

    # Check if script has set -euo pipefail or set -e
    if ! grep -q '^set -[^-]*e' "$file" 2>/dev/null; then
        # Script does NOT have set -e or set -euo pipefail
        # Flag docker compose calls that don't have explicit error handling
        while IFS= read -r line_num line; do
            # Skip comments
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            # Look for docker compose
            if grep -q 'docker compose' <<<"$line"; then
                # Check if this line has explicit error handling
                # OK patterns: || exit, || return, || { ..., && ..., | ..., ...;
                if ! grep -qE '(\|\||&&|set -e|\|\s|;)' <<<"$line"; then
                    # This line has docker compose without error handling
                    echo "$file:$line_num: WARNING: docker compose without error propagation (add || exit or use 'set -e'): ${line// /...}"
                    fail=1
                fi
            fi
        done < <(grep -n 'docker compose' "$file" 2>/dev/null)
    fi
done

exit $fail
