# nas-docker-helper

Docker/Dockge stack management, NAS automation, and homelab ops plugin for Claude Code.

## Installation

```
/plugin install ./nas-docker-helper
```

Then reload:

```
/reload-plugins
```

## Components

### Slash Command: `/nas-docker-helper:stack-audit`

Audits all Dockge-managed stacks under `/volume1/docker/dockge/stacks/` for:

- Missing or malformed `compose.yaml` files
- Missing bind-mount host directories
- Port conflicts across stacks
- Environment variable drift (`.env` vs `.env.example`)
- Deprecated host path patterns
- Unpinned image tags
- Unhealthy or exited containers

Outputs a prioritized **Critical / Warning / Info** fix list.

**Usage:**

```
/nas-docker-helper:stack-audit
```

---

### Agent: `nas-auditor`

A specialized security and hygiene auditor for the entire NAS Docker environment. Performs an adversarial review covering:

- Secrets and credential exposure in `.env` and `compose.yaml`
- Container privilege escalation (privileged, cap_add, docker socket mounts)
- Network isolation and segmentation
- Image provenance and age
- Data persistence risks
- Resource limits
- Logging configuration

Invoked automatically by Claude Code when you run a security audit task, or you can reference it explicitly.

---

### Skill: `nas-security`

Domain expertise in Docker hardening and Synology NAS security. Loaded on demand when you ask about:

- Container hardening (least privilege, read-only filesystems, capability dropping)
- Secret management (no hardcoded credentials, `.env` hygiene, Docker secrets)
- Network segmentation between stacks
- Synology firewall rules for Docker
- Docker socket proxy patterns

---

### Hook: `compose-validate` (PostToolUse/Write)

Automatically validates `compose.yaml` syntax after every write using `docker compose config --quiet`. If the file has errors, a warning is printed to stderr before you continue. This catches YAML/Compose mistakes immediately after editing.

Triggers on any file matching: `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml`.

## Requirements

- Docker CLI available on the host (required for `stack-audit` command and `compose-validate` hook)
- Python 3 available on the host (required for `compose-validate` hook)
- Stacks located under `/volume1/docker/dockge/stacks/`

## License

MIT © Laolu
