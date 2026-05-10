#!/usr/bin/env python3
"""
compose_schema.py — Validate docker-compose v3.9 schema compliance.

Functions:
  - validate_v39_schema: Check compose file against v3.9 spec
  - detect_deprecated_fields: Identify removed/deprecated compose directives
  - detect_invalid_depends_on: Find malformed depends_on structures

Used by: inventory.py (extended) and analyzer reports
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)

# Compose v3.9 known fields (non-exhaustive, covers most common cases)
COMPOSE_V39_TOP_KEYS = {
    'version',
    'services',
    'volumes',
    'networks',
    'secrets',
    'configs',
    'name',  # Compose project name (v2/v3)
    'x-build',
    'x-labels',  # Extension fields are allowed
}

SERVICE_KEYS = {
    'image', 'container_name', 'ports', 'volumes', 'environment',
    'networks', 'depends_on', 'healthcheck', 'logging', 'restart',
    'mem_limit', 'cpu_shares', 'security_opt', 'cap_drop', 'cap_add',
    'labels', 'command', 'entrypoint', 'user', 'group_add',
    'extra_hosts', 'network_mode', 'privileged', 'pid', 'ipc',
    'tmpfs', 'storage_opt', 'sysctls', 'ulimits', 'device_cgroup_rules',
    'secrets', 'configs', 'blkio_config', 'cpu_period', 'cpu_quota',
    'cpuset', 'mem_reservation', 'memswap_limit', 'oom_kill_disable',
    'read_only', 'shm_size', 'stdin_open', 'tty', 'working_dir',
    'profiles', 'build', 'image_pull_policy',
    # Extension fields
    'x-labels'
}

# Deprecated fields that should trigger warnings
DEPRECATED_FIELDS = {
    'cpu_percent': 'Use cpu_shares instead',
    'domainname': 'Use hostname or networks instead',
    'links': 'Use networks and service discovery instead',
    'net': 'Use network_mode instead',
    'expose': 'Use ports with protocol instead',
    'cgroup_parent': 'No direct replacement in v3.9',
}

DEPRECATED_TOP_KEYS = {
    'external_links': 'Use networks instead',
}


def validate_v39_schema(compose: dict[str, Any]) -> list[str]:
    """
    Validate top-level compose structure against v3.9 schema.
    Returns list of validation errors (empty if valid).
    """
    errors: list[str] = []

    if not isinstance(compose, dict):
        errors.append("Compose file must be a YAML dictionary")
        return errors

    # Check version
    version = compose.get('version', '3')
    try:
        parts = str(version).split('.')
        if len(parts) >= 2:
            v_major, v_minor = int(parts[0]), int(parts[1])
        else:
            v_major = int(parts[0])
            v_minor = 0
        if (v_major, v_minor) > (3, 9):
            errors.append(f"Unsupported version {version} (expected 3.x)")
    except (ValueError, AttributeError):
        errors.append(f"Invalid version format: {version}")

    # Check top-level keys (x-* extensions are valid; do not skip validation for other typos)
    unknown_keys = set(compose.keys()) - COMPOSE_V39_TOP_KEYS
    invalid_unknown = {k for k in unknown_keys if not k.startswith("x-")}
    if invalid_unknown:
        errors.append(f"Unknown top-level keys: {', '.join(sorted(invalid_unknown))}")

    # Validate services exist
    services = compose.get('services', {})
    if not isinstance(services, dict):
        errors.append("'services' must be a dictionary")
    else:
        for svc_name, svc_def in services.items():
            if not isinstance(svc_def, dict):
                errors.append(f"Service '{svc_name}' must be a dictionary")
                continue
            svc_errors = _validate_service(svc_name, svc_def)
            errors.extend(svc_errors)

    return errors


def _validate_service(name: str, service: dict[str, Any]) -> list[str]:
    """Validate a single service definition."""
    errors: list[str] = []

    # Unknown service keys are intentionally not errors — Compose evolves and
    # stacks use many optional keys (deploy, env_file, cgroupns, …).

    # Check for deprecated keys
    for deprecated, note in DEPRECATED_FIELDS.items():
        if deprecated in service:
            errors.append(f"Service '{name}': deprecated field '{deprecated}' ({note})")

    # Validate image or build
    if 'image' not in service and 'build' not in service:
        errors.append(f"Service '{name}': missing 'image' or 'build'")

    # Validate depends_on structure
    depends_on_errors = detect_invalid_depends_on(name, service.get('depends_on'))
    errors.extend(depends_on_errors)

    # Validate networks
    nets = service.get('networks', [])
    if isinstance(nets, list):
        for net in nets:
            if not isinstance(net, (str, dict)):
                errors.append(f"Service '{name}': networks must be strings or dicts")
    elif not isinstance(nets, dict):
        errors.append(f"Service '{name}': networks must be a list or dict")

    return errors


def detect_deprecated_fields(compose: dict[str, Any]) -> list[str]:
    """
    Scan entire compose file for deprecated fields.
    Returns list of deprecation warnings.
    """
    warnings: list[str] = []

    # Top-level deprecated keys
    for deprecated, note in DEPRECATED_TOP_KEYS.items():
        if deprecated in compose:
            warnings.append(f"Top-level '{deprecated}' is deprecated ({note})")

    # Service-level deprecated keys
    services = compose.get('services', {}) or {}
    if isinstance(services, dict):
        for svc_name, svc_def in services.items():
            if isinstance(svc_def, dict):
                for deprecated, note in DEPRECATED_FIELDS.items():
                    if deprecated in svc_def:
                        warnings.append(
                            f"Service '{svc_name}': '{deprecated}' is deprecated ({note})"
                        )

    return warnings


def detect_invalid_depends_on(service_name: str, depends_on: Any) -> list[str]:
    """
    Validate depends_on structure for a service.
    Returns list of errors.
    """
    errors: list[str] = []

    if depends_on is None:
        return errors

    if isinstance(depends_on, list):
        for dep in depends_on:
            if not isinstance(dep, str):
                errors.append(
                    f"Service '{service_name}': depends_on list entries must be strings, got {type(dep).__name__}"
                )

    elif isinstance(depends_on, dict):
        for dep_name, dep_config in depends_on.items():
            if not isinstance(dep_name, str):
                errors.append(
                    f"Service '{service_name}': depends_on keys must be strings"
                )
            if isinstance(dep_config, dict):
                # Check for valid condition field
                condition = dep_config.get('condition')
                if condition and condition not in ('service_started', 'service_healthy', 'service_completed_successfully'):
                    errors.append(
                        f"Service '{service_name}': depends_on[{dep_name}].condition has invalid value '{condition}'"
                    )
            elif dep_config is not None:
                errors.append(
                    f"Service '{service_name}': depends_on[{dep_name}] value must be a dict or null"
                )

    else:
        errors.append(
            f"Service '{service_name}': depends_on must be a list or dict, got {type(depends_on).__name__}"
        )

    return errors
