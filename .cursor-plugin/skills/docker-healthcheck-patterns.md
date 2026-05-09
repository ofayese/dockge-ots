---
name: docker-healthcheck-patterns
description: Choose compose healthcheck strategy by image capabilities and verify probe tooling before use.
---

# Docker Healthcheck Patterns

- Prefer app-native probes when available (for example `traefik healthcheck --ping`).
- Use `curl`/`wget` HTTP probes only after confirming tool presence in image.
- Keep retries/start_period aligned with service startup behavior.
- Document exceptions when no stable probe endpoint exists.
- Validate with `bash scripts/compose-validate.sh` after changes.
