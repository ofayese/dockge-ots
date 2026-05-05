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
#   5. Port: host 5571→container 5001 (louislam/dockge listens on 5001 inside the image).
#      Homepage/HAProxy backends must target host port 5571.
#   6. PUID/PGID: default root (0:0) for Synology bind-mount ownership; override if needed.
#   7. sleep 20 retained — required for Synology Docker daemon startup sequence.
#
# Default PUID/PGID are root (0:0), matching `HIVE_OBJECTIVE.md` NAS notes. Override only
# if a non-root owner is required for the stacks directory.
#
# App state: ${DOCKGE_ROOT}/data/ is bind-mounted at /app/data (dockge.db, etc.) so the
# git repo root stays free of SQLite files. Stacks stay at ${DOCKGE_ROOT}/stacks.
# =============================================================================

set -e

DOCKER="/usr/local/bin/docker"
NAME="Dockge"
IMAGE="louislam/dockge:1"
PUID="${PUID:-0}"
PGID="${PGID:-0}"
DOCKGE_ROOT="${DOCKGE_ROOT:-/volume1/docker/dockge}"
DATA_DIR="${DOCKGE_ROOT}/data"

sleep 20

# One-time: previous script used -v ${DOCKGE_ROOT}:/app/data (DB at repo root). Move known
# app files into ${DATA_DIR}/ before we mount only data/ at /app/data.
migrate_app_data_into_data_dir() {
	mkdir -p "${DATA_DIR}"
	if [ ! -f "${DATA_DIR}/dockge.db" ] && [ -f "${DOCKGE_ROOT}/dockge.db" ]; then
		echo "dockge-start: moving Dockge app state from repo root into ${DATA_DIR}/ (one-time)"
		for f in dockge.db dockge.db-shm dockge.db-wal db-config.json; do
			[ -e "${DOCKGE_ROOT}/$f" ] || continue
			mv "${DOCKGE_ROOT}/$f" "${DATA_DIR}/"
		done
	fi
}

migrate_app_data_into_data_dir

exists() {
	$DOCKER ps -a --format '{{.Names}}' | grep -qx "$NAME"
}

current_image() {
	$DOCKER inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null || true
}

# Image listens on 5001/tcp; host publishes 5571. Recreate if map is missing/wrong (e.g. old 5571:5571).
# Use HostConfig.PortBindings so stopped containers still evaluate correctly.
dockge_port_map_ok() {
	binds="$($DOCKER inspect -f '{{json .HostConfig.PortBindings}}' "$NAME" 2>/dev/null || echo '')"
	[ -n "$binds" ] || return 1
	echo "$binds" | grep -q '"5001/tcp"' || return 1
	echo "$binds" | grep -q '"HostPort":"5571"' || return 1
	return 0
}

# Recreate if /app/data is still bound to repo root (old script) instead of ${DATA_DIR}/.
dockge_data_mount_ok() {
	mounts="$($DOCKER inspect -f '{{json .Mounts}}' "$NAME" 2>/dev/null || echo '[]')"
	echo "$mounts" | grep -Fq "${DATA_DIR}" || return 1
	echo "$mounts" | grep -Fq '"/app/data"' || return 1
	return 0
}

create_container() {
	mkdir -p "${DOCKGE_ROOT}/stacks" "${DATA_DIR}"
	$DOCKER run -d \
		--name="$NAME" \
		-p 5571:5001 \
		--restart=on-failure:5 \
		--security-opt no-new-privileges:true \
		--memory 512m \
		--cpu-shares 512 \
		--log-driver json-file \
		--log-opt max-size=10m \
		--log-opt max-file=3 \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v "${DOCKGE_ROOT}/stacks:${DOCKGE_ROOT}/stacks" \
		-v "${DATA_DIR}:/app/data" \
		-e "DOCKGE_STACKS_DIR=${DOCKGE_ROOT}/stacks" \
		-e PUID="$PUID" \
		-e PGID="$PGID" \
		-e TZ=America/New_York \
		"$IMAGE"
}

$DOCKER pull "$IMAGE"

if exists; then
	CURR="$(current_image)"
	if [ "$CURR" != "$IMAGE" ] || ! dockge_port_map_ok || ! dockge_data_mount_ok; then
		if [ "$CURR" != "$IMAGE" ]; then
			echo "dockge-start: recreating ${NAME} (image: ${CURR:-none} -> ${IMAGE})"
		elif ! dockge_port_map_ok; then
			echo "dockge-start: recreating ${NAME} (host 5571 must map to container 5001)"
		else
			echo "dockge-start: recreating ${NAME} (/app/data must bind ${DATA_DIR}/)"
		fi
		$DOCKER stop "$NAME" || true
		$DOCKER rm "$NAME" || true
		create_container
	else
		$DOCKER start "$NAME" || true
	fi
else
	create_container
fi
