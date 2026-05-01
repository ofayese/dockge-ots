# PROPOSAL — docker-model-runner

**Owner:** operator · **2026-04-30**

## Summary

Add Synology-aligned **logging**, **`restart: on-failure:5`**, **`security_opt`**, **`TZ`**, **`mem_limit`**, and HTTP **healthchecks** for each model-runner service without changing published models/ports.

## Rollback

Restore prior `docker-compose.yml` from git history if GPU memory limits are too tight for your NAS.
