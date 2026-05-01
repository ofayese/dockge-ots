# openresume

Self-hosted resume builder ([Open-Resume](https://github.com/xitanggg/open-resume), Next.js). Stateless — all resume data lives in the user's browser localStorage.

## Service

- **openresume** (8889) — Next.js production build

## Public hostname

`resume.otsorundscore.olutechsys.com` (via HAProxy stretch when ready; resolved via `extra_hosts` today).

## Health

HTTP 200 on `/`.

## Rollback

```bash
git checkout -- openresume/compose.yaml
docker compose -f openresume/compose.yaml up -d
```

## Note

No persistent state on the server side. Container restarts are zero-data-loss; users keep their drafts in the browser.
