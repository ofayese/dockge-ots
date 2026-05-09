---
name: nas-reset-recovery
description: Recover a Synology NAS Dockge deployment after reset with safe git/bootstrap and Dockge validation steps.
---

# NAS Reset Recovery

- Install Container Manager and enable SSH.
- Clone repo to `/volume1/docker/dockge` and set repo-local `safe.directory`.
- Run `sudo bash scripts/init-nas.sh`.
- Install and run `scripts/dockge-start.sh` as `/usr/local/etc/rc.d/dockge.sh`.
- Verify Dockge bind is `5571:5001` via `docker inspect Dockge`.
- If git fails after sudo Docker ops, repair ownership and pull as non-root.
