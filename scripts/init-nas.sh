#!/usr/bin/env bash
# init-nas.sh — post-clone NAS bootstrap: resolve STACK_ROOT, write repo-root .env, mkdir stack dirs, fix permissions.
# Run once after git clone on the NAS: sudo bash scripts/init-nas.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STACKS_DIR="${REPO_ROOT}/stacks"

# --- STACK_MANIFEST: noop colon-quoted stack lines at end of file (keep in sync with ls stacks/).

resolve_stack_root() {
	if [[ -d "${STACKS_DIR}" ]]; then
		printf '%s' "${STACKS_DIR}"
		return 0
	fi
	printf '%s' "/dockge/stacks"
}

write_repo_env() {
	local stack_root="$1"
	local env_file="${REPO_ROOT}/.env"
	touch "${env_file}"
	if grep -q '^STACK_ROOT=' "${env_file}" 2>/dev/null; then
		if [[ "$(uname -s)" == "Darwin" ]]; then
			sed -i '' "s|^STACK_ROOT=.*|STACK_ROOT=${stack_root}|" "${env_file}"
		else
			sed -i "s|^STACK_ROOT=.*|STACK_ROOT=${stack_root}|" "${env_file}"
		fi
	else
		printf 'STACK_ROOT=%s\n' "${stack_root}" >>"${env_file}"
	fi
	for kv in "PUID=0" "PGID=0"; do
		key="${kv%%=*}"
		if ! grep -q "^${key}=" "${env_file}" 2>/dev/null; then
			printf '%s\n' "${kv}" >>"${env_file}"
		fi
	done
}

mkdir_stack_layout() {
	local stack_root="$1"
	local stack
	for stack in "${STACKS_DIR}"/*; do
		[[ -d "${stack}" ]] || continue
		local name
		name="$(basename "${stack}")"
		mkdir -p "${stack_root}/${name}/data" "${stack_root}/${name}/config" "${stack_root}/${name}/db"
	done
}

main() {
	local stack_root
	stack_root="$(resolve_stack_root)"
	printf 'Using STACK_ROOT=%s\n' "${stack_root}"
	mkdir -p "${stack_root}"
	write_repo_env "${stack_root}"
	mkdir_stack_layout "${stack_root}"

	if [[ "$(id -u)" -eq 0 ]]; then
		bash "${SCRIPT_DIR}/fix-permissions.sh" "${stack_root}"
	else
		printf 'WARN: not root; run: sudo bash %s %s\n' "${SCRIPT_DIR}/fix-permissions.sh" "${stack_root}" >&2
	fi
	printf 'init-nas.sh finished.\n'
}

main "$@"

# shellcheck disable=SC2034
# No-op manifest pairs for CI (keep in sync with ls stacks/ and comment manifest above).
: "acme-sh:data"
: "agents_gateway_data:data"
: "code-server:config"
: "codex-docs:data"
: "databases:db"
: "docker-model-runner:data"
: "dozzle:data"
: "github-desktop:config"
: "grafana-prom:data"
: "holyclaude:data"
: "homepage:config"
: "it-tools:data"
: "mcp-tools-config:data"
: "ollama:data"
: "openresume:data"
: "portainer:data"
: "searxng:config"
: "warp-main:data"
: "watchtower:data"
