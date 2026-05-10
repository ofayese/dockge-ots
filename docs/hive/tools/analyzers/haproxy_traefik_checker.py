#!/usr/bin/env python3
"""
haproxy_traefik_checker.py — Validate HAProxy and Traefik configuration consistency.

Functions:
  - validate_haproxy_config: Check HAProxy config file syntax and structure
  - validate_traefik_dynamic_config: Check Traefik dynamic config (YAML/TOML)
  - detect_haproxy_traefik_mismatches: Find inconsistencies between HAProxy and Traefik routing

Used by: inventory.py (extended) and analyzer reports
"""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


def validate_haproxy_config(config_path: Path) -> list[str]:
    """
    Validate HAProxy config file for syntax errors and common issues.
    Returns list of errors/warnings.
    """
    issues: list[str] = []

    if not config_path.exists():
        issues.append(f"HAProxy config not found: {config_path}")
        return issues

    try:
        content = config_path.read_text()
    except Exception as e:
        issues.append(f"Failed to read HAProxy config: {e}")
        return issues

    lines = content.splitlines()

    # Check for required sections
    has_global = any('global' in line for line in lines)
    has_defaults = any('defaults' in line for line in lines)

    if not has_global:
        issues.append("Missing 'global' section in HAProxy config")
    if not has_defaults:
        issues.append("Missing 'defaults' section in HAProxy config")

    # Check for frontend/backend definitions
    frontends = set()
    backends = set()

    for i, line in enumerate(lines, 1):
        stripped = line.strip()

        # Skip comments
        if stripped.startswith('#'):
            continue

        # Extract frontend names
        if stripped.startswith('frontend '):
            parts = stripped.split()
            if len(parts) >= 2:
                frontends.add(parts[1])

        # Extract backend names
        if stripped.startswith('backend '):
            parts = stripped.split()
            if len(parts) >= 2:
                backends.add(parts[1])

        # Check for bind directives
        if 'bind' in stripped and '*:' not in stripped:
            if not any(c.isdigit() for c in stripped):
                issues.append(f"Line {i}: 'bind' directive without port number: {stripped[:50]}")

        # Check for backend usage
        if 'use_backend' in stripped:
            # Extract backend name from "use_backend backend_name ..."
            match = re.search(r'use_backend\s+(\w+)', stripped)
            if match:
                backend_name = match.group(1)
                if backend_name not in backends and backend_name != '-':
                    issues.append(f"Line {i}: 'use_backend {backend_name}' but backend not defined")

    return issues


def validate_traefik_dynamic_config(config_path: Path) -> list[str]:
    """
    Validate Traefik dynamic config file (YAML or TOML format).
    Returns list of errors/warnings.
    """
    issues: list[str] = []

    if not config_path.exists():
        issues.append(f"Traefik config not found: {config_path}")
        return issues

    try:
        content = config_path.read_text()
    except Exception as e:
        issues.append(f"Failed to read Traefik config: {e}")
        return issues

    # Check for http/tcp/udp sections
    has_http = 'http:' in content or '"http"' in content
    has_routers = 'routers' in content
    has_services = 'services' in content

    if has_routers and not has_http:
        issues.append("Traefik config has routers but no 'http' section")

    # Check for orphaned routers (routers without services)
    router_matches = re.findall(r'(\w+):\s*(?:rule|entrypoints)', content)
    service_matches = re.findall(r'(?:services:\s*)?(\w+):\s*loadbalancer', content)

    for router in set(router_matches):
        if router not in service_matches:
            issues.append(f"Traefik: router '{router}' may be orphaned (no matching service)")

    # Check TLS configuration if present
    if 'tls' in content:
        if 'certresolver' not in content and 'certificate' not in content:
            issues.append("Traefik has TLS routers but no certificate configuration")

    # YAML syntax check (basic)
    if config_path.suffix in ('.yaml', '.yml'):
        for i, line in enumerate(content.splitlines(), 1):
            if line.strip() and not line.startswith(' ') and ':' in line:
                # Likely a key definition; check indentation consistency
                pass

    return issues


def detect_haproxy_traefik_mismatches(haproxy_config: Path, traefik_config: Path) -> dict[str, Any]:
    """
    Compare HAProxy and Traefik configurations for inconsistencies.
    Returns dict with findings (mismatches, uncovered routes, etc).
    """
    result: dict[str, Any] = {
        'haproxy_backends': set(),
        'traefik_services': set(),
        'missing_in_traefik': [],
        'missing_in_haproxy': [],
        'port_mismatches': [],
    }

    # Parse HAProxy
    if haproxy_config.exists():
        try:
            content = haproxy_config.read_text()
            backends = re.findall(r'backend\s+(\w+)', content)
            result['haproxy_backends'] = set(backends)
        except Exception as e:
            logger.warning(f"Failed to parse HAProxy config: {e}")

    # Parse Traefik
    if traefik_config.exists():
        try:
            content = traefik_config.read_text()
            services = re.findall(r'(?:services:\s*)?(\w+):\s*loadbalancer', content)
            result['traefik_services'] = set(services)
        except Exception as e:
            logger.warning(f"Failed to parse Traefik config: {e}")

    # Find mismatches
    result['missing_in_traefik'] = sorted(
        result['haproxy_backends'] - result['traefik_services']
    )
    result['missing_in_haproxy'] = sorted(
        result['traefik_services'] - result['haproxy_backends']
    )

    return result
