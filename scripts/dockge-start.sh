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
#   5. Port note: host 5571→container 5001. Homepage/HAProxy must use 5571.
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

sleep 20

exists() {
	$DOCKER ps -a --format '{{.Names}}' | grep -qx "$NAME"
}

current_image() {
	$DOCKER inspect -f '{{.Config.Image}}' "$NAME" 2>/dev/null || true
}

create_container() {
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
		-v /volume1/docker/dockge/stacks:/volume1/docker/dockge/stacks \
		-v /volume1/docker/dockge/data:/app/data \
		-e DOCKGE_STACKS_DIR=/volume1/docker/dockge/stacks \
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
