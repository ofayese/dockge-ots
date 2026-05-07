# stack-audit

Audit all Dockge-managed Docker stacks on this NAS for configuration issues, missing bind-mount directories, port conflicts, environment drift, and compose-file hygiene. Output a prioritized, actionable fix list.

## Purpose

This command performs a comprehensive read-only audit of every stack under `/volume1/docker/dockge/stacks/`. It checks for common problems that cause stacks to fail silently or behave unexpectedly, then produces a numbered list of issues ranked by severity (Critical → Warning → Info).

## Steps

### 1. Discover all stacks

```bash
ls /volume1/docker/dockge/stacks/
```

For each subdirectory found, treat it as a stack. Record the stack name and path.

### 2. Validate compose.yaml existence and syntax

For each stack directory:
- Check that `compose.yaml` (or `docker-compose.yaml`) exists. If missing → **Critical**.
- Run `docker compose -f <path>/compose.yaml config --quiet` to validate syntax. Any error → **Critical**, include the error output.

### 3. Check bind-mount host paths exist

Parse the `volumes:` sections of each `compose.yaml`. For every entry that uses a host path (not a named volume), verify the directory exists on the host:
```bash
stat <host-path>
```
Missing host paths → **Critical** (container will fail to start).

### 4. Check `.env` file presence and variable coverage

- Check if a `.env` file exists alongside `compose.yaml`.
- If `.env.example` or `.env.sample` is present, diff its keys against the actual `.env` to find missing or extra variables.
- Missing required variables → **Warning**.

### 5. Detect deprecated host path patterns

Scan all `compose.yaml` volumes for paths that start with `/volume1/docker/<stack-name>/` (outside `dockge/stacks/`). These are deprecated per project conventions. Flag each as **Warning** with suggested migration path.

### 6. Check port conflicts across stacks

Extract all `ports:` entries from every `compose.yaml`. Look for the same host port bound by more than one stack. Conflicts → **Critical** (only one can start; the other silently fails).

### 7. Verify STACK_ROOT usage

Check that bind-mount paths use `${STACK_ROOT}` variable substitution rather than hard-coded absolute paths where applicable. Hard-coded paths → **Warning** (breaks portability).

### 8. Check for containers currently in unhealthy or exited state

```bash
docker ps -a --format '{{.Names}}\t{{.Status}}' | grep -E 'Exit|unhealthy'
```
Any unhealthy or exited containers → **Warning**, include container name and exit code.

### 9. Check image versions for pinning

For each service in each `compose.yaml`, check whether the image uses `:latest` or no tag. Unpinned images → **Info** (risk of unexpected upgrades on pull).

### 10. Compile and output the report

Format the results as:

```
## Stack Audit Report — <date>

### CRITICAL (fix before next deploy)
1. [stack-name] <issue description> → <suggested fix>

### WARNING (fix soon)
1. [stack-name] <issue description> → <suggested fix>

### INFO (consider addressing)
1. [stack-name] <issue description> → <suggested fix>

### PASS
- [stack-name] No issues found.
```

If there are no issues, say so clearly.

## Tools to use

- `Bash` — for `ls`, `stat`, `docker compose config`, `docker ps`
- `Read` — for reading `compose.yaml` and `.env` files
- `Glob` — for finding all `compose.yaml` files under `/volume1/docker/dockge/stacks/`
- `Grep` — for extracting ports, volume paths, and image references from compose files

## Constraints

- This is a **read-only** audit. Do not modify any files.
- Do not start, stop, or restart any containers.
- If a `compose.yaml` file is malformed and `docker compose config` fails, still continue auditing the remaining stacks.
- The canonical stacks root is `/volume1/docker/dockge/stacks/`.

## Example output

```
## Stack Audit Report — 2026-05-06

### CRITICAL
1. [warp-main] Port 8080 also claimed by [traefik] → change one stack's host port
2. [jellyfin] Bind-mount /volume1/media does not exist → create the directory or update compose.yaml

### WARNING
3. [gitea] .env missing keys: GITEA__database__PASSWD → add to .env from .env.example
4. [uptime-kuma] Image uses :latest tag → pin to a specific version

### PASS
- traefik: No issues found.
- dozzle: No issues found.
```
