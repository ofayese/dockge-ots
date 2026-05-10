#!/usr/bin/env python3
"""
analyzer_report.py — Generate JSON and Markdown reports from analyzer findings.

Functions:
  - build_analyzer_report: Collect findings from all analyzer modules
  - render_json_report: Output structured JSON format (for PSU dashboard)
  - render_markdown_report: Output human-readable Markdown format
  - generate_dashboard_summary: Summarize findings for PSU dashboard visualization

Used by: inventory.py (extended) and PSU automation endpoints
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


def build_analyzer_report(
    compose_file: Path,
    env_file: Path,
    env_example_file: Path,
) -> dict[str, Any]:
    """
    Build comprehensive analyzer report for a stack.
    Returns dict with findings from all modules.
    """
    report: dict[str, Any] = {
        'timestamp': datetime.now().isoformat(),
        'stack_path': str(compose_file.parent),
        'compose_file': str(compose_file),
        'env_file': str(env_file),
        'env_example_file': str(env_example_file),
        'findings': {
            'schema_validation': [],
            'env_validation': {},  # Always a dict, even if .env doesn't exist
            'traefik_routing': [],
            'dependency_analysis': [],
            'security_checks': [],
        },
        'summary': {
            'total_issues': 0,
            'total_warnings': 0,
            'severity_breakdown': {'error': 0, 'warning': 0, 'info': 0},
        }
    }

    # Try to load and validate compose file
    try:
        import yaml
        with compose_file.open() as f:
            compose = yaml.safe_load(f) or {}

        # Import analyzer modules
        from . import compose_schema, env_validator, label_analyzer, dependency_graph

        # Run schema validation
        schema_errors = compose_schema.validate_v39_schema(compose)
        deprecated = compose_schema.detect_deprecated_fields(compose)

        report['findings']['schema_validation'] = {
            'errors': schema_errors,
            'deprecated_fields': deprecated,
        }

        # Run env validation
        if env_file.exists():
            env_errors = env_validator.validate_env_file(env_file)
            missing_keys = env_validator.detect_missing_keys(env_file, env_example_file)
            drift = env_validator.compare_env_drift(env_file, env_example_file)

            report['findings']['env_validation'] = {
                'errors': env_errors,
                'missing_keys': missing_keys,
                'drift_analysis': drift,
            }

        # Analyze dependencies
        services = compose.get('services', {}) or {}
        cycles = dependency_graph.detect_cycles(services)
        orphaned = dependency_graph.detect_orphaned_services(services)

        report['findings']['dependency_analysis'] = {
            'cycles': cycles,
            'orphaned_services': orphaned,
        }

        # Analyze Traefik labels
        traefik_issues: list[dict[str, Any]] = []
        for svc_name, svc_def in services.items():
            if isinstance(svc_def, dict):
                # normalize_labels returns dict[str, str] directly
                labels = label_analyzer.normalize_labels(svc_def.get('labels'))

                invalid = label_analyzer.detect_invalid_traefik_labels(labels)
                missing = label_analyzer.detect_missing_router_defs(svc_name, labels)

                if invalid or missing:
                    traefik_issues.append({
                        'service': svc_name,
                        'invalid_labels': invalid,
                        'missing_defs': missing,
                    })

        report['findings']['traefik_routing'] = traefik_issues

        # Count issues
        all_errors = schema_errors + report['findings']['env_validation'].get('errors', [])
        all_warnings = deprecated + report['findings']['env_validation'].get('missing_keys', [])

        report['summary']['total_issues'] = len(all_errors)
        report['summary']['total_warnings'] = len(all_warnings)
        report['summary']['severity_breakdown'] = {
            'error': len(all_errors),
            'warning': len(all_warnings),
            'info': len(cycles) + len(traefik_issues),
        }

    except Exception as e:
        logger.error(f"Error building analyzer report: {e}")
        report['findings']['error'] = str(e)

    return report


def render_json_report(report: dict[str, Any]) -> str:
    """
    Render analyzer report as JSON (for PSU dashboard and API responses).
    """
    return json.dumps(report, indent=2, default=str)


def render_markdown_report(report: dict[str, Any]) -> str:
    """
    Render analyzer report as Markdown (for human review).
    """
    lines: list[str] = []

    # Header
    lines.append(f"# Stack Analysis Report")
    lines.append(f"**Generated:** {report.get('timestamp', 'unknown')}")
    lines.append(f"**Stack:** {report.get('stack_path', 'unknown')}")
    lines.append("")

    # Summary
    summary = report.get('summary', {})
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- **Total Issues:** {summary.get('total_issues', 0)}")
    lines.append(f"- **Total Warnings:** {summary.get('total_warnings', 0)}")
    breakdown = summary.get('severity_breakdown', {})
    lines.append(f"- **Errors:** {breakdown.get('error', 0)}, **Warnings:** {breakdown.get('warning', 0)}, **Info:** {breakdown.get('info', 0)}")
    lines.append("")

    # Findings by category
    findings = report.get('findings', {})

    if findings.get('schema_validation'):
        lines.append("## Compose Schema Validation")
        lines.append("")
        schema = findings['schema_validation']
        if schema.get('errors'):
            lines.append("### Errors")
            for error in schema['errors']:
                lines.append(f"- {error}")
            lines.append("")
        if schema.get('deprecated_fields'):
            lines.append("### Deprecated Fields")
            for dep in schema['deprecated_fields']:
                lines.append(f"- {dep}")
            lines.append("")

    if findings.get('env_validation'):
        lines.append("## Environment File Validation")
        lines.append("")
        env = findings['env_validation']
        if env.get('errors'):
            lines.append("### Errors")
            for error in env['errors']:
                lines.append(f"- {error}")
            lines.append("")
        if env.get('missing_keys'):
            lines.append("### Missing Keys")
            for key in env['missing_keys']:
                lines.append(f"- `{key}`")
            lines.append("")

    if findings.get('dependency_analysis'):
        lines.append("## Dependency Analysis")
        lines.append("")
        deps = findings['dependency_analysis']
        if deps.get('cycles'):
            lines.append("### Circular Dependencies ⚠️")
            for cycle in deps['cycles']:
                lines.append(f"- {' → '.join(cycle)}")
            lines.append("")
        if deps.get('orphaned_services'):
            lines.append("### Orphaned Services")
            for svc in deps['orphaned_services']:
                lines.append(f"- `{svc}`")
            lines.append("")

    if findings.get('traefik_routing'):
        lines.append("## Traefik Routing Configuration")
        lines.append("")
        for issue in findings['traefik_routing']:
            lines.append(f"### Service: `{issue.get('service', 'unknown')}`")
            if issue.get('invalid_labels'):
                for inv in issue['invalid_labels']:
                    lines.append(f"- {inv}")
            if issue.get('missing_defs'):
                for miss in issue['missing_defs']:
                    lines.append(f"- {miss}")
            lines.append("")

    return "\n".join(lines)


def generate_dashboard_summary(reports: list[dict[str, Any]]) -> dict[str, Any]:
    """
    Generate summary metrics for PSU dashboard visualization.
    Aggregates findings across multiple stacks.
    """
    summary: dict[str, Any] = {
        'timestamp': datetime.now().isoformat(),
        'total_stacks': len(reports),
        'stacks_with_issues': 0,
        'aggregate_metrics': {
            'total_errors': 0,
            'total_warnings': 0,
            'total_cycles': 0,
            'total_orphaned': 0,
        },
        'top_issues': [],
    }

    issue_counts: dict[str, int] = {}

    for report in reports:
        rep_summary = report.get('summary', {})
        if rep_summary.get('total_issues', 0) > 0 or rep_summary.get('total_warnings', 0) > 0:
            summary['stacks_with_issues'] += 1

        summary['aggregate_metrics']['total_errors'] += rep_summary.get('total_issues', 0)
        summary['aggregate_metrics']['total_warnings'] += rep_summary.get('total_warnings', 0)

        findings = report.get('findings', {})

        # Count cycles
        cycles = findings.get('dependency_analysis', {}).get('cycles', [])
        summary['aggregate_metrics']['total_cycles'] += len(cycles)

        # Count orphaned
        orphaned = findings.get('dependency_analysis', {}).get('orphaned_services', [])
        summary['aggregate_metrics']['total_orphaned'] += len(orphaned)

        # Track issue types
        for issue_list in findings.get('schema_validation', {}).get('errors', []):
            key = 'schema_error'
            issue_counts[key] = issue_counts.get(key, 0) + 1

    # Top issues
    for issue_type, count in sorted(issue_counts.items(), key=lambda x: -x[1])[:10]:
        summary['top_issues'].append({'type': issue_type, 'count': count})

    return summary
