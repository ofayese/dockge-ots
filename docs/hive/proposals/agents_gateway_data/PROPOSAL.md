# PROPOSAL — agents_gateway_data

**Owner:** operator · **2026-04-30**

## Summary

Document and baseline the **MCP gateway** stack: external bridge network, `restart: on-failure:5`, `security_opt`, logging, pinned gateway image, explicit `docker.sock` security comments.

## Rollback

Revert `stacks/agents_gateway_data/compose.yaml` and `duckduckgo/compose.yaml` to prior minimal manifests if the gateway version pin blocks pulls.
