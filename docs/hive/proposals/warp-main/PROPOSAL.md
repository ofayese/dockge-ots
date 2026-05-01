# PROPOSAL — warp-main

**Owner:** operator · **2026-04-30**

## Summary

Replace `unless-stopped` with **`on-failure:5`** and add **healthchecks** on `warp` and `warp-claude-cli-sidecar` (skip `warp-agent` where the listen port is ambiguous); keep upstream `user: "0:0"` on `warp-agent`.

## Rollback

Restore `restart: unless-stopped` and remove healthchecks if Warp images lack `wget`.
