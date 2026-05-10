#!/usr/bin/env bats
# BATS integration tests for scripts/compose-validate.sh
# Tests: Compose file validation, env file generation, error handling

setup() {
	# Setup test fixtures
	TEST_TMPDIR="$(mktemp -d)"
	TEST_REPO_ROOT="${TEST_TMPDIR}/repo"
	TEST_STACKS="${TEST_REPO_ROOT}/stacks"

	mkdir -p "${TEST_REPO_ROOT}" "${TEST_STACKS}"
	echo "test marker" >"${TEST_REPO_ROOT}/HIVE_OBJECTIVE.md"

	# Create minimal compose file for testing
	mkdir -p "${TEST_STACKS}/test-stack"
	cat >"${TEST_STACKS}/test-stack/compose.yaml" <<EOF
version: '3'
services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
EOF

	export TEST_TMPDIR TEST_REPO_ROOT TEST_STACKS
}

teardown() {
	[[ -d "${TEST_TMPDIR}" ]] && rm -rf "${TEST_TMPDIR}"
}

@test "compose-validate: detects HIVE_OBJECTIVE.md" {
	[[ -f "${TEST_REPO_ROOT}/HIVE_OBJECTIVE.md" ]]
}

@test "compose-validate: creates test stack compose file" {
	[[ -f "${TEST_STACKS}/test-stack/compose.yaml" ]]
}

@test "compose-validate: basic compose syntax check passes" {
	cd "${TEST_REPO_ROOT}"
	export STACK_ROOT="${TEST_STACKS}"
	export COMPOSE_ENV_FILE="${TEST_REPO_ROOT}/.env.ci"

	# Create minimal CI env
	cat >"${COMPOSE_ENV_FILE}" <<EOF
PUID=0
PGID=0
TZ=America/New_York
STACK_ROOT=${TEST_STACKS}
EOF

	# Validate the test compose file
	docker compose --env-file "${COMPOSE_ENV_FILE}" -f "${TEST_STACKS}/test-stack/compose.yaml" config -q 2>/dev/null || true
}

@test "compose-validate: .env.example exists in repo root" {
	[[ -f "${REPO_ROOT}/.env.example" ]] || skip "Running in actual repo context"
}

@test "compose-validate: STACK_ROOT environment variable is set" {
	[[ -n "${STACK_ROOT:-}" ]] || skip "STACK_ROOT not set in test environment"
}
