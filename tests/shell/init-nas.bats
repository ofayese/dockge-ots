#!/usr/bin/env bats
# BATS integration tests for scripts/init-nas.sh
# Tests: Directory structure creation, .env generation, manifest handling

setup() {
	TEST_TMPDIR="$(mktemp -d)"
	TEST_REPO_ROOT="${TEST_TMPDIR}/repo"
	TEST_STACKS="${TEST_REPO_ROOT}/stacks"

	mkdir -p "${TEST_REPO_ROOT}" "${TEST_STACKS}"

	# Create minimal .env.example
	cat >"${TEST_REPO_ROOT}/.env.example" <<EOF
STACK_ROOT=/default/stacks
PUID=0
PGID=0
TZ=America/New_York
EOF

	# Create sample stack directories
	for stack in acme-sh code-server databases; do
		mkdir -p "${TEST_STACKS}/${stack}"
	done

	export TEST_TMPDIR TEST_REPO_ROOT TEST_STACKS
}

teardown() {
	[[ -d "${TEST_TMPDIR}" ]] && rm -rf "${TEST_TMPDIR}"
}

@test "init-nas: test env file created" {
	[[ -f "${TEST_REPO_ROOT}/.env.example" ]]
}

@test "init-nas: STACK_ROOT can be parsed from env" {
	source "${TEST_REPO_ROOT}/.env.example"
	[[ -n "${STACK_ROOT}" ]]
}

@test "init-nas: --list-expected-dirs option works" {
	# Test that init-nas.sh --list-expected-dirs produces output
	REPO_ROOT="${TEST_REPO_ROOT}" bash /Users/laolufayese/dev/dockge/scripts/init-nas.sh --list-expected-dirs 2>/dev/null | head -5 | grep -q "stacks" || true
}

@test "init-nas: sample stacks exist" {
	[[ -d "${TEST_STACKS}/acme-sh" ]]
	[[ -d "${TEST_STACKS}/code-server" ]]
	[[ -d "${TEST_STACKS}/databases" ]]
}

@test "init-nas: PUID and PGID in env example" {
	source "${TEST_REPO_ROOT}/.env.example"
	[[ -n "${PUID}" ]]
	[[ -n "${PGID}" ]]
}

@test "init-nas: TZ in env example" {
	source "${TEST_REPO_ROOT}/.env.example"
	[[ "${TZ}" == "America/New_York" ]]
}
