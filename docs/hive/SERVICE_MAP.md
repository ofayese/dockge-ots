# Olutech Systems — Homelab Service Map

## Domains and namespaces

| Namespace | Wildcard               | Routes to                 | Cert     |
| --------- | ---------------------- | ------------------------- | -------- |
| ots       | `*.ots.olutechsys.com`  | otsorundscore.synology.me | ots-sub/ |
| mft       | `*.mft.olutechsys.com`  | misfitsds.synology.me     | mft-sub/ |

Root domain `olutechsys.com` is reserved for public-facing or global services (www, api, vpn). Namespace CNAMEs are DNS-only (grey cloud in Cloudflare) — Cloudflare does not proxy wildcard CNAMEs to third-party DDNS hostnames.

## OTS NAS services (`*.ots.olutechsys.com`)

DDNS: otsorundscore.synology.me  
Traefik stack: `stacks/traefik-ots/`  
Cert: `/volume1/certs/acme/ots-sub/` (`*.ots.olutechsys.com`, RSA 2048)

| Service      | URL                                   | Router name | Internal port |
| ------------ | ------------------------------------- | ----------- | ------------- |
| Drive        | https://otsdrv.ots.olutechsys.com     | otsdrv      | 6690          |
| File Station | https://otsfst.ots.olutechsys.com     | otsfst      | 7000          |
| Calendar     | https://otscal.ots.olutechsys.com     | otscal      | 5000          |
| Contacts     | https://otscnt.ots.olutechsys.com     | otscnt      | 5002          |
| Photos       | https://otspht.ots.olutechsys.com     | otspht      | 5003          |
| SSO          | https://otssso.ots.olutechsys.com     | otssso      | 5001          |
| VMM          | https://otsvmm.ots.olutechsys.com     | otsvmm      | 8000          |

## MFT NAS services (`*.mft.olutechsys.com`)

DDNS: misfitsds.synology.me  
Traefik stack: `stacks/traefik-mft/`  
Cert: `/volume1/certs/acme/mft-sub/` (`*.mft.olutechsys.com`, RSA 2048)

| Service      | URL                                   | Router name | Internal port |
| ------------ | ------------------------------------- | ----------- | ------------- |
| Drive        | https://mftdrv.mft.olutechsys.com     | mftdrv      | 6690          |
| File Station | https://mftfst.mft.olutechsys.com     | mftfst      | 7000          |
| Calendar     | https://mftcal.mft.olutechsys.com     | mftcal      | 5000          |
| Contacts     | https://mftcnt.mft.olutechsys.com     | mftcnt      | 5002          |
| Photos       | https://mftpht.mft.olutechsys.com     | mftpht      | 5003          |

## SSL and certificates

| Cert dir           | Covers                               | Issuer        | Renewed by        |
| ------------------ | ------------------------------------ | ------------- | ----------------- |
| wildcard/          | `*.olutechsys.com`, `*.olutech.systems` | Let's Encrypt | acme-sh daemon    |
| ots-sub/           | `*.ots.olutechsys.com`               | Let's Encrypt | acme-sh daemon    |
| mft-sub/           | `*.mft.olutechsys.com`               | Let's Encrypt | acme-sh daemon    |
| otsorundscore-sub/ | `otsorundscore.{olutechsys,olutech.systems}` + `*.otsorundscore.*` + optional `*.ots` / `*.mft` SANs | Let's Encrypt | acme-sh daemon    |
| misfitsds-sub/     | `misfitsds.{olutechsys,olutech.systems}` + `*.misfitsds.*` + optional `*.ots` / `*.mft` SANs | Let's Encrypt | acme-sh daemon    |

Traefik reads certs directly from `/volume1/certs/acme/<dir>/` via bind-mount. `acme-sh` renews automatically; Traefik picks up renewed PEMs on the next configuration reload (no Traefik restart needed).

## Design principles

- Root domain reserved for public-facing or global services
- Namespaces (`ots`, `mft`) isolate service clusters per NAS
- Wildcard CNAMEs minimise DNS maintenance — add services without touching DNS
- `acme-sh` owns the cert lifecycle; Traefik is cert-consumer only
- DNS-01 challenge requires no open inbound ports during issuance
- `lab` and `dev` namespaces are reserved in DNS but commented out until a use case is confirmed

## Adding a new service

1. Add Traefik labels to the service's `compose.yaml` (see `stacks/traefik-ots/README.md` or `stacks/traefik-mft/README.md`).
2. No DNS change needed — wildcard CNAME covers all subdomains.
3. No cert change needed — wildcard cert covers all subdomains.
4. Update this table with the new service URL and port.

## Cloudflare proxy note

`*.ots` and `*.mft` CNAME records must remain DNS-only (grey cloud). Cloudflare cannot proxy wildcard CNAMEs to third-party DDNS hostnames on standard plans. Traefik handles TLS termination directly; the Synology DDNS hostname resolves to the NAS public IP.
