# Removing leaked secrets from Git history

If `.env`, API tokens, or application keys were ever committed, **rotating the live credential is mandatory**; removing the file from the current tree is not enough for a public or widely cloned repo.

## Policy (recommended order)

1. **Rotate** every exposed credential (tokens, DB passwords, SearXNG `secret_key`, HAProxy stats passwords, etc.).
2. **Stop** committing secret material — use `.env.example`, Docker secrets, or operator-managed files under paths listed in `.gitignore`.
3. **Rewrite history** so clones and forks do not retain old blobs (coordinate with all fork owners).

## Tooling

Prefer [`git filter-repo`](https://github.com/newren/git-filter-repo) over `filter-branch`.

Example patterns (adjust paths; **dry-run first**):

```bash
pip install git-filter-repo   # or brew install git-filter-repo
git filter-repo --analyze

# Remove a tracked env file from all commits:
git filter-repo --path grafana-prom/.env --invert-paths

# Or replace file contents historically (advanced):
# see git-filter-repo manual for --replace-text
```

After rewrite: **force-push** all branches and tags you care about, and ask collaborators to re-clone or reset hard to the new default branch.

## When to skip history rewrite

- Repo is private, small team, and you have confidence no clone leaked — still rotate secrets; rewrite is optional risk/cost tradeoff.
- Secrets were only ever on a local branch never pushed — reset branch and rotate anyway.

Document the incident outcome (rotation date + ticket) in your ops log.
