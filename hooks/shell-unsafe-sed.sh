#!/usr/bin/env bash
# Hook: Flag sed substitutions that use / as the s delimiter while interpolating ${VAR}.
# Safe pattern: s|...|...| (or awk + ENVIRON per AGENTS.md).

set -euo pipefail

fail=0
for file in "$@"; do
	[[ -f "$file" ]] || continue
	# Use process substitution to avoid subshell so fail=1 propagates
	while read -r line; do
		# Skip comments and lines without both sed, /, and ${}
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ "$line" =~ sed ]] || continue
		[[ "$line" =~ s/ ]] || continue
		[[ "$line" =~ \$\{ ]] || continue
		[[ "$line" =~ s\| ]] && continue  # Already using | delimiter
		# Matched: sed with s/.../.../ and ${VAR}
		echo "$file: WARNING sed uses s/.../\${...} style — prefer s|...|...| or awk + ENVIRON" >&2
		fail=1
	done < "$file"
done

exit "$fail"
