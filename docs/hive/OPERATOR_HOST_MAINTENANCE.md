# Operator host maintenance (DSM, Docker logging, nginx, Git)

Consolidated **operator runbooks** for risky host-level changes. These are **manual** procedures unless a linked repo script explicitly performs a read-only probe. Do **not** silently enable experimental DSM features from automation.

## 5.1 — 007revad / M2 volume tooling (support and warranty)

- **Support / warranty:** Third-party volume drivers and unofficial DSM modules can void vendor support or complicate warranty claims. Treat every install as a **maintenance-window** change with a written rollback.
- **Backups:** Take **Hyper Backup** and **Snapshot Replication** (or BTRFS snapshots) of affected volumes **before** installation or upgrade.
- **DSM version pin:** Document the **from → to** DSM build numbers and the revad package version. If DSM auto-update is enabled, **pause updates** until the driver is confirmed compatible with the target build.
- **Rollback:** Keep the previous `.spk` / driver package and the prior DSM recovery notes; plan disk-order and pool-import steps if the M2 volume hosts irreplaceable metadata.
- **Probes only:** If a script only **lists** disks, M2 status, or `cat /proc/mdstat`, it is informational. Do not chain probes into silent `insmod` / package install without explicit operator approval.

**Operator acknowledgment (fleet / change windows):** Before installing or upgrading **007revad-class** M.2 volume tooling, the operator documents agreement with the bullets above (support/warranty, backups, DSM build pin, rollback) in the change ticket or runbook — **no** repo CI or agent may apply DSM patches or drivers autonomously.

## 5.2 — telnetdoogie / Docker logging (fleet-wide risk)

Docker daemon log drivers and log opts affect **every** container that does not override `logging:`.

- **Sequence:** (1) Add or tighten **`logging:`** per stack in **compose** for high-churn services first; (2) measure disk use and `docker logs` behavior; (3) only then consider **daemon-wide** defaults in `daemon.json`.
- **Rollback:** Keep a copy of the previous `daemon.json` and a reboot/restart plan. Validate **`docker compose`** for critical stacks after each step.
- **Risk:** Aggressive rotation can hide incidents; too loose rotation can fill `/var/log` or slow BTRFS. Prefer **measured** `max-size` / `max-file` aligned with NAS retention policy.

## 5.3 — DSM nginx Basic Auth escaping (separate from ACME)

- DSM’s reverse-proxy / nginx layers are **not** replaced by this repo’s acme.sh + Traefik path. Basic Auth strings in generated nginx snippets must **escape** `$` and special characters per DSM’s parser.
- **DSM upgrade overwrite:** DSM updates can reset or merge nginx fragments. Re-apply custom snippets after upgrades and keep a **git-tracked** copy of your final nginx fragment outside DSM-only paths if possible.

## 5.4 — Apple Metadata Cleanup (macOS SMB Shares)

- **Default:** `DRY_RUN=1` — the script prints planned removals only until you explicitly set `DRY_RUN=0` after review.
- **Script:** `scripts/maintenance/remove_apple_hidden_files.sh` — **safe-by-default** with `DRY_RUN=1` (prints planned `rm` only). Run with `DRY_RUN=0` only after reviewing dry-run output on a copy or narrow path list.
- **Warning — no blind `._*` sweeps:** Do not run bulk `find … -name '._*' -delete` (or similar) across entire shares; that can strip valid AppleDouble sidecars. Use this repo script’s paired/stray logic and opt-in toggles instead of wholesale deletion.
- **Why not blanket `._*` deletes:** Blind removal of every small `._*` file can strip Finder / AppleDouble **resource-fork** sidecars the OS or apps still expect on some shares. Default behavior keeps **paired** cleanup (stub only when a sibling data file exists) unless you explicitly opt in.
- **Optional toggles (review dry-run first):**
  - `APPLE_CLEANUP_ORPHAN_DOT_UNDERSCORE=1` — also remove tiny orphan `._*` files with **no** sibling; higher risk of removing harmless-but-attached metadata.
  - `APPLE_CLEANUP_STRAY_SYNO_SIDECARS=1` — remove **stray** only `*@SynoEAStream` / `*@SynoResource` under `@eaDir` when the primary file path no longer exists (Synology sidecar clutter).
- **Out of scope:** This repo **does not** implement upstream **`hwdbk/synology-scripts`** **`cleanup_SynoFiles`**-style **bogus-xattr** cleanup that depends on helper tooling (**`get_attr`** + **`xattrs.lst`**). Use DSM/Mac-side `xattr` workflows if you need that depth.

## 6 — Git usability on Synology (dmurphyoz-style hardening)

- **`git-shell-commands`:** Restrict login shells for dedicated Git users to a small allow-listed command set (e.g. `git-upload-pack`, `git-receive-pack`, custom repo-creation helpers).
- **Permissions:** Home directory **`711`**, **`~/.ssh` `711`**, **`authorized_keys` `600`** — enough for `sshd` to read keys without exposing other users’ listings where policy requires it.
- **Example (operator runs on client):**  
  `ssh gituser@nas "git-create-repository Foo.git"`  
  where `git-create-repository` is a **server-side** allowed command that prepares a bare repo path and `git update-server-info` as needed.
- **Parity with fail2ban / SSH:** Keep **`MaxAuthTries`**, **`PasswordAuthentication no`**, and jail times aligned with the rest of the fleet; Git-over-SSH inherits the same **`sshd`** surface — rate limits and keys matter more when HTTP helpers are not in path.
