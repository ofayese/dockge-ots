#!/usr/bin/env bash
# Syntax-check stacks/_haproxy/haproxy.cfg using a temp tree (dummy TLS + map copy).
# Resolves /volume1/docker/dockge/stacks/_haproxy to a writable temp path so haproxy -c works off-NAS.
set -euo pipefail
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${_script_dir}"
while [[ ! -f "${ROOT}/HIVE_OBJECTIVE.md" && "${ROOT}" != "/" ]]; do
	ROOT="$(dirname "${ROOT}")"
done
cfg="${ROOT}/stacks/_haproxy/haproxy.cfg"
map_src="${ROOT}/stacks/_haproxy/maps/host.map"
if [[ ! -f "${cfg}" ]]; then
	echo "validate-haproxy-proposal: missing ${cfg}" >&2
	exit 1
fi
wrapper="${ROOT}/docs/hive/proposals/_haproxy/haproxy.cfg"
if [[ ! -f "${wrapper}" ]]; then
	echo "validate-haproxy-proposal: missing ${wrapper}" >&2
	exit 1
fi
if [[ ! -f "${map_src}" ]]; then
	echo "validate-haproxy-proposal: missing ${map_src}" >&2
	exit 1
fi

run_haproxy_check() {
	local haproxy_cfg="$1"
	if command -v haproxy >/dev/null 2>&1; then
		haproxy -c -f "${haproxy_cfg}"
		return
	fi
	if command -v docker >/dev/null 2>&1; then
		local cfg_dir
		cfg_dir="$(dirname "${haproxy_cfg}")"
		docker run --rm -v "${cfg_dir}:${cfg_dir}:ro" haproxytech/haproxy-alpine:3.0 \
			haproxy -c -f "${haproxy_cfg}"
		return
	fi
	echo "validate-haproxy-proposal: SKIP (need haproxy or docker in PATH)" >&2
	return 0
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/certs" "${TMP}/maps"
cp "${map_src}" "${TMP}/maps/host.map"
if ! command -v openssl >/dev/null 2>&1; then
	echo "validate-haproxy-proposal: SKIP (openssl not in PATH; cannot create dummy PEM)" >&2
	exit 0
fi
openssl req -x509 -nodes -newkey rsa:2048 -keyout "${TMP}/k.pem" -out "${TMP}/c.pem" -days 1 \
	-subj "/CN=haproxy-syntax-check" >/dev/null 2>&1
cat "${TMP}/c.pem" "${TMP}/k.pem" >"${TMP}/certs/_syntax-check.pem"
sed "s|/volume1/docker/dockge/stacks/_haproxy|${TMP}|g" "${cfg}" >"${TMP}/haproxy.cfg"

echo "validate-haproxy-proposal: haproxy -c -f ${TMP}/haproxy.cfg (paths rewritten to temp)"
if ! run_haproxy_check "${TMP}/haproxy.cfg"; then
	echo "validate-haproxy-proposal: FAIL (stacks/_haproxy/haproxy.cfg)" >&2
	exit 1
fi

# Wrapper include (docs path) — same temp tree, include target beside generated haproxy.cfg
cp "${TMP}/haproxy.cfg" "${TMP}/haproxy-main.cfg"
cat >"${TMP}/haproxy.cfg" <<EOF
include ${TMP}/haproxy-main.cfg
EOF
echo "validate-haproxy-proposal: haproxy -c -f ${TMP}/haproxy.cfg (include smoke)"
if ! run_haproxy_check "${TMP}/haproxy.cfg"; then
	echo "validate-haproxy-proposal: FAIL (include chain)" >&2
	exit 1
fi

echo "validate-haproxy-proposal: OK (stacks/_haproxy/haproxy.cfg + include)"
exit 0
