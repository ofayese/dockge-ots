#!/usr/bin/env bash
# Hook: Flag sed substitutions that use / as the s delimiter while interpolating ${VAR}.
# Safe pattern: s|...|...| (or awk + ENVIRON per AGENTS.md).
# Uses case / prefix checks only — no [[ =~ ]] (avoids false positives in shell-bash-regex-alternation).

set -euo pipefail

fail=0
for file in "$@"; do
	[[ -f "$file" ]] || continue
	while read -r line; do
		case "$line" in
		'#'*) continue ;;
		*sed*) ;;
		*) continue ;;
		esac
		case "$line" in
		*s/*) ;;
		*) continue ;;
		esac
		[[ "$line" == *"\$\{"* ]] || continue
		case "$line" in
		*s'|'*) continue ;;
		esac
		case "$line" in
		*s\|*) continue ;;
		esac
		echo "$file: WARNING sed uses s/.../\${...} style — prefer s|...|...| or awk + ENVIRON" >&2
		fail=1
	done <"$file"
done

exit "$fail"
