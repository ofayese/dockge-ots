#!/bin/sh
# =============================================================================
# Dockge startup script — Synology DSM rc.d replacement
# =============================================================================
# Drop this file at /usr/local/etc/rc.d/dockge.sh on the NAS and chmod +x it.
#
# Changes vs. original script:
#   1. Image: louislam/dockge:base  →  louislam/dockge:1  (production release;
#      :base is a builder layer, not the app).  Latest stable = 1.5.0.
#   2. Security: added --security-opt no-new-privileges:true
#   3. Resources: added --memory 512m --cpu-shares 512
#   4. Logging: added --log-driver json-file with size cap
#   5. Port: host 5571→container 5571 (image default). Homepage/HAProxy must use 5571.
#   6. PUID/PGID: default root (0:0) for Synology bind-mount ownership; override if needed.
#   7. sleep 20 retained — required for Synology Docker daemon startup sequence.
#
# Default PUID/PGID are root (0:0), matching `HIVE_OBJECTIVE.md` NAS notes. Override only
# if a non-root owner is required for the stacks directory.
# =============================================================================

set -e

DOCKER="/usr/local/bin/docker"
NAME="Dockge"
IMAGE="louislam/dockge:1"
PUID="${PUID:-0}"
PGID="${PGID:-0}"
# Repo root on the NAS (contains stacks/, scripts/, .git, etc.). Dockge app state
# (SQLite, etc.) lives here — no separate .../data/ subfolder required.
# Legacy layout: .../dockge/data/ was mounted at /app/data (dockge.db lived there).
# This script one-time-moves ${DOCKGE_ROOT}/data/* into ${DOCKGE_ROOT}/ when
# data/dockge.db exists and repo-root dockge.db does not — avoids silent DB loss.
DOCKGE_ROOT="${DOCKGE_ROOT:-/volume1/docker/dockge}"

sleep 20

# One-time migration from old .../dockge/data/ bind to repo-root /app/data bind.
migrate_legacy_app_data() {
	legacy_dir="${DOCKGE_ROOT}/data"
	[ -f "${legacy_dir}/dockge.db" ] || return 0
	[ -f "${DOCKGE_ROOT}/dockge.db" ] && return 0
	echo "dockge-start: migrating Dockge app state from ${legacy_dir}/ to ${DOCKGE_ROOT}/ (one-time)"
	find "${legacy_dir}" -mindepth 1 -maxdepth 1 | while IFS= read -r f; do
		[ -n "$f" ] || continue
		bn=$(basename "$f")
		case "$bn" in
		stacks | scripts | .git) continue ;;
		esac
		dest="${DOCKGE_ROOT}/${bn}"
		if [ -e "$dest" ]; then
			echo "dockge-start: migration skip (exists): ${dest}"
			continue
		fi
		mv "$f" "$dest"
	done
}

migrate_legacy_app_data

exists() {
	$DOCKER ps -a --format '{{.Names}}' | grep -qx "$NAME"
}

current_image() {
	$DOCKER inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null || true
}

create_container() {
	mkdir -p "${DOCKGE_ROOT}/stacks"
	$DOCKER run -d \
		--name="$NAME" \
		-p 5571:5571 \
		--restart=on-failure:5 \
		--security-opt no-new-privileges:true \
		--memory 512m \
		--cpu-shares 512 \
		--log-driver json-file \
		--log-opt max-size=10m \
		--log-opt max-file=3 \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v "${DOCKGE_ROOT}/stacks:${DOCKGE_ROOT}/stacks" \
		-v "${DOCKGE_ROOT}:/app/data" \
		-e "DOCKGE_STACKS_DIR=${DOCKGE_ROOT}/stacks" \
		-e PUID="$PUID" \
		-e PGID="$PGID" \
		-e TZ=America/New_York \
		"$IMAGE"
}

$DOCKER pull "$IMAGE"

if exists; then
	CURR="$(current_image)"
	if [ "$CURR" != "$IMAGE" ]; then
		$DOCKER stop "$NAME" || true
		$DOCKER rm "$NAME" || true
		create_container
	else
		$DOCKER start "$NAME" || true
	fi
else
	create_container
fi
