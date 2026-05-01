#!/usr/bin/env bash
# Portable check: stack names in scripts/init-nas.sh no-op manifest match ls stacks/.
# (BSD grep lacks grep -oP; use this instead of raw grep -oP on macOS.)
set -euo pipefail
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${_script_dir}"
while [[ ! -f "${ROOT}/HIVE_OBJECTIVE.md" && "${ROOT}" != "/" ]]; do
	ROOT="$(dirname "${ROOT}")"
done
[[ -f "${ROOT}/HIVE_OBJECTIVE.md" ]] || {
	echo "ERROR: could not find repo root" >&2
	exit 1
}
# shellcheck disable=SC2012
diff <(
	perl -ne 'while (/"([^"]+:[^"]+)"/g) { ($x=$1) =~ s/:.*//s; print "$x\n" }' "${ROOT}/scripts/init-nas.sh" | sort -u
) <(ls "${ROOT}/stacks" | sort)
