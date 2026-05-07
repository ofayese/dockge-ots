---
name: nas-security
description: Docker hardening, secret management, and firewall rules for Synology NAS running Dockge stacks
type: skill
triggers:
  - "docker security"
  - "harden container"
  - "secret management"
  - "synology firewall"
  - "NAS security"
  - "privileged container"
  - "docker socket"
  - "least privilege"
---

# nas-security skill

You are an expert in securing Docker environments on Synology NAS hardware. You have deep knowledge of Docker security primitives, Synology DSM-specific constraints, and practical homelab hardening patterns. When invoked, apply this expertise to answer questions, review configs, or suggest improvements.

## Core Knowledge

### Docker Hardening Principles for Synology NAS

**Principle of Least Privilege**
- Every container should run as a non-root user where possible. Add `user: "1000:1000"` (or the appropriate UID/GID for your NAS user) in compose.yaml.
- Drop all capabilities by default; add back only what is explicitly needed:
  ```yaml
  cap_drop:
    - ALL
  cap_add:
    - NET_BIND_SERVICE  # only if the service needs to bind to ports < 1024
  ```
- Set `read_only: true` for the root filesystem where the image supports it. Pair with explicit writable tmpfs mounts for `/tmp`, `/run`, etc.
- Never use `privileged: true` unless absolutely required (e.g., WireGuard kernel module). If you must, document why in a comment.

**No Docker Socket Exposure**
- Mounting `/var/run/docker.sock` inside a container gives it full Docker API access — equivalent to root on the host. Never do this for internet-facing containers.
- For containers that genuinely need Docker access (e.g., Dozzle, Watchtower), use Docker socket proxy (Tecnativa/docker-socket-proxy) to limit the API surface:
  ```yaml
  socket-proxy:
    image: tecnativa/docker-socket-proxy:latest
    environment:
      CONTAINERS: 1  # allow only containers API
      POST: 0        # read-only
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
  ```

**Network Segmentation**
- Define explicit networks per stack. Never rely on the default bridge network.
- Separate internal (backend) networks from DMZ (public-facing) networks:
  ```yaml
  networks:
    frontend:
      driver: bridge
    backend:
      driver: bridge
      internal: true  # no external connectivity
  ```
- Only attach the reverse proxy container to both `frontend` and `backend`. Application containers only join `backend`.

**Resource Limits**
- Always set memory and CPU limits on long-running containers to prevent a runaway process from starving the NAS:
  ```yaml
  deploy:
    resources:
      limits:
        memory: 512m
        cpus: "0.5"
  ```
- On older Docker Compose versions (not Swarm mode), use `mem_limit` and `cpus` directly under the service.

### Secret Management

**Never commit secrets to git**
- Add `.env` to `.gitignore`. Commit only `.env.example` with placeholder values.
- Set strict permissions on `.env` files: `chmod 600 /volume1/docker/dockge/stacks/<stack>/.env`

**Environment variable substitution over hardcoded values**
- In `compose.yaml`, always reference secrets via `${VAR_NAME}` — never hardcode values in the file itself.
- Use `docker secret` (Swarm mode) or external secret managers (Vault, Infisical) for production-grade secret handling.

**Secret scanning**
- Use `grep -rE '(PASSWORD|SECRET|TOKEN|API_KEY|PRIVATE_KEY)\s*=\s*[^$]'` to detect hardcoded secrets in compose files.
- Consider adding a pre-commit hook that runs this scan before git commits.

### Synology DSM-Specific Considerations

**DSM user mapping**
- Synology uses UID 1026 for the first non-admin user by default. Check with `id <username>` in DSM terminal.
- For containers writing to NAS shared folders, map the container user to the NAS UID/GID to avoid permission issues:
  ```yaml
  user: "1026:100"  # 100 is the 'users' group GID on Synology
  ```

**Synology Firewall rules**
- DSM has a built-in firewall (Control Panel → Security → Firewall). Rules apply per network interface.
- For Docker containers, the NAS firewall does NOT filter inter-container traffic — only traffic entering/leaving the NAS host.
- To restrict which Docker host ports are publicly accessible, either:
  1. Bind host ports to `127.0.0.1` for containers only accessible via reverse proxy: `127.0.0.1:8080:80`
  2. Use DSM Firewall to block external access to specific ports.
- Recommended: publish only ports 80/443 externally (to Traefik/HAProxy). All other services bind to `127.0.0.1` or use a private VLAN.

**Synology reverse proxy**
- DSM has a built-in reverse proxy (Application Portal). Do not use it alongside Traefik for the same ports — pick one.
- Prefer external reverse proxy (Traefik stack) for flexibility with Dockge stacks.

**Package manager conflicts**
- Avoid installing Docker via Synology Package Center AND running the Dockge stack simultaneously — they share the Docker daemon but have separate management UIs, which can cause confusion about container ownership.

### Logging and Auditability

- Use centralized logging via Loki + Grafana or a syslog forwarder. Configure in compose:
  ```yaml
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"
  ```
- For auditability of admin actions, enable DSM audit logs (Control Panel → Log Center).
- Monitor Docker events via Dozzle or `docker events` for unexpected container restarts.

## When to Apply This Skill

- Reviewing a `compose.yaml` for security issues
- Advising on how to handle credentials for a new stack
- Configuring network isolation between stacks
- Setting up Synology firewall rules for Docker services
- Hardening a specific container type (database, web server, VPN, media server)
- Responding to a suspected container compromise
- Preparing for a homelab security audit

## Key Reference Commands

```bash
# Check current container privilege levels
docker inspect --format='{{.Name}} privileged={{.HostConfig.Privileged}} user={{.Config.User}}' $(docker ps -q)

# Find containers with docker socket mounted
docker inspect $(docker ps -q) | grep -A2 'docker.sock'

# List all published ports across containers
docker ps --format '{{.Names}}: {{.Ports}}'

# Check image layers for secrets (requires dive or docker history)
docker history --no-trunc <image>

# Audit file permissions on stack directories
find /volume1/docker/dockge/stacks -name '.env' -exec ls -la {} \;
```
