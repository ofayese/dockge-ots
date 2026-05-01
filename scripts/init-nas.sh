#!/usr/bin/env bash
# init-nas.sh
# Post-clone bootstrap for the Dockge stack repo.
# Run once after git clone on the NAS:
#   sudo bash scripts/init-nas.sh
# Re-run after git pull only if new stacks have been added.
# Idempotent — safe to run multiple times.

set -euo pipefail

# ── 1. Resolve repo root and STACK_ROOT ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ENV="${REPO_ROOT}/.env"
STACKS_IN_REPO="${REPO_ROOT}/stacks"

# Prefer stacks inside this repo (this layout). Else sibling ../stacks next to the
# clone parent. Else STACK_ROOT_OVERRIDE or /dockge/stacks.
if [[ -d "${STACKS_IN_REPO}" ]]; then
	STACK_ROOT="${STACKS_IN_REPO}"
	echo "Auto-detected STACK_ROOT (repo stacks/): ${STACK_ROOT}"
else
	CANDIDATE_STACKS="$(cd "${REPO_ROOT}/.." && pwd)/stacks"
	if [[ -d "${CANDIDATE_STACKS}" ]]; then
		STACK_ROOT="${CANDIDATE_STACKS}"
		echo "Auto-detected STACK_ROOT (sibling stacks/): ${STACK_ROOT}"
	else
		STACK_ROOT="${STACK_ROOT_OVERRIDE:-/dockge/stacks}"
		echo "Using default STACK_ROOT: ${STACK_ROOT}"
		echo "(Override with: STACK_ROOT_OVERRIDE=/your/path sudo bash scripts/init-nas.sh)"
	fi
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

# Format: "stack-name:sub1[,sub2]" — keep aligned with compose bind mounts under ${STACK_ROOT}/<stack>/...
STACK_MANIFEST=(
	"acme-sh:data"
	"agents_gateway_data:data"
	"code-server:config"
	"codex-docs:data"
	"databases:db"
	"docker-model-runner:data"
	"dozzle:data"
	"github-desktop:config"
	"grafana-prom:data,config"
	"holyclaude:data"
	"homepage:config"
	"it-tools:data"
	"mcp-tools-config:data"
	"ollama:data"
	"openresume:data"
	"portainer:data"
	"searxng:config"
	"warp-main:data"
	"watchtower:data"
	"zabbix:db,data,config"
)

for entry in "${STACK_MANIFEST[@]}"; do
	stack="${entry%%:*}"
	sub_folders="${entry##*:}"
	IFS=',' read -ra folders <<<"${sub_folders}"
	for folder in "${folders[@]}"; do
		dir="${STACK_ROOT}/${stack}/${folder}"
		mkdir -p "${dir}"
		echo "  ✓ ${dir}"
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
