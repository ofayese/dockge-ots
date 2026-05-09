---
name: synology-git-safety
description: Safe git workflow for Synology-hosted repos with @eaDir and root-ownership pitfalls.
---

# Synology Git Safety

- Run git as the NAS user, not root.
- Avoid `git add -A` on NAS working trees.
- Clean `@eaDir` refs if DSM indexing polluted `.git/refs`.
- Keep `safe.directory` in repo config when global config is locked.
- After privileged writes, run `chown -R <user>:<group> /volume1/docker/dockge`.
