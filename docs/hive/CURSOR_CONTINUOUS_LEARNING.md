# Cursor continuous learning (optional)

This repo ships a **project-local** stop-hook script under **`.cursor/hooks/`** so teammates can copy it into **`~/.cursor/hooks/`** (user scope) without symlinking from the repo (see **`AGENTS.md`** — no symlinks from `~/.cursor` into the git tree).

## Install (user scope)

1. Copy **`.cursor/hooks/continuous-learning-evaluate-session.sh`** → **`~/.cursor/hooks/`** and **`chmod +x`**.
2. Merge into **`~/.cursor/hooks.json`** (cwd for commands is **`~/.cursor`**):

```json
{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": "hooks/continuous-learning-evaluate-session.sh",
        "timeout": 60
      }
    ]
  }
}
```

If **`stop`** already exists, **append** this object to the array.

3. Treat files under **`~/.cursor/skills/learned/`** as **drafts** until a human promotes them into **`AGENTS.md`** or a thin rule.

## Dockge-focused draft content

After sessions touching **ACME**, **DSM bridges**, or **image digest pins**, the script appends a short note including:

- Digest verification: **never** reuse a `sha256:` from another Docker Hub namespace without **`docker manifest inspect`** or pull+inspect on the **pinned** reference.
- **synology-api-bridge:** no generic **`/dsm/proxy`** — allowlisted **`api`/`method`/`version`** only; **`X-Bridge-Secret`** on non-health routes.

See the personal skill **`continuous-learning`** in your Cursor skills path for **`config.json`** thresholds (`min_session_length`, etc.).
