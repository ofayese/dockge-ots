---
name: subnet-registry
description: Maintain explicit Docker network names and 172.x/24 subnet allocations for all stacks.
---

# Subnet Registry

- Do not use `192.168.x.x` in compose network definitions.
- Use explicit `name`, `driver: bridge`, `subnet`, and `gateway`.
- Keep allocations in `docs/hive/NAS_DEPLOYMENT.md` in sync with compose files.
- Reserve next free `/24` before assigning new stack networks.
