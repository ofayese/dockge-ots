# Operator host maintenance (DSM, Docker logging, nginx, Git)

Consolidated **operator runbooks** for risky host-level changes. These are **manual** procedures unless a linked repo script explicitly performs a read-only probe. Do **not** silently enable experimental DSM features from automation.

## 5.1 — 007revad / M2 volume tooling (support and warranty)

- **Support / warranty:** Third-party volume drivers and unofficial DSM modules can void vendor support or complicate warranty claims. Treat every install as a **maintenance-window** change with a written rollback.
- **Backups:** Take **Hyper Backup** and **Snapshot Replication** (or BTRFS snapshots) of affected volumes **before** installation or upgrade.
- **DSM version pin:** Document the **from → to** DSM build numbers and the revad package version. If DSM auto-update is enabled, **pause updates** until the driver is confirmed compatible with the target build.
- **Rollback:** Keep the previous `.spk` / driver package and the prior DSM recovery notes; plan disk-order and pool-import steps if the M2 volume hosts irreplaceable metadata.
- **Probes only:** If a script only **lists** disks, M2 status, or `cat /proc/mdstat`, it is informational. Do not chain probes into silent `insmod` / package install without explicit operator approval.

## 5.2 — telnetdoogie / Docker logging (fleet-wide risk)

Docker daemon log drivers and log opts affect **every** container that does not override `logging:`.

- **Sequence:** (1) Add or tighten **`logging:`** per stack in **compose** for high-churn services first; (2) measure disk use and `docker logs` behavior; (3) only then consider **daemon-wide** defaults in `daemon.json`.
- **Rollback:** Keep a copy of the previous `daemon.json` and a reboot/restart plan. Validate **`docker compose`** for critical stacks after each step.
- **Risk:** Aggressive rotation can hide incidents; too loose rotation can fill `/var/log` or slow BTRFS. Prefer **measured** `max-size` / `max-file` aligned with NAS retention policy.

## 5.3 — DSM nginx Basic Auth escaping (separate from ACME)

- DSM’s reverse-proxy / nginx layers are **not** replaced by this repo’s acme.sh + Traefik path. Basic Auth strings in generated nginx snippets must **escape** `$` and special characters per DSM’s parser.
- **DSM upgrade overwrite:** DSM updates can reset or merge nginx fragments. Re-apply custom snippets after upgrades and keep a **git-tracked** copy of your final nginx fragment outside DSM-only paths if possible.

## 6 — Git usability on Synology (dmurphyoz-style hardening)

- **`git-shell-commands`:** Restrict login shells for dedicated Git users to a small allow-listed command set (e.g. `git-upload-pack`, `git-receive-pack`, custom repo-creation helpers).
- **Permissions:** Home directory **`711`**, **`~/.ssh` `711`**, **`authorized_keys` `600`** — enough for `sshd` to read keys without exposing other users’ listings where policy requires it.
- **Example (operator runs on client):**  
  `ssh gituser@nas "git-create-repository Foo.git"`  
  where `git-create-repository` is a **server-side** allowed command that prepares a bare repo path and `git update-server-info` as needed.
- **Parity with fail2ban / SSH:** Keep **`MaxAuthTries`**, **`PasswordAuthentication no`**, and jail times aligned with the rest of the fleet; Git-over-SSH inherits the same **`sshd`** surface — rate limits and keys matter more when HTTP helpers are not in path.
