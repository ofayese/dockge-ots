# portainer

Container management UI (server) + agent for daemon access on the host.

## Services

- **portainer** (9000 HTTP, 9443 HTTPS) — UI; mounts host `docker.sock` and `/volume1/​docker/portainer` for state
- **portainer_agent** (9001) — daemon-side agent; runs with `cap_drop: ALL` and only `cap_add: NET_RAW`; mounts `/` as `/host` for full filesystem visibility

## Bootstrap (bind mounts)

`compose.yaml` mounts **`${PORTAINER_DATA_ROOT}`** → `/data` and **`${PORTAINER_CERT_ROOT}`** → `/certs` (production NAS defaults are **`/volume1/docker/portainer`** and **`/volume1/docker/portainer/certs`** — see **`stacks/portainer/.env.example`**). If either host path is missing, the daemon returns **Bind mount failed: … does not exist**. Create dirs and install agent TLS material first.

## TLS certs (agent)

`/volume1/​docker/portainer/certs/` — mount read-only at `/certs`; files must be named **`cert.pem`** and **`key.pem`** (see `compose.yaml`). Issue or copy TLS material separately; do not commit keys to git.

## Health

- portainer: HTTP 200 on `/api/system/status`
- portainer_agent: TCP open on 9001

## Trust posture

`portainer_agent` mounts `/` as `/host` plus `docker.sock` — this is the **highest privilege surface** of any stack. Access is gated by the agent-cluster TLS certs.

## OIDC (Synology SSO Server — Path B)

Use **DSM SSO Server** as the OIDC IdP for **who can open the Portainer UI** — **not** the **OAuth Service** package (Synology API resource authorization).

1. Package Center → **SSO Server** → **General Settings** → **Account Type** **`Domain/LDAP/local`** for DSM/local directory compatibility with NAS-backed identities.
2. Create a separate **OIDC application** for Portainer (do not reuse PSU or Open WebUI clients).
3. Portainer: **Settings → Authentication → OAuth** — choose **Custom** and paste endpoints from Synology’s OIDC discovery document (issuer, authorization, token, userinfo as required by Portainer’s wizard).
4. **Scopes:** request **`openid profile email groups`** when you rely on group claims for teams/RBAC (omit or narrow **`groups`** only if you intentionally do not map DSM groups).
5. **Redirect URL:** use the exact value Portainer shows for your **public** Portainer base URL — strict match against the SSO application registration (scheme/host/port/path + trailing slash rules); mismatches surface as **`redirect_uri_mismatch`** (confirm in UI after enabling OAuth; do not assume a fragment like `#!/auth` unless your edition displays it).
6. **Username / subject mapping:** prefer **`preferred_username`** when available from the IdP; use **`sub`** as the stable fallback identifier if **`preferred_username`** is absent or unsuitable.
7. **Automatic team membership:** to map DSM **`groups`** (or equivalent) to Portainer teams, set **Claim name** to match the claim Synology puts in the token (often **`groups`**) and define regex / static team mappings per [Portainer — OAuth](https://docs.portainer.io/admin/settings/authentication/oauth).

**Risk note:** OAuth/OIDC only gates **UI access**. It does **not** reduce **`docker.sock`** or agent **host `/`** exposure — operators with Portainer access remain highly trusted.

## Rollback

```bash
git checkout -- portainer/compose.yaml
docker compose -f portainer/compose.yaml up -d
```

Portainer DB (settings, registries, endpoints) persists at `/volume1/​docker/portainer`. Loss = re-create endpoints and re-pair the agent.

## History

Compose previously had a malformed `environment: - https://10.0.1.15:9001` entry (no `KEY=value`). Cleaned up; see `docs/hive/proposals/portainer/PROPOSAL.md` Change 1.
