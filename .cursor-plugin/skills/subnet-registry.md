---
name: subnet-registry
description: Maintain explicit Docker network names and 172.x/24 subnet allocations for all stacks.
---

# Subnet Registry

- All stacks use the shared external network `ots-net` (`172.29.0.0/16`).
- Do not use `192.168.x.x` — DSM Container Manager auto-assigns from that range without explicit IPAM.
- Each `compose.yaml` must declare `networks: { ots-net: { external: true } }` and reference `- ots-net` in every service.
- `init-nas.sh` creates `ots-net` idempotently at bootstrap.
- Exceptions (`warp-network`, `zabbix-net`) retain per-stack `/24` subnets; do not migrate them.
