#!/usr/bin/env bash
# Hook: Detect bash regex alternation (|) outside quoted contexts.
# Flags: [[ $var =~ pattern|other ]] where pipe is not escaped (\|).
# Issue: Bash treats | as alternation only in [[ =~ ]], but not in extended regex without shopt -s extglob.
# This hook warns when | appears in regex without proper escaping or quoting.

set -euo pipefail

fail=0
for file in "$@"; do
	[[ -f "$file" ]] || continue

	# Check for [[ ... =~ ... ]] patterns with unescaped pipe
	# Pattern: [[ $something =~ (...|...) ]] where pipes might not be escaped
	if grep -E '\[\[.*=~.*\|' "$file" >/dev/null 2>&1; then
		# Found =~ with pipe — check if it's escaped or quoted
		while IFS= read -r line; do
			# Skip comments
			[[ "$line" =~ ^[[:space:]]*# ]] && continue

			# Check if line has =~ and unescaped pipe (not preceded by backslash)
			if [[ "$line" =~ \[\[.*=~.*\| ]]; then
				# Check for escaped pipes (\|)
				if ! grep -q '\\|' <<<"$line"; then
					# Check if pipe is inside quotes (heuristic: count quotes before pipe)
					before_pipe="${line%%|*}"
					# Count quotes without a [^'] pattern (breaks shfmt/shellcheck parsing).
					single_quotes=$(printf '%s' "$before_pipe" | tr -d -c "'")
					double_quotes=$(printf '%s' "$before_pipe" | tr -d -c '"')
					# If odd number of quotes, pipe is inside a quote context
					if ((${#single_quotes} % 2 == 0 && ${#double_quotes} % 2 == 0)); then
						echo "$file: WARNING: regex alternation (|) may need escaping in =~ context: $(echo "$line" | xargs)"
						fail=1
					fi
				fi
			fi
		done <"$file"
	fi
done

exit $fail
