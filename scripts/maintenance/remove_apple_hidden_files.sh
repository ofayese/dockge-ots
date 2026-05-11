#!/usr/bin/env bash
# Remove Apple SMB / Finder metadata files under operator-chosen paths.
# Safe-by-default: DRY_RUN=1 (no deletes). Use Task Scheduler only after dry-run review.
#
# Usage:
#   DRY_RUN=1 APPLE_CLEANUP_ROOT=/volume1/docker/dockge bash scripts/maintenance/remove_apple_hidden_files.sh
#   DRY_RUN=0 APPLE_CLEANUP_PATHS_FILE=/path/to/paths.list bash scripts/maintenance/remove_apple_hidden_files.sh
#
# paths.list: one absolute directory path per line; # comments and blank lines ignored.
set -euo pipefail

DRY_RUN="${DRY_RUN:-1}"
APPLE_CLEANUP_ROOT="${APPLE_CLEANUP_ROOT:-}"
APPLE_CLEANUP_PATHS_FILE="${APPLE_CLEANUP_PATHS_FILE:-}"
# Max size (bytes) for ._* resource-fork stubs; larger files are skipped.
MAX_DOT_UNDERSCORE_BYTES="${MAX_DOT_UNDERSCORE_BYTES:-65536}"

usage() {
	cat <<'USAGE'
remove_apple_hidden_files.sh — prune .DS_Store, small ._* , .AppleDouble dirs

  DRY_RUN=1|0           default 1 — print actions only
  APPLE_CLEANUP_ROOT   single directory root (optional if PATHS_FILE set)
  APPLE_CLEANUP_PATHS_FILE  file with one absolute path per line
  MAX_DOT_UNDERSCORE_BYTES  default 65536 (use with find -size -Nc, N in bytes)

Prunes descent into: .git, node_modules, @eaDir (do not remove Synology @eaDir metadata)
USAGE
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
	usage
	exit 0
}

trim_ws() {
	local s="$1"
	s="${s%%$'\r'}"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "${s}"
}

collect_roots() {
	local roots=()
	if [[ -n "${APPLE_CLEANUP_PATHS_FILE}" ]]; then
		if [[ ! -f "${APPLE_CLEANUP_PATHS_FILE}" ]]; then
			echo "ERROR: APPLE_CLEANUP_PATHS_FILE is not a file: ${APPLE_CLEANUP_PATHS_FILE}" >&2
			exit 2
		fi
		while IFS= read -r line || [[ -n "${line}" ]]; do
			line="$(trim_ws "${line}")"
			[[ -z "${line}" || "${line:0:1}" == '#' ]] && continue
			roots+=("${line}")
		done <"${APPLE_CLEANUP_PATHS_FILE}"
	fi
	if [[ -n "${APPLE_CLEANUP_ROOT}" ]]; then
		roots+=("${APPLE_CLEANUP_ROOT}")
	fi
	if [[ "${#roots[@]}" -eq 0 ]]; then
		echo "ERROR: Set APPLE_CLEANUP_ROOT and/or APPLE_CLEANUP_PATHS_FILE" >&2
		exit 2
	fi
	printf '%s\n' "${roots[@]}"
}

delete_file() {
	local f="$1"
	if [[ "${DRY_RUN}" == "1" ]]; then
		printf 'DRY_RUN rm -f -- %q\n' "${f}"
		return 0
	fi
	rm -f -- "${f}"
}

delete_dir() {
	local d="$1"
	if [[ "${DRY_RUN}" == "1" ]]; then
		printf 'DRY_RUN rm -rf -- %q\n' "${d}"
		return 0
	fi
	rm -rf -- "${d}"
}

process_root() {
	local root="$1"
	if [[ ! -d "${root}" ]]; then
		echo "WARN: skip (not a directory): ${root}" >&2
		return 0
	fi
	echo "==> ${root} (DRY_RUN=${DRY_RUN})"

	while IFS= read -r -d '' f; do
		delete_file "${f}"
	done < <(
		find "${root}" \( -name .git -o -name node_modules -o -name '@eaDir' \) -prune -o \
			-name '.DS_Store' -type f -print0 2>/dev/null
	)

	# GNU/BSD find: -size -${N}c = strictly less than N bytes
	local size_arg="-${MAX_DOT_UNDERSCORE_BYTES}c"
	while IFS= read -r -d '' f; do
		delete_file "${f}"
	done < <(
		find "${root}" \( -name .git -o -name node_modules -o -name '@eaDir' \) -prune -o \
			-name '._*' -type f -size "${size_arg}" -print0 2>/dev/null
	)

	while IFS= read -r -d '' d; do
		delete_dir "${d}"
	done < <(
		find "${root}" \( -name .git -o -name node_modules -o -name '@eaDir' \) -prune -o \
			-depth -type d -name '.AppleDouble' -print0 2>/dev/null
	)
}

_roots=()
while IFS= read -r line; do
	[[ -z "${line}" ]] && continue
	_roots+=("${line}")
done < <(collect_roots | sort -u)
for r in "${_roots[@]}"; do
	process_root "${r}"
done

echo "Done."
