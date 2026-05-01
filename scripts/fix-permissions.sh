#!/usr/bin/env bash
# =============================================================================
# fix-permissions.sh — Synology NAS stack directory ownership (root:root)
# =============================================================================
# Purpose: After rsync or manual edits, ensure stack bind-mount paths under the
# Dockge stacks root are owned by root (UID/GID 0) with predictable permissions,
# matching Synology Docker’s default container user for bind mounts.
#
# Usage (on the NAS, as root):
#   sudo bash /volume1/docker/dockge/scripts/fix-permissions.sh
#   sudo bash /volume1/docker/dockge/scripts/fix-permissions.sh /volume1/docker/dockge/stacks
#
# Optional second path (e.g. Portainer data outside stacks/):
#   sudo bash .../fix-permissions.sh /volume1/docker/dockge/stacks /volume1/docker/portainer
#
# Idempotent: safe to run multiple times.
# =============================================================================
set -euo pipefail

fix_tree() {
	local target="$1"
	if [[ ! -d "${target}" ]]; then
		echo "WARN: skip (not a directory): ${target}" >&2
		return 0
	fi
	echo "Fixing: ${target}"
	chown -R 0:0 "${target}"
	find "${target}" -type d -exec chmod 755 {} +
	find "${target}" -type f -exec chmod 644 {} +
}

main() {
	if [[ "$(id -u)" -ne 0 ]]; then
		echo "ERROR: run as root (sudo)." >&2
		exit 1
	fi

	local default_stacks="/volume1/docker/dockge/stacks"
	local p1="${1:-${default_stacks}}"
	fix_tree "${p1}"
	if [[ -n "${2:-}" ]]; then
		fix_tree "$2"
	fi
	echo "Done."
}

main "$@"
