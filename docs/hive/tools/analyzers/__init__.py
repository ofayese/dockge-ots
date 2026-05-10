#!/usr/bin/env python3
"""Analyzer package init — expose all analyzer modules."""

from .compose_schema import (
    validate_v39_schema,
    detect_deprecated_fields,
    detect_invalid_depends_on,
)
from .env_validator import (
    validate_env_file,
    detect_missing_keys,
    detect_malformed_entries,
    compare_env_drift,
)
from .label_analyzer import (
    normalize_labels,
    detect_invalid_traefik_labels,
    validate_traefik_routing,
    detect_missing_router_defs,
)
from .dependency_graph import (
    build_dependency_graph,
    detect_cycles,
    detect_orphaned_services,
    topological_sort,
)
from .haproxy_traefik_checker import (
    validate_haproxy_config,
    validate_traefik_dynamic_config,
    detect_haproxy_traefik_mismatches,
)
from .analyzer_report import (
    build_analyzer_report,
    render_json_report,
    render_markdown_report,
    generate_dashboard_summary,
)

__all__ = [
    'validate_v39_schema',
    'detect_deprecated_fields',
    'detect_invalid_depends_on',
    'validate_env_file',
    'detect_missing_keys',
    'detect_malformed_entries',
    'compare_env_drift',
    'normalize_labels',
    'detect_invalid_traefik_labels',
    'validate_traefik_routing',
    'detect_missing_router_defs',
    'build_dependency_graph',
    'detect_cycles',
    'detect_orphaned_services',
    'topological_sort',
    'validate_haproxy_config',
    'validate_traefik_dynamic_config',
    'detect_haproxy_traefik_mismatches',
    'build_analyzer_report',
    'render_json_report',
    'render_markdown_report',
    'generate_dashboard_summary',
]
