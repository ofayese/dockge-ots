# Compose image pin policy

Production stacks should pin **`image:`** to an explicit **semver tag** or **`@sha256:` digest** so deploys are reproducible and supply-chain drift is visible in diffs.

## Exceptions (do not pin in compose `image:`)

- **Model / artifact tags inside env defaults** (not Docker `image:`), for example **`nomic-embed-text:latest`** in Ollama or rag-stack env — those are upstream model identifiers, not container images. Pin the **runtime image** (`ollama/ollama@sha256:…`) instead.

## Operator re-pin workflow

```bash
docker pull <image>:<tag>
docker image inspect <image>:<tag> --format '{{index .RepoDigests 0}}'
```

Replace the compose `image:` line with the resolved digest (or a semver tag that your change-management accepts).

## Registry notes (2026-05-10)

- **codex-docs** uses **`ghcr.io/codex-team/codex.docs@sha256:…`** (the historical `codexteam/codex.docs` Hub path was not pullable from automation hosts).
- **openresume** pins **`yuihtt/open-resume@sha256:…`** (digest must be re-resolved with `docker pull` + `inspect` on **that** image only). **Cross-namespace digest reuse is invalid supply chain practice** — a digest for `xitanggg/*` or `itsnoted/*` is not interchangeable with `yuihtt/*` unless proven by `docker manifest inspect` (almost never true). Historical: upstream `xitanggg/open-resume` and mirror `itsnoted/open-resume` were used when Hub pulls failed from CI; **superseded** by the `yuihtt` pin dated **2026-05-10**.
