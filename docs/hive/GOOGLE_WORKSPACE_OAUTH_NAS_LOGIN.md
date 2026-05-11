# Google Workspace OAuth — NAS Login Guide

> **Audience:** Operator deploying Google Workspace identity login for Synology DSM.
> **Goal:** Use a Google Workspace account to authenticate into DSM as a NAS system user.

**Operator checklist (certs → Traefik → this doc):** [`docs/hive/CERT_REISSUE_TRAEFIK_OAUTH_RUNBOOK.md`](CERT_REISSUE_TRAEFIK_OAUTH_RUNBOOK.md) — Part **C** mirrors **Step 1** below with dual-TLD origin/redirect notes.

---

## Architecture choice

| Path | What it does | Use for |
|---|---|---|
| **A — DSM SSO Client** | DSM login portal delegates auth to Google OIDC | **NAS system login** ✓ |
| **B — Synology SSO Server** | NAS acts as OIDC/SAML IdP for other apps | App-to-app SSO only |

**Recommendation:** Path A for NAS system login. Path B is for when the NAS itself is the identity provider for other services (not covered here).

---

## Prerequisites

- Google Workspace admin access (to create OAuth client)
- Custom domain with valid TLS cert covering the OAuth hostname
  - This repo's issued certs: `*.otsorundscore.olutechsys.com` / `*.otsorundscore.olutech.systems`, `*.olutechsys.com`, `*.olutech.systems`
  - Recommended hostname: `nas.otsorundscore.olutechsys.com` → `10.0.1.15`
- DSM 7.x with HTTPS enabled on Login Portal
- DSM user accounts pre-created with email addresses matching Google Workspace

---

## DNS and TLS alignment rules

These four things **must agree** — mismatches cause `origin_mismatch` or `redirect_uri_mismatch`:

| Item | Must match |
|---|---|
| Google Authorized domains | `olutechsys.com` (add **`olutech.systems`** if you use that hostname on DSM) |
| OAuth Client JavaScript Origins | Exact `scheme://host` for each browser URL you will use (see **Step 1**) |
| OAuth Client Redirect URIs | Exact callback per origin, e.g. `https://nas.otsorundscore.olutechsys.com/__ssolib/oauth/callback` |
| DSM Login Portal HTTPS hostname | Must equal the host in Origins (e.g. `nas.otsorundscore.olutechsys.com`) |
| TLS cert SAN | Wildcard **`*.otsorundscore.olutechsys.com`** / **`*.otsorundscore.olutech.systems`** when both issued on the Traefik PEM (see runbook) |

**Origin rules (Google enforces strictly):**
- Scheme + host only — no paths, no wildcards, no trailing slash
- Non-standard ports must be included: `https://example.com:8443`
- `http://` origins are rejected for production

---

## Step 1 — Google Auth Platform setup

