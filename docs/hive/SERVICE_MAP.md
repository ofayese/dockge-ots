# Olutech Systems — Homelab Service Map

Operator sequence (issue PEMs → HAProxy reload → DSM Google SSO Step 1): [`CERT_REISSUE_TRAEFIK_OAUTH_RUNBOOK.md`](CERT_REISSUE_TRAEFIK_OAUTH_RUNBOOK.md).

## Domains and namespaces

| NAS hostname   | Wildcard (per TLD)                                      | Routes to                 | PEM dir (`/volume1/certs/acme/`) |
| -------------- | ------------------------------------------------------- | ------------------------- | -------------------------------- |
| `otsorundscore` | `*.otsorundscore.olutechsys.com`, `*.otsorundscore.olutech.systems` | otsorundscore.synology.me | `otsorundscore/`                 |
| `misfitsds`     | `*.misfitsds.olutechsys.com`, `*.misfitsds.olutech.systems`         | misfitsds.synology.me     | `misfitsds/`                     |

Root domain `olutechsys.com` is reserved for public-facing or global services (www, api, vpn). **Host-named** wildcard CNAMEs (e.g. `*.otsorundscore.olutechsys.com` → `otsorundscore.synology.me`) are **DNS-only** (grey cloud in Cloudflare) — Cloudflare does not proxy wildcard CNAMEs to third-party DDNS hostnames on typical plans.

## OTS NAS services (`*.otsorundscore.*`)

DDNS: otsorundscore.synology.me  
Edge route: `stacks/_haproxy/` host map + backend (OTS NAS)  
Cert bundle source: `/volume1/certs/acme/otsorundscore/` (SANs: `otsorundscore.{olutechsys,olutech.systems}` + `*.otsorundscore.{olutechsys,olutech.systems}`, RSA 2048 via `acme-sh`)

| Service        | URL                                           | HAProxy backend | Upstream port |
| -------------- | --------------------------------------------- | --------------- | ------------- |
| PSU (NOC)      | https://psu.otsorundscore.olutechsys.com      | psu-be          | 5055          |
| Drive          | https://otsdrv.otsorundscore.olutechsys.com   | otsdrv      | 6690          |
| File Station   | https://otsfst.otsorundscore.olutechsys.com   | otsfst      | 7000          |
| Calendar       | https://otscal.otsorundscore.olutechsys.com   | otscal      | 5000          |
| Contacts       | https://otscnt.otsorundscore.olutechsys.com   | otscnt      | 5002          |
| Photos         | https://otspht.otsorundscore.olutechsys.com   | otspht      | 5003          |
| SSO            | https://otssso.otsorundscore.olutechsys.com   | otssso      | 5001          |
| VMM            | https://otsvmm.otsorundscore.olutechsys.com   | otsvmm      | 8000          |
| Remotely       | https://remotely.otsorundscore.olutechsys.com | remotely    | 5000          |

## MFT NAS services (`*.misfitsds.*`)

DDNS: misfitsds.synology.me  
Edge route: host-level HAProxy on MFT NAS  
Cert bundle source: `/volume1/certs/acme/misfitsds/` (SANs: `misfitsds.{olutechsys,olutech.systems}` + `*.misfitsds.{olutechsys,olutech.systems}`, RSA 2048)

| Service      | URL                                         | Router name | Internal port |
| ------------ | ------------------------------------------- | ----------- | ------------- |
| Drive        | https://mftdrv.misfitsds.olutechsys.com     | mftdrv      | 6690          |
| File Station | https://mftfst.misfitsds.olutechsys.com     | mftfst      | 7000          |
| Calendar     | https://mftcal.misfitsds.olutechsys.com     | mftcal      | 5000          |
| Contacts     | https://mftcnt.misfitsds.olutechsys.com     | mftcnt      | 5002          |
| Photos       | https://mftpht.misfitsds.olutechsys.com     | mftpht      | 5003          |

## SSL and certificates

| Cert dir        | Covers                                                                 | Issuer        | Renewed by     |
| --------------- | ---------------------------------------------------------------------- | ------------- | -------------- |
| `wildcard/`     | `*.olutechsys.com`, `*.olutech.systems`                                | Let's Encrypt | acme-sh daemon |
| `otsorundscore/` | `otsorundscore.*` + `*.otsorundscore.*` on `.olutechsys.com` / `.olutech.systems` | Let's Encrypt | acme-sh daemon |
| `misfitsds/`    | `misfitsds.*` + `*.misfitsds.*` on `.olutechsys.com` / `.olutech.systems`          | Let's Encrypt | acme-sh daemon |

HAProxy uses PEM bundles staged from `/volume1/certs/acme/<dir>/`. `acme-sh` renews automatically; after **manual** PEM replace, rebuild bundles and reload HAProxy.

## Design principles

- Root domain reserved for public-facing or global services
- **Per-NAS hostname** (`otsorundscore`, `misfitsds`) drives TLS SANs and public service names — not a shared `ots.` / `mft.` label segment
- Wildcard CNAMEs per host minimise DNS maintenance — add services without per-record DNS when covered by the wildcard SAN
- `acme-sh` owns the cert lifecycle; HAProxy consumes staged PEM bundles
- DNS-01 challenge requires no open inbound ports during issuance
- `lab` and `dev` namespaces are reserved in DNS but commented out until a use case is confirmed

## Adding a new service

1. Publish the service on a dedicated host port in its stack `compose.yaml`.
2. Add hostnames to `stacks/_haproxy/maps/host.map` and backend/server in `stacks/_haproxy/haproxy.cfg`.
3. Confirm the hostname is covered by the NAS wildcard cert (or add SANs / separate order in `acme-sh`).
4. Update this table with the new service URL and backend port.

## Cloudflare proxy note

Wildcard CNAMEs to third-party DDNS hostnames must remain **DNS-only** (grey cloud). HAProxy handles TLS termination; the Synology DDNS hostname resolves to the NAS public IP.
