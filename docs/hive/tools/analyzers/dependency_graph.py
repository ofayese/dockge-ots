#!/usr/bin/env python3
"""
dependency_graph.py — Build and analyze service dependency graphs.

Functions:
  - build_dependency_graph: Create directed graph of service dependencies
  - detect_cycles: Find circular dependencies
  - detect_orphaned_services: Find services not referenced by anything
  - topological_sort: Order services by dependency

Used by: inventory.py (extended) and analyzer reports
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)


class DependencyGraph:
    """Directed graph for service dependencies."""

    def __init__(self) -> None:
        self.graph: dict[str, list[str]] = {}

    def add_service(self, service: str) -> None:
        """Add a service node (with no edges initially)."""
        if service not in self.graph:
            self.graph[service] = []

    def add_edge(self, from_service: str, to_service: str) -> None:
        """Add an edge: from_service -> to_service."""
        self.add_service(from_service)
        self.add_service(to_service)
        if to_service not in self.graph[from_service]:
            self.graph[from_service].append(to_service)

    def get_all_services(self) -> set[str]:
        """Return all services in the graph."""
        return set(self.graph.keys())

    def find_cycles(self) -> list[list[str]]:
        """
        Find all cycles in the graph.
        Returns list of cycles (each cycle is a list of service names).
        """
        visited: dict[str, int] = {}  # 0=unvisited, 1=visiting, 2=visited
        cycles: list[list[str]] = []

        def dfs(node: str, path: list[str]) -> None:
            if node in visited:
                if visited[node] == 1:
                    # Found a cycle: from current node to where it appears in path
                    cycle_start = path.index(node)
                    cycle = path[cycle_start:] + [node]
                    cycles.append(cycle)
                return

            visited[node] = 1
            path.append(node)

            for neighbor in self.graph.get(node, []):
                dfs(neighbor, path.copy())

            visited[node] = 2

        for service in self.graph.keys():
            if service not in visited:
                dfs(service, [])

        return cycles

    def find_orphaned_services(self) -> list[str]:
        """
        Find services that are never depended upon.
        (Services with no incoming edges.)
        """
        all_services = self.get_all_services()
        has_incoming = set()

        for service, dependencies in self.graph.items():
            for dep in dependencies:
                has_incoming.add(dep)

        orphaned = sorted(all_services - has_incoming)
        return orphaned

    def topological_sort(self) -> list[str] | None:
        """
        Topological sort of services by dependency.
        Returns ordered list if acyclic, None if cycle detected.
        """
        cycles = self.find_cycles()
        if cycles:
            return None

        visited: set[str] = set()
        stack: list[str] = []

        def dfs(node: str) -> None:
            if node in visited:
                return
            visited.add(node)
            for neighbor in self.graph.get(node, []):
                dfs(neighbor)
            stack.append(node)

        for service in self.graph.keys():
            dfs(service)

        return list(reversed(stack))


def build_dependency_graph(services: dict[str, dict[str, Any]]) -> DependencyGraph:
    """
    Build dependency graph from compose services dict.
    Each service's depends_on creates edges.
    """
    graph = DependencyGraph()

    for service_name in services.keys():
        graph.add_service(service_name)

    for service_name, service_def in services.items():
        if not isinstance(service_def, dict):
            continue

        depends_on = service_def.get('depends_on', [])

        if isinstance(depends_on, list):
            for dep in depends_on:
                if isinstance(dep, str):
                    graph.add_edge(service_name, dep)

        elif isinstance(depends_on, dict):
            for dep_name in depends_on.keys():
                if isinstance(dep_name, str):
                    graph.add_edge(service_name, dep_name)

    return graph


def detect_cycles(services: dict[str, dict[str, Any]]) -> list[list[str]]:
    """
    Detect circular dependencies in services.
    Returns list of cycles found.
    """
    graph = build_dependency_graph(services)
    return graph.find_cycles()


def detect_orphaned_services(services: dict[str, dict[str, Any]]) -> list[str]:
    """
    Find services that nothing depends on.
    Returns sorted list of orphaned service names.
    """
    graph = build_dependency_graph(services)
    return graph.find_orphaned_services()


def topological_sort(services: dict[str, dict[str, Any]]) -> list[str] | None:
    """
    Get services in dependency order (safe startup order).
    Returns ordered list if no cycles, None if cycle detected.
    """
    graph = build_dependency_graph(services)
    return graph.topological_sort()