1. Go to [console.cloud.google.com](https://console.cloud.google.com) → **APIs & Services → OAuth consent screen**
   - User Type: **Internal** (Google Workspace only — no external users)
   - App name: `Olutech NAS`
   - Authorized domains: add **`olutechsys.com`**; add **`olutech.systems`** if any OAuth hostname or user email uses that domain
   - Save

2. **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID**
   - Application type: **Web application**
   - Name: `OTS NAS DSM SSO`
   - Authorized JavaScript Origins (one line per **exact** browser host you will use; no path, no trailing slash):
     ```
     https://nas.otsorundscore.olutechsys.com
     ```
     If DSM Login Portal is also reachable as **`nas.otsorundscore.olutech.systems`**, add:
     ```
     https://nas.otsorundscore.olutech.systems
     ```
   - Authorized Redirect URIs (must pair with each origin above):
     ```
     https://nas.otsorundscore.olutechsys.com/__ssolib/oauth/callback
     https://nas.otsorundscore.olutech.systems/__ssolib/oauth/callback
     ```
     Omit the `.olutech.systems` pair if you will never browse DSM on that hostname.
   - Click **Create** → copy **Client ID** and **Client Secret** immediately

3. Download the JSON credentials file — store offline, never commit to git

---

## Step 2 — DSM SSO Client configuration

1. DSM → **Control Panel → Domain/LDAP → SSO Client**
2. Enable **OpenID Connect SSO**
3. Select profile: **Google Workspace** (or Generic OIDC)
4. Fill in:
   - Client ID: `<from Step 1>`
   - Client Secret: `<from Step 1>`
   - Redirect URI: must match exactly what was registered
5. Save → **Test** button

---

## Step 3 — DSM user account alignment

For SSO to work, a DSM user account must exist with the same email as the Google Workspace account.

```
DSM → Control Panel → User & Group → Create user
  Email: user@olutechsys.com   ← must match Google Workspace email
  Groups: administrators (or appropriate group)
```

On first SSO login, DSM matches the Google identity to the DSM user by email.

---

## Configuration templates

### Origins (copy-paste, adjust hostname)
```
https://nas.otsorundscore.olutechsys.com
https://nas.otsorundscore.olutech.systems
```
(Remove the second line if unused.)

### Redirect URIs (copy-paste, adjust hostname)
```
https://nas.otsorundscore.olutechsys.com/__ssolib/oauth/callback
https://nas.otsorundscore.olutech.systems/__ssolib/oauth/callback
```

### Routing table
| Public URL | Reverse proxy | DSM service |
|---|---|---|
| `https://nas.otsorundscore.olutechsys.com` | Traefik :6443 | DSM HTTPS :5001 |

---

## Validation checklist

- [ ] TLS cert SAN covers the DSM hostname (wildcards `*.otsorundscore.olutechsys.com` and `*.otsorundscore.olutech.systems` cover `nas.otsorundscore.*` when both are on the PEM)
- [ ] Every browser URL you test matches a registered **Origin** exactly (no trailing slash, no path)
- [ ] Redirect URI exactly matches each origin, including `/__ssolib/oauth/callback`
- [ ] DSM Login Portal HTTPS is enabled and accessible at the OAuth hostname
- [ ] Test DSM user exists with matching Google Workspace email address
- [ ] Tested SSO login in a private/incognito browser window
- [ ] Verified local admin account still works after SSO is enabled (rollback path)

---

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `origin_mismatch` | Browser URL doesn't match registered origin | Add the exact `scheme://host:port` to Origins |
| `redirect_uri_mismatch` | DSM sends a different callback URL than registered | Copy exact URI from DSM SSO Client config |
| `NET::ERR_CERT_AUTHORITY_INVALID` | DSM serving self-signed cert on the OAuth hostname | Issue cert for `nas.otsorundscore.olutechsys.com` via acme-sh |
| `Client sent HTTP request to HTTPS server` | Reverse proxy sending HTTP to DSM HTTPS backend | Set proxy destination to `https://` |
| `400 Bad Request` from DSM | Same HTTP/HTTPS mismatch at proxy layer | Verify Traefik backend uses `https://` for DSM |

---

## Client secret rotation

1. Google Cloud Console → OAuth client → **Edit → Reset Client Secret**
2. DSM → SSO Client → update **Client Secret** → Save
3. Test immediately with a private browser window
4. If broken: revert to old secret while debugging

## Rollback

DSM → SSO Client → **Disable** → Save. Log in with local admin account.  
The local admin account always works regardless of SSO state.

---

## Path B — Synology SSO Server (app-level SSO, not NAS login)

For when the NAS acts as identity provider for other services:

1. **Package Center** → install **SSO Server**
2. SSO Server → **General Settings** → set server URL and **Account Type** **`Domain/LDAP/local`** so DSM/local NAS accounts resolve consistently when tokens carry DSM-aligned identifiers (Path A Google login on DSM remains separate).
3. SSO Server → **Service** → enable OIDC
4. SSO Server → **Application** → Add → OIDC
   - Application name and **Redirect URI** — must match **character-for-character** what each client sends (`redirect_uri` exact match avoids **`redirect_uri_mismatch`**; mind trailing slashes, scheme, port, and path).
   - **Scopes** on clients (PSU, Open WebUI, Portainer, etc.): request **`openid profile email groups`** when you need profile + email + DSM **`groups`** in tokens for RBAC/team mapping.
   - **Username claim:** configure consuming apps to prefer **`preferred_username`** when the IdP emits it; otherwise fall back to **`sub`** (stable subject identifier).
   - Note the App ID and App Secret
5. Copy App ID + Secret + Well-known URL into the consuming app

This does **not** replace NAS system login — it enables downstream apps to delegate to the NAS as their IdP.

---

*See also: [docs/hive/CERT_REISSUE_TRAEFIK_OAUTH_RUNBOOK.md](CERT_REISSUE_TRAEFIK_OAUTH_RUNBOOK.md) | [docs/hive/NAS_DEPLOYMENT.md](NAS_DEPLOYMENT.md) | [docs/hive/SERVICE_MAP.md](SERVICE_MAP.md)*
