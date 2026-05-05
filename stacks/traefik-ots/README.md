# traefik-ots — reverse proxy (OTS NAS)

## Overview

Traefik v3 runs on the **OTS** NAS and routes HTTPS for `*.ots.olutechsys.com`. It discovers backend services from Docker labels and terminates TLS using a **pre-issued** wildcard certificate from the `acme-sh` stack (`ots-sub/`), loaded via `config/tls.yaml`.

## Image pinning

`compose.yaml` uses **`traefik:v3`** (floating major). For production, pin to a specific semver (for example **`traefik:v3.3.4`**) and bump deliberately after reading release notes. Current tags: [Docker Hub — traefik](https://hub.docker.com/_/traefik/tags).

## Cert sources (two layers)

1. **Default (production):** `acme-sh` issues `*.ots.olutechsys.com` via **Cloudflare DNS-01** and installs PEMs under `${ACME_CERT_ROOT}/ots-sub/`. Traefik mounts them read-only at `/certs/ots-sub`. **Internal split-horizon DNS is not involved** in issuance or renewal.

2. **Optional:** Traefik also exposes **`certificatesResolvers.cloudflare`** (Cloudflare DNS-01, `CF_DNS_API_TOKEN`, `ACME_EMAIL`, state in `${STACK_ROOT}/traefik-ots/data/acme.json`). Use only on routers that set `traefik.http.routers.<n>.tls.certresolver=cloudflare`. Wildcards such as `*.ots.olutechsys.com` / `*.mft.olutechsys.com` remain **public-DNS** challenges at Cloudflare—same as acme-sh.

**Renew / reload:** after `acme-sh` renews PEMs, restart Traefik (or reload) so file certs refresh. **Do not delete** `acme-sh` state or PEM dirs as part of Traefik restarts. For built-in resolver activity, check Traefik logs for `acme` / `lego` lines.

## Adding a new service

Expose a container through Traefik by attaching labels and joining the external `traefik-ots` network:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<name>.rule=Host(`<subdomain>.ots.olutechsys.com`)"
  - "traefik.http.routers.<name>.entrypoints=websecure"
  - "traefik.http.routers.<name>.tls=true"
  - "traefik.http.services.<name>.loadbalancer.server.port=<port>"
networks:
  - traefik-ots
```

```yaml
networks:
  traefik-ots:
    external: true
    name: traefik-ots
```

Replace `<name>` with a short unique router and service identifier (for example `otsdrv`), `<subdomain>` with the hostname label (for example `otsdrv`), and `<port>` with the container’s listening port.

## Volumes

| Host path                                        | Mount            | Purpose                                          |
| ------------------------------------------------ | ---------------- | ------------------------------------------------ |
| `${STACK_ROOT}/traefik-ots/config`               | `/etc/traefik`   | Static config (`tls.yaml`, optional extra files) |
| `${STACK_ROOT}/traefik-ots/data`                 | `/data`          | Traefik built-in ACME `acme.json` (gitignored)   |
| `${ACME_CERT_ROOT:-/volume1/certs/acme}/ots-sub` | `/certs/ots-sub` | PEM bundle from `acme-sh` (read-only)            |

Copy `.env.example` to `.env` and set `STACK_ROOT`, `CF_Token`, **`ACME_EMAIL`** (override the compose default `hostmaster@example.com` placeholder for real Let’s Encrypt account contact), and tuning variables as needed.

## Dashboard

The API dashboard is **disabled** by default (`TRAEFIK_DASHBOARD=false`). For short-lived debugging, set `TRAEFIK_DASHBOARD=true` in `.env`, redeploy, and reach the dashboard on `${TRAEFIK_DASHBOARD_PORT:-8080}`. Turn it off again afterward.

## Healthcheck

Type **A**: HTTP `GET` on `http://127.0.0.1:8080/ping` (Traefik ping entrypoint on port 8080). Requires `--ping=true` and the internal `traefik` entrypoint (see `compose.yaml`).

## Network

The stack defines a bridge network named **`traefik-ots`**. Other stacks join it with `external: true` and `name: traefik-ots` so Traefik can reach their containers. Deploy **traefik-ots** before dependent services so the network exists.
