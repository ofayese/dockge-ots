# traefik-ots — Traefik v3 (OTS NAS)

Traefik v3 runs on the **OTS** NAS and routes HTTPS for **`*.otsorundscore.olutechsys.com`** and **`*.otsorundscore.olutech.systems`**. It discovers backend services from Docker labels and terminates TLS using a **pre-issued** wildcard certificate from the `acme-sh` stack (`otsorundscore/`), loaded via `config/tls.yaml`.

## Ports

- **Published:** `TRAEFIK_HTTP_PUBLISH` → container `:80`, `TRAEFIK_HTTPS_PUBLISH` → container `:443`, `TRAEFIK_DASHBOARD_PORT` (default `9080`) → container `:8080` (`/ping`, optional `/dashboard/`).
- **Dashboard toggle name is exact:** set `TRAEFIK_DASHBOARD=true` (uppercase key). `traefik_dashboard=true` is ignored by Compose interpolation.
- **LAN example:** `http://10.0.1.15:9080/ping` for host-side liveness.
- **In-container check:** `docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping`, or `docker exec traefik-ots traefik healthcheck --ping` (no `wget` required). On DSM, if you see **`permission denied` … `docker.sock`**, run the same command with **`sudo`** (only root / docker group may use the socket), or add your user to the **`docker`** group and start a new SSH session.
- **`docker exec … bash` fails:** The image ships **BusyBox `/bin/sh` only** — there is **no `bash`**. Use `docker exec -it traefik-ots sh`, or run the `traefik` / `wget` commands above directly (Synology “Terminal” defaults to `bash`; pick **`sh`** or override the command).

## TLS sources

1. **Default (production):** `acme-sh` issues host-named wildcards via **Cloudflare DNS-01** and installs PEMs under `${ACME_CERT_ROOT}/otsorundscore/`. Traefik mounts them read-only at `/certs/otsorundscore`. **Internal split-horizon DNS is not involved** in issuance or renewal.

2. **Optional:** Traefik also exposes **`certificatesResolvers.cloudflare`** (Cloudflare DNS-01, `CF_DNS_API_TOKEN`, `ACME_EMAIL`, state in `${STACK_ROOT}/traefik-ots/data/acme.json`). Use only on routers that set `traefik.http.routers.<n>.tls.certresolver=cloudflare`.

### Log messages (usually harmless)

- **`Failed to inspect container ... No such container`** — The Docker provider still references a container ID that was **removed or recreated** (new ID). Traefik drops it on the next refresh; **restart Traefik** if it repeats after a large redeploy. Not a routing failure by itself.
- **`Error checking new version` / `update.traefik.io` ... timeout** — Built-in **version check** hitting the public internet; common when NAS DNS or egress is restricted. This repo sets **`--global.checkNewVersion=false`** in `compose.yaml` so Traefik does not call home.

### ACME storage permissions (`acme.json`)

Traefik refuses to use the Cloudflare resolver if **`acme.json` is world- or group-readable** (expects mode **600**). After the file first exists on the NAS:

```bash
chmod 600 "${STACK_ROOT}/traefik-ots/data/acme.json"
# recreate container if it logged ERR and skipped the resolver
```

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
