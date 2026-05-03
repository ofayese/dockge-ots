#!/usr/bin/env bash
# init-nas.sh
# Post-clone bootstrap for the Dockge stack repo.
# Run once after git clone on the NAS:
#   sudo bash scripts/init-nas.sh
# Re-run after git pull only if new stacks have been added.
# Idempotent — safe to run multiple times.
#
# Manifest exhaustiveness (BSD-safe; no grep -oP):
#   diff <(grep -E '^\s*"[^"]+:' scripts/init-nas.sh | sed -E 's/^[[:space:]]*"([^"]+):.*/\1/' | sort) \
#        <(ls stacks/ | grep -vE '^portainer$|^agents_gateway_data$|^it-tools$|^mcp-tools-config$|^openresume$|^warp-main$|^watchtower$|^docker-model-runner$' | sort)
# Left: stack names from STACK_MANIFEST. Right: stack dirs excluding MANIFEST_EXEMPT (same as grep -vE list).

set -euo pipefail

LIST_ONLY=0
IF_CHANGED_MODE=0
[[ "${1:-}" == "--list-expected-dirs" ]] && LIST_ONLY=1

# ── 1. Resolve repo root and STACK_ROOT ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ENV="${REPO_ROOT}/.env"
STACKS_IN_REPO="${REPO_ROOT}/stacks"

# Prefer stacks inside this repo (this layout). Else sibling ../stacks next to the
# clone parent. Else STACK_ROOT_OVERRIDE or /dockge/stacks.
if [[ -d "${STACKS_IN_REPO}" ]]; then
	STACK_ROOT="${STACKS_IN_REPO}"
	[[ "${LIST_ONLY}" -eq 0 ]] && echo "Auto-detected STACK_ROOT (repo stacks/): ${STACK_ROOT}"
else
	CANDIDATE_STACKS="$(cd "${REPO_ROOT}/.." && pwd)/stacks"
	if [[ -d "${CANDIDATE_STACKS}" ]]; then
		STACK_ROOT="${CANDIDATE_STACKS}"
		[[ "${LIST_ONLY}" -eq 0 ]] && echo "Auto-detected STACK_ROOT (sibling stacks/): ${STACK_ROOT}"
	else
		STACK_ROOT="${STACK_ROOT_OVERRIDE:-/dockge/stacks}"
		if [[ "${LIST_ONLY}" -eq 0 ]]; then
			echo "Using default STACK_ROOT: ${STACK_ROOT}"
			echo "(Override with: STACK_ROOT_OVERRIDE=/your/path sudo bash scripts/init-nas.sh)"
		fi
	fi
fi

# Format: "stack-name:sub1[,sub2]" — keep aligned with compose bind mounts under ${STACK_ROOT}/<stack>/...
STACK_MANIFEST=(
	# Sub-folder rules:
	#   data   → default for all stacks with host bind mounts
	#   db     → add only when a DB engine has its own host bind mount
	#   config → add only when a non-db service writes runtime config
	# Never add a folder speculatively.
	# portainer: OPERATOR EXCEPTION — exempt from this manifest.
	#   Path managed via ${PORTAINER_DATA_ROOT}. See repo AGENTS.md / stack README.

	# ── data only ─────────────────────────────────────────────────────
	"acme-sh:data"
	"dozzle:data"
	"ollama:data"

	# ── data,config ───────────────────────────────────────────────────
	"code-server:data,config"
	"github-desktop:config" # KasmVNC GUI — /config only, no data dir
	"homepage:data,config"
	"searxng:data,config"
	"grafana-prom:data,config"

	# ── data,db ───────────────────────────────────────────────────────
	"codex-docs:data,db"
	# databases: mariadb + postgres engine data dirs both under db/ (no separate app data layer).
	"databases:db"
	"zabbix:data,db"
	"holyclaude:data"

	# ── Omit (no ${STACK_ROOT} dirs in manifest) — audit trail only ───
	# agents_gateway_data: docker.sock only — no ${STACK_ROOT} dirs needed.
	# docker-model-runner: no host volume binds.
	# it-tools: no volumes.
	# mcp-tools-config: catalog only — no runtime dirs.
	# openresume: no volumes.
	# warp-main: no volumes.
	# watchtower: docker.sock only — no ${STACK_ROOT} dirs needed.
	#   Absent from manifest intentionally. Listed here for audit trail.

	# ── New stacks: add entry here before first deploy ─────────────────
	"traefik-ots:config" # Traefik config (tls.yaml)
	"traefik-ots:data"   # Traefik built-in ACME state (acme.json) — separate from acme-sh PEMs
	"traefik-mft:config"
	"traefik-mft:data"

	# HAProxy bind-mount assets (certs + host map); not a Dockge compose stack — see stacks/_haproxy/README.txt
	"_haproxy:certs,maps"
)

# Stacks intentionally absent from STACK_MANIFEST.
# These have no persistent host bind mounts under ${STACK_ROOT}.
# Listed here so the manifest exhaustiveness check can account
# for them without requiring a dummy entry. (Not read by this script — see
# docs/hive/NAS_DEPLOYMENT.md for the matching `diff` / `grep -vE` list.)
# shellcheck disable=SC2034
MANIFEST_EXEMPT=(
	"agents_gateway_data" # docker.sock only
	"it-tools"            # no volumes
	"mcp-tools-config"    # catalog only
	"openresume"          # no volumes
	"warp-main"           # no volumes
	"watchtower"          # docker.sock only
	"portainer"           # operator exception — path outside STACK_ROOT
	"docker-model-runner" # no host volume binds
)

