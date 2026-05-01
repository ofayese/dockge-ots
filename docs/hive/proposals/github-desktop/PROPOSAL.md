# PROPOSAL — github-desktop

**Owner:** operator · **2026-04-30**

## Summary

Align **PUID/PGID** defaults with repo NAS policy (`0`/`0`) and refresh operator README/`SETUP` snippets for `chown root:root` + `fix-permissions.sh`.

## Rollback

Revert `compose.yaml` environment defaults and README if a non-root bind-mount owner is required on your NAS.
