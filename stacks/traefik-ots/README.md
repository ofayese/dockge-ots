# traefik-ots — Traefik v3 (OTS NAS)

Traefik v3 runs on the **OTS** NAS and routes HTTPS for **`*.otsorundscore.olutechsys.com`** and **`*.otsorundscore.olutech.systems`**. It discovers backend services from Docker labels and terminates TLS using a **pre-issued** wildcard certificate from the `acme-sh` stack (`otsorundscore/`), loaded via `config/tls.yaml`.

## Ports

- **Published:** `TRAEFIK_HTTP_PUBLISH` → container `:80`, `TRAEFIK_HTTPS_PUBLISH` → container `:443`, `TRAEFIK_DASHBOARD_PORT` → `:8080` (`/ping`, optional `/dashboard/`).
- **LAN example:** `http://10.0.1.15:8080/ping` for liveness.

## TLS sources

1. **Default (production):** `acme-sh` issues host-named wildcards via **Cloudflare DNS-01** and installs PEMs under `${ACME_CERT_ROOT}/otsorundscore/`. Traefik mounts them read-only at `/certs/otsorundscore`. **Internal split-horizon DNS is not involved** in issuance or renewal.

2. **Optional:** Traefik also exposes **`certificatesResolvers.cloudflare`** (Cloudflare DNS-01, `CF_DNS_API_TOKEN`, `ACME_EMAIL`, state in `${STACK_ROOT}/traefik-ots/data/acme.json`). Use only on routers that set `traefik.http.routers.<n>.tls.certresolver=cloudflare`.

## Adding a service

1. Join the **`traefik-ots`** external network from the service stack.
2. Add labels (example placeholders):

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.<name>.rule=Host(`<subdomain>.otsorundscore.olutechsys.com`)
  - traefik.http.routers.<name>.entrypoints=websecure
  - traefik.http.routers.<name>.tls=true
  - traefik.http.services.<name>.loadbalancer.server.port=<port>
```

3. Deploy; no new public DNS name is required when the hostname matches the wildcard SAN.

## Files

- `compose.yaml` — Traefik service, mounts, healthcheck.
- `config/tls.yaml` — default certificate from `acme-sh` PEM paths.
