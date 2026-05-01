#!/usr/bin/env bash
# Validate Compose files parse and interpolate (no pull / no run).
# Repo root = parent of scripts/; compose stacks live under stacks/.
set -euo pipefail
# Repo root contains HIVE_OBJECTIVE.md (works from repo/scripts or repo/stacks/scripts).
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${_script_dir}"
while [[ ! -f "${ROOT}/HIVE_OBJECTIVE.md" && "${ROOT}" != "/" ]]; do
	ROOT="$(dirname "${ROOT}")"
done
[[ -f "${ROOT}/HIVE_OBJECTIVE.md" ]] || {
	echo "ERROR: could not find repo root (HIVE_OBJECTIVE.md) above ${_script_dir}" >&2
	exit 1
}
STACKS="${ROOT}/stacks"
cd "$ROOT"

export COMPOSE_ENV_FILE="${ROOT}/.github/compose-ci.env"

mkdir -p "${STACKS}/grafana-prom/secrets"
if [[ ! -s "${STACKS}/grafana-prom/secrets/watchtower_bearer_token.txt" ]]; then
	printf 'ci-watchtower-bearer-token\n' >"${STACKS}/grafana-prom/secrets/watchtower_bearer_token.txt"
fi

mkdir -p "${STACKS}/databases/secrets"
for f in mariadb_root_pw.txt mariadb_app_pw.txt postgres_pw.txt; do
	if [[ ! -s "${STACKS}/databases/secrets/${f}" ]]; then
		printf 'ci-dummy-db-secret\n' >"${STACKS}/databases/secrets/${f}"
	fi
done

mkdir -p /tmp/workspace 2>/dev/null || true

created_env_files=()
cleanup() {
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		for p in "${created_env_files[@]+"${created_env_files[@]}"}"; do
			rm -f "${p}"
		done
	fi
}
trap cleanup EXIT

if [[ ! -f "${STACKS}/codex-docs/.env" ]]; then
	printf 'APP_SECRET=ci_dummy_app_secret_at_least_thirty_two_chars_long\n' >"${STACKS}/codex-docs/.env"
	created_env_files+=("${STACKS}/codex-docs/.env")
fi

if [[ ! -f "${STACKS}/holyclaude/.env" ]]; then
	cat >"${STACKS}/holyclaude/.env" <<EOF
PUID=1000
PGID=1000
DISCORD_WEBHOOK_URL=
NOTIFY_DISCORD=false
WORKSPACE_PATH=/tmp/workspace
EOF
	created_env_files+=("${STACKS}/holyclaude/.env")
fi

while IFS= read -r f; do
	[[ -n "${f}" ]] || continue
	rel="${f#"${ROOT}"/}"
	dir="$(dirname "${f}")"
	base="$(basename "${f}")"
	echo "compose config: ${rel}"
	(
		cd "${dir}"
		docker compose --env-file "${COMPOSE_ENV_FILE}" -f "${base}" config -q
	)
done < <(find "${STACKS}" -maxdepth 4 \( -name compose.yaml -o -name docker-compose.yml -o -name docker-compose.yaml \) ! -path '*/.git/*' | sort)

echo "All compose files validated OK."
