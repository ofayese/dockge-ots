#!/usr/bin/env python3
"""
env_validator.py — Validate .env files against .env.example and detect drift.

Functions:
  - validate_env_file: Check .env for syntax and required keys
  - detect_missing_keys: Find keys in .env.example that are missing from .env
  - detect_malformed_entries: Identify invalid KEY=VALUE syntax
  - compare_env_drift: Detect divergence between .env and .env.example

Used by: inventory.py (extended) and analyzer reports
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


def parse_env_file(content: str) -> dict[str, str]:
    """
    Parse KEY=VALUE file format.
    Returns dict of key->value. Skips comments and blank lines.
    """
    result: dict[str, str] = {}
    for line in content.splitlines():
        line = line.strip()
        # Skip empty and comment lines
        if not line or line.startswith('#'):
            continue
        if '=' not in line:
            continue
        key, _, value = line.partition('=')
        key = key.strip()
        value = value.strip()
        if key:
            result[key] = value
    return result


def validate_env_file(env_path: Path) -> list[str]:
    """
    Validate .env file syntax and format.
    Returns list of errors (empty if valid).
    """
    errors: list[str] = []

    if not env_path.exists():
        errors.append(f"File not found: {env_path}")
        return errors

    try:
        content = env_path.read_text()
    except Exception as e:
        errors.append(f"Failed to read {env_path}: {e}")
        return errors

    for i, line in enumerate(content.splitlines(), 1):
        line_stripped = line.strip()

        # Skip empty and comment lines
        if not line_stripped or line_stripped.startswith('#'):
            continue

        # Check for KEY=VALUE format
        if '=' not in line:
            errors.append(f"{env_path}:{i}: malformed entry (no '='): {line_stripped[:50]}")
            continue

        key, _, value = line.partition('=')
        key = key.strip()
        value = value.strip()

        # Validate key format (alphanumeric, underscore, no spaces)
        if not key or not all(c.isalnum() or c == '_' for c in key):
            errors.append(f"{env_path}:{i}: invalid KEY format: {key}")

        # Check for unquoted values with spaces (may be accidental)
        if ' ' in value and not (value.startswith('"') and value.endswith('"')) \
           and not (value.startswith("'") and value.endswith("'")):
            if not any(var in value for var in ['${', '$(']):  # Allow shell vars
                logger.warning(f"{env_path}:{i}: value with spaces (should be quoted?): {key}={value[:30]}")

    return errors


def detect_missing_keys(env_file: Path, env_example_file: Path) -> list[str]:
    """
    Find keys in .env.example that are missing from .env.
    Returns list of warnings.
    """
    warnings: list[str] = []

    if not env_example_file.exists():
        return warnings

    try:
        example_content = env_example_file.read_text()
        env_content = env_file.read_text() if env_file.exists() else ""
    except Exception:
        return warnings

    example_keys = set(parse_env_file(example_content).keys())
    env_keys = set(parse_env_file(env_content).keys())

    missing = example_keys - env_keys
    if missing:
        for key in sorted(missing):
            warnings.append(f"Key '{key}' in {env_example_file.name} but missing from {env_file.name}")

    return warnings


def detect_malformed_entries(env_path: Path) -> list[str]:
    """
    Identify entries that don't follow KEY=VALUE syntax.
    Returns list of errors.
    """
    errors: list[str] = []

    if not env_path.exists():
        return errors

    try:
        content = env_path.read_text()
    except Exception:
        return errors

    for i, line in enumerate(content.splitlines(), 1):
        line_stripped = line.strip()

        # Skip empty and comment lines
        if not line_stripped or line_stripped.startswith('#'):
            continue

        # Check if line looks like it's trying to be an assignment but failed
        if '=' not in line:
            # Might be continuation or export statement
            if not line_stripped.startswith('export '):
                errors.append(f"{env_path}:{i}: no '=' found (not KEY=VALUE): {line_stripped[:50]}")

    return errors


def compare_env_drift(env_file: Path, env_example_file: Path) -> dict[str, Any]:
    """
    Comprehensive comparison between .env and .env.example.
    Returns dict with:
      missing_keys, extra_keys, value_changes, malformed_entries
    """
    result: dict[str, Any] = {
        'missing_keys': [],
        'extra_keys': [],
        'value_changes': [],
        'malformed_entries': []
    }

    if not env_example_file.exists():
        return result

    try:
        example_content = env_example_file.read_text()
        env_content = env_file.read_text() if env_file.exists() else ""
    except Exception:
        return result

    example_env = parse_env_file(example_content)
    env_dict = parse_env_file(env_content)

    # Missing keys (in example but not in env)
    result['missing_keys'] = sorted(set(example_env.keys()) - set(env_dict.keys()))

    # Extra keys (in env but not in example)
    result['extra_keys'] = sorted(set(env_dict.keys()) - set(example_env.keys()))

    # Value changes (keys that exist in both but have different values)
    for key in set(example_env.keys()) & set(env_dict.keys()):
        if example_env[key] != env_dict[key]:
            result['value_changes'].append({
                'key': key,
                'example_value': example_env[key][:50] if example_env[key] else '(empty)',
                'env_value': env_dict[key][:50] if env_dict[key] else '(empty)',
            })

    # Malformed entries
    result['malformed_entries'] = detect_malformed_entries(env_file)

    return result
