# INVENTORY — docker-model-runner

**Path:** `stacks/docker-model-runner/docker-compose.yml` · **Manual stub** (2026-04-30)

## Services

Three `docker/model-runner` CUDA services on LAN ports `8001`, `8003`, `8011`.

## Volumes

No bind mounts in tracked compose; optional operator paths documented in stack `README.md`.

## Gaps vs baseline

GPU runtime and image size are operator concerns; healthchecks probe `/v1/models` over HTTP inside each container.
