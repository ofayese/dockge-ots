# HolyClaude Stack

Dev-only HolyClaude workstation stack for Synology Dockge.

## Run

1. Copy `.env.example` to `.env` and fill values.
2. Start stack:
   - `docker compose -f compose.yaml up -d`
3. Open:
   - `http://<nas-ip>:3059`

## Persistence

- Agent/workstation config:
  - `claude-home:/home/claude/.claude`
- Project workspace:
  - `${WORKSPACE_PATH}:/workspace` (set in `.env`; use NAS stack root path)
- CloudCLI persistent state (survives rebuild/recreate/down-up without `-v`):
  - `cloudcli-data:/home/claude/.cloudcli`

Important: `docker compose down -v` removes named volumes, including `cloudcli-data`.
This also removes `claude-home`.

## Notifications (Discord)

Set in local `.env`:

- `DISCORD_WEBHOOK_URL=...` (same secret style as `acme-sh`)
- `NOTIFY_DISCORD=discord://webhook_id/webhook_token`

Enable notifications inside container:

- `touch /home/claude/.claude/notify-on`

Disable:

- `rm /home/claude/.claude/notify-on`

Reference formats:

- `https://github.com/CoderLuii/HolyClaude/blob/master/docs/configuration.md`

## Baseline and HAProxy gate

This stack must pass baseline verification first (including `.claude-flow` read/write and persistence tests) before any HAProxy/TLS integration is proposed or applied.

## Verification checklist

- `docker compose -f compose.yaml config` succeeds.
- Service is reachable on `http://<nas-ip>:3059`.
- Inside HolyClaude:
  - `ls /workspace/.claude-flow`
  - create and remove `/workspace/.claude-flow/holyclaude-write-test.txt`
- Persistence:
  - create `/home/claude/.cloudcli/persist-check.txt`
  - verify after rebuild/recreate/down-up cycles without `-v`.
