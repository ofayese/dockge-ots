# github-desktop

GitHub Desktop running inside a KasmVNC container on Synology NAS, managed by Dockge.
Based on the [mariushosting installation guide](https://mariushosting.com/how-to-install-github-desktop-on-your-synology-nas/).

## Service

| Container | Host Port | Purpose |
|---|---|---|
| `Github-Desktop` | `3405` → `3001` | KasmVNC HTTPS browser UI |

Access via browser: `https://<nas-ip>:3405` or through the Synology Reverse Proxy at
`https://githubdesktop.<yourname>.synology.me`

---

## Quick Start

### 1. Create host directories

Run this on the Synology (SSH or via Task Scheduler as root):

```bash
mkdir -p /volume1/docker/dockge/stacks/github-desktop/config
mkdir -p /volume1/docker/dockge/stacks/github-desktop/data
chown -R 1026:100 /volume1/docker/dockge/stacks/github-desktop
```

> Replace `1026:100` with your own PUID:PGID (see [how to find yours](https://mariushosting.com/synology-find-user-id-and-group-id/)).

### 2. Configure environment

```bash
cp .env.example .env
nano .env   # Set PASSWORD, confirm PUID/PGID/TZ
```

Key values to set:

| Variable | Default | Notes |
|---|---|---|
| `PUID` | `1026` | Your Synology user ID |
| `PGID` | `100` | Your Synology group ID (usually `users = 100`) |
| `TZ` | `America/New_York` | [IANA timezone string](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) |
| `CUSTOM_USER` | `admin` | Login username for KasmVNC web UI |
| `PASSWORD` | *(required)* | Login password — no special characters |
| `TITLE` | `Github-Desktop` | Browser tab title |
| `HOST_PORT` | `3405` | Host-side port (reverse proxy destination) |

### 3. Deploy

```bash
docker compose up -d
# or via Dockge UI
```

### 4. Access

Open `https://<nas-ip>:3405` in your browser, sign in with `CUSTOM_USER` / `PASSWORD`,
then authenticate with your GitHub account inside the app.

---

## Synology Reverse Proxy Setup

In **Control Panel → Login Portal → Advanced → Reverse Proxy**, create a new rule:

| Field | Value |
|---|---|
| Name | `Github-Desktop` |
| Source Protocol | HTTPS |
| Source Hostname | `githubdesktop.<yourname>.synology.me` |
| Source Port | `443` |
| Enable HSTS | ✅ |
| Destination Protocol | HTTPS |
| Destination Hostname | `localhost` |
| Destination Port | `3405` |

Under **Custom Header → Create → WebSocket**, add the WebSocket headers and click Save.

Enable HTTP/2: **Control Panel → Network → Connectivity → Enable HTTP/2**.
Enable HTTP Compression: **Control Panel → Security → Advanced → Enable HTTP Compression**.

---

## Volume Layout

```
/volume1/docker/dockge/stacks/github-desktop/
├── compose.yaml
├── .env                  # live secrets (git-ignored)
├── .env.example          # template committed to git
├── .gitignore
├── README.md
├── config/               # linuxserver /config — all app state, credentials, settings
└── data/                 # optional: bind-mount for git repositories
```

The `data/` directory is not mounted by default. To persist git repositories outside the
container, uncomment the second `volumes` entry in `compose.yaml` and re-deploy.

---

## Health & Monitoring

The healthcheck probes KasmVNC's internal HTTP listener on port `3000` every 30 seconds
(90-second grace period on startup, which is needed because the ~4 GB image initialises slowly).

Watchtower monitors this container automatically via the
`com.centurylinklabs.watchtower.enable=true` label.

---

## Rollback

```bash
git checkout -- github-desktop/compose.yaml
docker compose -f github-desktop/compose.yaml up -d
```

---

## Optional: GPU / Hardware Acceleration

This container is CPU-rendered (KasmVNC does not expose VAAPI/DRI by default).
If you want hardware acceleration for Electron rendering on a NAS with an Intel iGPU,
add the following to the service definition:

```yaml
    devices:
      - /dev/dri:/dev/dri
    group_add:
      - "video"        # GID varies — check with: getent group video
```

> This is experimental. Synology DSM must have GPU passthrough available and the
> `video` group GID confirmed on your system.

---

## Notes

- **Image size**: ~4 GB — allow several minutes on first pull.
- **Seccomp**: `seccomp:unconfined` is required; Electron/Chromium's sandboxing fails
  without it. This is a known upstream requirement for all linuxserver GUI containers.
- **Password characters**: avoid `!`, `@`, `#`, `$`, `%` and other shell-special characters
  in `PASSWORD` — they can break the linuxserver entrypoint.
- **Port conflict**: if `3405` is already in use, change `HOST_PORT` in `.env` and update
  the Synology Reverse Proxy destination port accordingly.
- **Pinning the image**: `latest` is used here for convenience; for production stability,
  replace with a pinned digest e.g. `ghcr.io/linuxserver/github-desktop:3.5.6`.

---

## Alignment With Repo Conventions

| Convention | This Stack |
|---|---|
| Filename | `compose.yaml` |
| `mem_limit` / `cpu_shares` | ✅ `2g` / `768` |
| `logging` (json-file 10m/3) | ✅ |
| `restart: on-failure:5` | ✅ |
| `security_opt: no-new-privileges:true` | ✅ (+ seccomp:unconfined required by Electron) |
| `healthcheck` | ✅ 30s interval, 90s start_period |
| Watchtower label | ✅ |
| `TZ` / `PUID` / `PGID` via `.env` | ✅ |
| Volume path under `/volume1/docker/dockge/stacks/` | ✅ |
| `bridge` external network | ✅ |
| `.env.example` + `.gitignore` | ✅ |
