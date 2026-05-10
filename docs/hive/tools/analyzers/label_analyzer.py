#!/usr/bin/env python3
"""
label_analyzer.py — Analyze and validate docker-compose service labels.

Functions:
  - normalize_labels: Convert label dict/list to standardized format
  - detect_invalid_traefik_labels: Find missing or malformed Traefik directives
  - validate_traefik_routing: Ensure router and service are properly defined
  - detect_missing_router_defs: Find routers without corresponding service definitions

Used by: inventory.py (extended) and analyzer reports
"""

from __future__ import annotations

import logging
import re
from typing import Any

logger = logging.getLogger(__name__)


def normalize_labels(labels: Any) -> dict[str, str]:
    """
    Convert labels (dict, list, or None) into normalized dict.
    Returns dict of label_name -> label_value.
    """
    result: dict[str, str] = {}

    if labels is None:
        return result

    if isinstance(labels, dict):
        for k, v in labels.items():
            result[str(k)] = str(v)
    elif isinstance(labels, list):
        for item in labels:
            s = str(item)
            if '=' in s:
                k, _, v = s.partition('=')
                result[k.strip()] = v.strip()
            else:
                logger.warning(f"Label without '=': {s}")

    return result


def detect_invalid_traefik_labels(labels: dict[str, str]) -> list[str]:
    """
    Find Traefik labels that are malformed or missing required fields.
    Returns list of warnings.
    """
    warnings: list[str] = []

    traefik_labels = {k: v for k, v in labels.items() if k.startswith('traefik.')}

    if not traefik_labels:
        return warnings

    # Check for traefik.enable
    if 'traefik.enable' not in traefik_labels:
        warnings.append("Traefik labels present but 'traefik.enable' is missing")

    # Check for routers without services
    router_patterns = re.compile(r'traefik\.http\.routers\.([^.]+)\.')
    service_patterns = re.compile(r'traefik\.http\.services\.([^.]+)\.')

    routers = set()
    services = set()

    for label_name in traefik_labels.keys():
        if router_match := router_patterns.search(label_name):
            routers.add(router_match.group(1))
        if service_match := service_patterns.search(label_name):
            services.add(service_match.group(1))

    # Find routers without services
    for router in routers:
        if router not in services:
            warnings.append(f"Router '{router}' defined but no service 'traefik.http.services.{router}' found")

    # Check router structure
    for router in routers:
        router_labels = {k: v for k, v in traefik_labels.items() if f'traefik.http.routers.{router}.' in k}
        if not any('rule' in k for k in router_labels.keys()):
            warnings.append(f"Router '{router}' missing 'traefik.http.routers.{router}.rule'")
        if not any('entrypoints' in k for k in router_labels.keys()):
            warnings.append(f"Router '{router}' missing 'traefik.http.routers.{router}.entrypoints'")

    # Check service structure
    for service in services:
        service_labels = {k: v for k, v in traefik_labels.items() if f'traefik.http.services.{service}.' in k}
        if not any('loadbalancer' in k for k in service_labels.keys()):
            warnings.append(f"Service '{service}' missing loadbalancer configuration")

    return warnings


def validate_traefik_routing(service_name: str, labels: dict[str, str]) -> list[str]:
    """
    Validate complete Traefik routing setup for a service.
    Returns list of errors.
    """
    errors: list[str] = []

    traefik_labels = {k: v for k, v in labels.items() if k.startswith('traefik.')}

    if not traefik_labels:
        return errors

    # Extract enable flag
    traefik_enable = traefik_labels.get('traefik.enable', 'false').lower()
    if traefik_enable != 'true':
        return errors  # Traefik disabled, skip validation

    # Check required fields for HTTP routing
    http_routers = {k: v for k, v in traefik_labels.items() if 'traefik.http.routers.' in k}

    if http_routers and not any('http' in k for k in http_routers.keys()):
        errors.append(f"Service '{service_name}': Traefik enabled but no HTTP routers configured")

    # Check rule format
    for router_rule in [v for k, v in traefik_labels.items() if '.rule=' in k or '.rule' in k]:
        if not router_rule or not any(c in router_rule for c in ['Host', 'Path', 'Method']):
            errors.append(f"Service '{service_name}': router rule format invalid: {router_rule}")

    return errors


def detect_missing_router_defs(service_name: str, labels: dict[str, str]) -> list[str]:
    """
    Find router definitions that are incomplete or reference non-existent services.
    Returns list of warnings.
    """
    warnings: list[str] = []

    traefik_labels = {k: v for k, v in labels.items() if k.startswith('traefik.')}

    if not traefik_labels:
        return warnings

    # Extract all router and service names
    router_pattern = re.compile(r'traefik\.http\.routers\.([^.]+)')
    service_pattern = re.compile(r'traefik\.http\.services\.([^.]+)')

    routers = set()
    services = set()

    for label_key in traefik_labels.keys():
        if m := router_pattern.search(label_key):
            routers.add(m.group(1))
        if m := service_pattern.search(label_key):
            services.add(m.group(1))

    # Check each router has a corresponding service
    for router in routers:
        if router not in services:
            warnings.append(
                f"Service '{service_name}': router '{router}' has no corresponding service definition"
            )

    # Check middleware references (if present)
    for label_key, label_val in traefik_labels.items():
        if 'middleware' in label_key and label_val:
            # Middleware format: "name1,name2" or just "name1"
            middlewares = [m.strip() for m in str(label_val).split(',')]
            # Note: We can't validate middleware definitions exist here (would need full traefik config)
            # Just warn if format looks off
            for mw in middlewares:
                if not mw or ' ' in mw:
                    warnings.append(f"Service '{service_name}': suspicious middleware format: {label_val}")

    return warnings
