# Hive output directory

Workers write **proposals only** here unless the queen merges after review.

- `proposals/<stack>/` — per-stack patches, rationale, rollback (`INVENTORY.md`, `PROPOSAL.md`, diffs).
- `proposals/_monitoring/`, `proposals/_backups/`, `proposals/_haproxy/` — cross-cutting drafts (require queen consensus before any repo-wide apply).
- `REPORT.md` — final closeout (created at end of hive run).
- `COMPOSE_FILENAMES.md` — stacks that use `docker-compose.yml` / `docker-compose.yaml` instead of `compose.yaml`.

Do not commit live secrets. Use `.env.example` only for documented keys.
