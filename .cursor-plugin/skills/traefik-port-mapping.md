---
name: traefik-port-mapping
description: Prevent Traefik listener and published-port mismatches in Synology homelab deployments.
---

# Traefik Port Mapping

- Container entrypoints listen on `:80` and `:443`.
- Host ports should map to internal listener ports (for example `8880:80`, `6443:443`).
- Dashboard URL requires trailing slash: `/dashboard/`.
- `api.insecure=false` returns 404 at dashboard root by design.
- "Connection dropped" usually means published port has no container listener.
