# PROPOSAL — `holyclaude`

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md)
**Status:** Draft
**Owner:** Queen (with stack worker support)

## Scope

Add a dev-only HolyClaude stack with:

- high-privilege runtime flags retained (`SYS_ADMIN`, `SYS_PTRACE`, `seccomp:unconfined`, `shm_size: 2g`)
- direct baseline exposure on `10.0.1.15:3059`
- named volume persistence for HolyClaude home and CloudCLI state
- Discord notification wiring and `notify-on` runtime toggle

## Baseline inheritance

Baseline gate: This proposal inherits all controls from `../_baseline/PROPOSAL.md` unless explicitly excepted below.

## Stack specifics

1. Image policy follows user direction:
   - `coderluii/holyclaude:latest`
2. Persistence requirement:
   - named volume `claude-home` mounted at `/home/claude/.claude`
   - named volume `cloudcli-data` mounted at `/home/claude/.cloudcli`
3. `.claude-flow` access requirement from inside container:
   - `ls /workspace/.claude-flow`
   - write/remove test file at `/workspace/.claude-flow/holyclaude-write-test.txt`
   - if failed: adjust `PUID`/`PGID`, ownership, mount write access
4. Notification baseline:
   - Discord only first (`DISCORD_WEBHOOK_URL`, `NOTIFY_DISCORD`)
   - enable with `touch /home/claude/.claude/notify-on`

## HAProxy/TLS gate

No HAProxy/TLS routing changes are applied for HolyClaude until baseline acceptance checks pass and evidence is recorded.
When gate is satisfied, route:

- `hcld.otsorundscore.olutechsys.com` -> `10.0.1.15:3059`
- `hcld.otsorundscore.olutech.systems` -> `10.0.1.15:3059`

## Acceptance evidence

- Compose validation output
- Direct baseline access screenshot/check notes
- `.claude-flow` read/write verification notes
- `claude-home` and `cloudcli-data` persistence verification across recreate/down-up without `-v`
- `cloudcli-data` persistence verification across rebuild/recreate/down-up without `-v`
- Notification dry-run evidence
- HAProxy syntax validation note (`haproxy -c`) and rollback step

## Evidence captured (2026-04-30)

- Compose config validation passed with local env file:
  - `docker compose --env-file .env config`
- Stack startup and port mapping confirmed:
  - `0.0.0.0:3059->3001/tcp`
- `.claude-flow` access validated from inside container:
  - `ls /workspace/.claude-flow`
  - create/remove `/workspace/.claude-flow/holyclaude-write-test.txt`
- Persistence validated:
  - sentinel in `/home/claude/.cloudcli/persist-check.txt` survived recreate and down/up (without `-v`)
  - named volumes present: `holyclaude_claude-home`, `holyclaude_cloudcli-data`
- Notify toggle created:
  - `/home/claude/.claude/notify-on`

## Rollback note (HAProxy hcld route)

If the `hcld` route must be reverted, remove the three additions in `_haproxy/haproxy.cfg`:

1. ACL line:
   - `acl host_hcld hdr(host) -i hcld.otsorundscore.olutechsys.com hcld.otsorundscore.olutech.systems`
2. Backend routing line:
   - `use_backend hcld-be if host_hcld`
3. Backend block:
   - `backend hcld-be` and its `server hcld 10.0.1.15:3059 check`

Then run HAProxy syntax validation (`haproxy -c -f <path>`) before reload/apply.