# ── Manifest-derived expected directory list ─────────────────────────
# Usage: bash scripts/init-nas.sh --list-expected-dirs
# Prints paths init-nas.sh would create under STACK_ROOT, without mkdir or .env writes.
if [[ "${LIST_ONLY}" -eq 1 ]]; then
	for entry in "${STACK_MANIFEST[@]}"; do
		[[ "${entry}" =~ ^[[:space:]]*# ]] && continue
		[[ -z "${entry// /}" ]] && continue
		entry="${entry//\"/}"
		stack="${entry%%:*}"
		sub_folders="${entry##*:}"
		[[ -z "${sub_folders}" ]] && continue
		IFS=',' read -ra folders <<<"${sub_folders}"
		for folder in "${folders[@]}"; do
			[[ -z "${folder}" ]] && continue
			echo "${STACK_ROOT}/${stack}/${folder}"
		done
	done
	exit 0
fi

# ── --if-changed: skip if init-nas.sh itself has not changed ─────────
# Hash is written only after a successful full init (end of script).
if [[ "${1:-}" == "--if-changed" ]]; then
	HASH_FILE="${REPO_ROOT}/.manifest-hash"
	if command -v md5 &>/dev/null; then
		CURRENT_HASH=$(md5 -q "$0")
	else
		CURRENT_HASH=$(md5sum "$0" | cut -d' ' -f1)
	fi
	STORED_HASH=$(cat "${HASH_FILE}" 2>/dev/null || echo "")
	if [[ "${CURRENT_HASH}" == "${STORED_HASH}" ]]; then
		echo "init-nas.sh: unchanged — skipping directory creation."
		exit 0
	fi
	IF_CHANGED_MODE=1
	echo "init-nas.sh: changed — running full init."
fi

# ── 2. Write STACK_ROOT into repo-root .env ───────────────────────────
if [[ -f "${REPO_ENV}" ]]; then
	if grep -q '^STACK_ROOT=' "${REPO_ENV}" 2>/dev/null; then
		if [[ "$(uname -s)" == "Darwin" ]]; then
			sed -i '' "s|^STACK_ROOT=.*|STACK_ROOT=${STACK_ROOT}|" "${REPO_ENV}"
		else
			sed -i "s|^STACK_ROOT=.*|STACK_ROOT=${STACK_ROOT}|" "${REPO_ENV}"
		fi
		echo "Updated STACK_ROOT in ${REPO_ENV}"
	else
		echo "STACK_ROOT=${STACK_ROOT}" >>"${REPO_ENV}"
		echo "Appended STACK_ROOT to ${REPO_ENV}"
	fi
else
	if [[ -f "${REPO_ROOT}/.env.example" ]]; then
		cp "${REPO_ROOT}/.env.example" "${REPO_ENV}"
		if [[ "$(uname -s)" == "Darwin" ]]; then
			sed -i '' "s|^STACK_ROOT=.*|STACK_ROOT=${STACK_ROOT}|" "${REPO_ENV}"
		else
			sed -i "s|^STACK_ROOT=.*|STACK_ROOT=${STACK_ROOT}|" "${REPO_ENV}"
		fi
		echo "Created ${REPO_ENV} from .env.example with resolved STACK_ROOT"
	else
		echo "STACK_ROOT=${STACK_ROOT}" >"${REPO_ENV}"
		echo "Created minimal ${REPO_ENV}"
	fi
fi

# Ensure PUID/PGID exist in repo .env (non-destructive append).
for kv in "PUID=0" "PGID=0"; do
	key="${kv%%=*}"
	if ! grep -q "^${key}=" "${REPO_ENV}" 2>/dev/null; then
		echo "${kv}" >>"${REPO_ENV}"
	fi
done

# ── 3. Create volume directories for all stacks ───────────────────────
echo ""
echo "Creating volume directories under ${STACK_ROOT} ..."

for entry in "${STACK_MANIFEST[@]}"; do
	# Skip comments and blank lines
	[[ "${entry}" =~ ^[[:space:]]*# ]] && continue
	[[ -z "${entry// /}" ]] && continue
	# Strip quotes if present
	entry="${entry//\"/}"
	stack="${entry%%:*}"
	sub_folders="${entry##*:}"
	# Trailing "stack:" with no sub-folders — omit stack: create nothing under STACK_ROOT.
	[[ -z "${sub_folders}" ]] && continue
	IFS=',' read -ra folders <<<"${sub_folders}"
	for folder in "${folders[@]}"; do
		[[ -z "${folder}" ]] && continue
		dir="${STACK_ROOT}/${stack}/${folder}"
		mkdir -p "${dir}"
		echo "  ✓ staged: ${dir}"
	done
done

# ── 4. Run fix-permissions.sh ─────────────────────────────────────────
echo ""
echo "Fixing permissions ..."
if [[ "$(id -u)" -eq 0 ]]; then
	bash "${SCRIPT_DIR}/fix-permissions.sh" "${STACK_ROOT}"
else
	echo "WARN: not root; run: sudo bash ${SCRIPT_DIR}/fix-permissions.sh ${STACK_ROOT}" >&2
fi

echo ""
echo "────────────────────────────────────────"
echo "Init complete."
echo "STACK_ROOT = ${STACK_ROOT}"
echo "Now open Dockge and deploy your stacks."
echo "────────────────────────────────────────"

# ── Write hash after successful full init (--if-changed runs only) ───
if [[ "${IF_CHANGED_MODE:-0}" -eq 1 ]]; then
	echo "${CURRENT_HASH}" >"${HASH_FILE}"
	echo "init-nas.sh: hash updated for next --if-changed run."
fi
