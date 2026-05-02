# traefik-mft — reverse proxy (Misfits NAS)

## Overview

Traefik v3 runs on the **MFT** (Misfits) NAS and routes HTTPS for `*.mft.olutechsys.com`. It discovers backend services from Docker labels and terminates TLS using a **pre-issued** wildcard certificate from the `acme-sh` stack (`mft-sub/`).

## Cert source

Certificates are **not** requested by Traefik in normal operation. `acme-sh` issues `*.mft.olutechsys.com` and writes PEMs under `/volume1/certs/acme/mft-sub/`. This stack bind-mounts that directory **read-only** at `/certs/mft-sub` and loads paths via `config/tls.yaml`. When `acme-sh` renews, Traefik picks up updated files on the next configuration reload.

## Adding a new service

Expose a container through Traefik by attaching labels and joining the external `traefik-mft` network:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<name>.rule=Host(`<subdomain>.mft.olutechsys.com`)"
  - "traefik.http.routers.<name>.entrypoints=websecure"
  - "traefik.http.routers.<name>.tls=true"
  - "traefik.http.services.<name>.loadbalancer.server.port=<port>"
networks:
  - traefik-mft
```

```yaml
networks:
  traefik-mft:
    external: true
    name: traefik-mft
```

Replace `<name>` with a short unique router and service identifier (for example `mftdrv`), `<subdomain>` with the hostname label (for example `mftdrv`), and `<port>` with the container’s listening port.

## Volumes

| Host path                                        | Mount            | Purpose                                          |
| ------------------------------------------------ | ---------------- | ------------------------------------------------ |
| `${STACK_ROOT}/traefik-mft/config`               | `/etc/traefik`   | Static config (`tls.yaml`, optional extra files) |
| `${ACME_CERT_ROOT:-/volume1/certs/acme}/mft-sub` | `/certs/mft-sub` | PEM bundle from `acme-sh` (read-only)            |

Copy `.env.example` to `.env` and set `STACK_ROOT`, `CF_Token` (optional if Traefik never uses its own ACME), and tuning variables as needed.

## Dashboard

The API dashboard is **disabled** by default (`TRAEFIK_DASHBOARD=false`). For short-lived debugging, set `TRAEFIK_DASHBOARD=true` in `.env`, redeploy, and reach the dashboard on `${TRAEFIK_DASHBOARD_PORT:-8080}`. Turn it off again afterward.

## Healthcheck

Type **A**: HTTP `GET` on `http://127.0.0.1:8080/ping` (Traefik ping entrypoint on port 8080). Requires `--ping=true` and the internal `traefik` entrypoint (see `compose.yaml`).

## Network

The stack defines a bridge network named **`traefik-mft`**. Other stacks join it with `external: true` and `name: traefik-mft` so Traefik can reach their containers. Deploy **traefik-mft** before dependent services so the network exists.
