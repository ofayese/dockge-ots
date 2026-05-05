# traefik-mft — reverse proxy (Misfits NAS)

## Overview

Traefik v3 runs on the **MFT** (Misfits) NAS and routes HTTPS for `*.mft.olutechsys.com`. Default TLS uses **`acme-sh`** PEMs (`mft-sub/`) via `config/tls.yaml`. A **`certificatesResolvers.cloudflare`** resolver (DNS-01, same token model as acme-sh) is also configured; internal split-horizon DNS is **not** used for ACME.

## Image pinning

`compose.yaml` uses **`traefik:v3`** (floating major). For production, pin to a specific semver (for example **`traefik:v3.3.4`**) and bump deliberately. Tags: [Docker Hub — traefik](https://hub.docker.com/_/traefik/tags).

## Cert sources

See [traefik-ots README](../traefik-ots/README.md#cert-sources-two-layers) — same pattern: file certs from `acme-sh`, optional Traefik resolver state under `${STACK_ROOT}/traefik-mft/data/acme.json`.

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
| `${STACK_ROOT}/traefik-mft/data`                 | `/data`          | Traefik built-in ACME `acme.json` (gitignored)   |
| `${ACME_CERT_ROOT:-/volume1/certs/acme}/mft-sub` | `/certs/mft-sub` | PEM bundle from `acme-sh` (read-only)            |

Copy `.env.example` to `.env` and set `STACK_ROOT`, `CF_Token`, **`ACME_EMAIL`** (override the compose default placeholder), and tuning variables as needed.

## Dashboard

The API dashboard is **disabled** by default (`TRAEFIK_DASHBOARD=false`). For short-lived debugging, set `TRAEFIK_DASHBOARD=true` in `.env`, redeploy, and reach the dashboard on `${TRAEFIK_DASHBOARD_PORT:-8080}`. Turn it off again afterward.

## Healthcheck

Type **A**: HTTP `GET` on `http://127.0.0.1:8080/ping` (Traefik ping entrypoint on port 8080). Requires `--ping=true` and the internal `traefik` entrypoint (see `compose.yaml`).

## Network

The stack defines a bridge network named **`traefik-mft`**. Other stacks join it with `external: true` and `name: traefik-mft` so Traefik can reach their containers. Deploy **traefik-mft** before dependent services so the network exists.
