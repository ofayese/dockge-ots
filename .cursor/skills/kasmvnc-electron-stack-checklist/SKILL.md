---
name: kasmvnc-electron-stack-checklist
description: Validates LinuxServer.io KasmVNC and Electron-style compose stacks for seccomp, PR_NO_NEW_PRIVS, caps, shared memory, healthchecks, and documentation. Use when adding or editing KasmVNC/Electron/GUI-in-browser stacks, linuxserver baseimage-kasmvnc images, github-desktop-style compose, or when the user mentions setuid sandbox helpers, NNP, seccomp unconfined, or Block 3 healthcheck policy for VNC apps.
---

# KasmVNC / Electron stack checklist

The combination is almost certainly wrong for any image that uses
a setuid sandbox helper. Check the image docs before assuming it
is safe to keep both.

---

## New KasmVNC stack checklist

Before shipping a new LinuxServer.io KasmVNC or Electron stack:

- [ ] `seccomp:unconfined` present
- [ ] `no-new-privileges:true` absent — comment explains why
- [ ] `IPC_LOCK` in `cap_add`
- [ ] `shm_size` set to at least `1g`
- [ ] README Permissions section explains NNP omission
- [ ] Security Advisor warnings table updated in repo-level docs
- [ ] Healthcheck is type B (TCP on KasmVNC internal port 3000)
      with `start_period` of at least `90s` for Electron init

---

## Reference

- Electron sandbox docs: https://chromium.googlesource.com/chromium/src/+/main/docs/linux/sandboxing.md
- Docker PR_NO_NEW_PRIVS: https://docs.docker.com/engine/security/seccomp/
- LinuxServer.io KasmVNC base: ghcr.io/linuxserver/baseimage-kasmvnc
- Dockge repo commits: c75af1b (NNP added incorrectly) → bfa07bd (removed with docs)

---

## Repo conventions (this workspace)

- Standing rule for `no-new-privileges` and documented NNP exceptions: `AGENTS.md` → **Stack hardening defaults**.
- Healthcheck policy and exemptions: `docs/hive/HEALTHCHECK_EXEMPTIONS.md`.
- NAS-facing Security Advisor table: `docs/hive/NAS_DEPLOYMENT.md`.

When editing compose, align inline comments with the pattern required in `AGENTS.md` (reason + do not add `--no-sandbox` where applicable).
