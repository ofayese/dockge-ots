# PROPOSAL — warp-main

**Owner:** operator · **2026-04-30**

## Summary

Use **`restart: unless-stopped`** and **healthchecks** on **`warp`**, **`warp-agent`** (HTTP `8080`), and **`warp-claude-cli-sidecar`**. `warp-agent` **`user`** is **`${PUID:-0}:${PGID:-0}`** (defaults match upstream `0:0`).

## Rollback

Restore `restart: unless-stopped` and remove healthchecks if Warp images lack `wget`.
