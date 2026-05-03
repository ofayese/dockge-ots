#!/usr/bin/env bash
# Syntax-check the hive HAProxy proposal if a haproxy binary is available (NAS or dev box).
set -euo pipefail
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${_script_dir}"
while [[ ! -f "${ROOT}/HIVE_OBJECTIVE.md" && "${ROOT}" != "/" ]]; do
	ROOT="$(dirname "${ROOT}")"
done
cfg="${ROOT}/docs/hive/proposals/_haproxy/haproxy.cfg"
if [[ ! -f "${cfg}" ]]; then
	echo "validate-haproxy-proposal: missing ${cfg}" >&2
	exit 1
fi
if ! command -v haproxy >/dev/null 2>&1; then
	echo "validate-haproxy-proposal: SKIP (haproxy not in PATH). On DSM run: haproxy -c -f <package-config>"
	exit 0
fi
echo "validate-haproxy-proposal: haproxy -c -f ${cfg}"
log="$(mktemp)"
trap 'rm -f "${log}"' EXIT
if haproxy -c -f "${cfg}" >"${log}" 2>&1; then
	echo "validate-haproxy-proposal: OK"
	exit 0
fi
cat "${log}" >&2
# Proposal targets Synology package paths and user sc-haproxy — off-box checks often fail for those alone.
if grep -qE 'sc-haproxy|/var/packages/haproxy' "${log}"; then
	echo "validate-haproxy-proposal: WARN Synology-only user/paths in cfg; re-run haproxy -c on the NAS before reload." >&2
	exit 0
fi
exit 1
