#!/usr/bin/env python3
"""
inventory.py — Generate `docs/hive/proposals/<stack>/INVENTORY.md` for a Dockge stack.

Per HIVE_OBJECTIVE.md M1 spec: services / images / ports / volumes / networks /
secrets surface / hostname check / baseline gap matrix.

Usage:
    inventory.py <stack>            # write docs/hive/proposals/<stack>/INVENTORY.md
    inventory.py --all              # regenerate every stack folder
    inventory.py --stdout <stack>   # print to stdout, do not write
    inventory.py --repo-root PATH   # git repo root (contains HIVE_OBJECTIVE.md); stacks live in stacks/
"""

from __future__ import annotations

import argparse
import logging
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    sys.exit("ERROR: PyYAML required (pip install pyyaml)")

logger = logging.getLogger(__name__)


# ---------- compose-level extraction ----------

@dataclass
class ServiceFacts:
    name: str
    container: str | None
    image: str
    pin_kind: str  # 'digest' | 'semver' | 'latest' | 'floating'
    ports: list[str]
    volumes: list[tuple[str, str, str]]  # (host, container, mode)
    networks: list[str]
    env: dict[str, str]              # key -> source ('inline VALUE' or 'env')
    secrets_refs: list[str]
    healthcheck: bool
    logging: bool
    watchtower: bool
    security_opt: bool
    mem_limit: str | None
    cpu_shares: int | None
    restart: str | None
    extra_hosts: list[str]
    depends_on: list[str]
    cap_drop: list[str]
    cap_add: list[str]
    network_mode: str | None


@dataclass
class StackFacts:
    name: str
    path: Path
    compose: Path
    services: list[ServiceFacts]
    top_secrets: dict[str, dict]
    top_networks: dict[str, dict]
    top_volumes: dict[str, dict]
    has_env: bool
    has_env_example: bool
    has_readme: bool
    extra_files: list[str]
    stale_hostname_hits: list[str]
    bare_orundscore_hits: list[str] = field(default_factory=list)


def classify_pin(image: str) -> str:
    if "@sha256:" in image:
        return "digest"
    if ":" not in image:
        return "latest"  # implicit :latest
    tag = image.rsplit(":", 1)[1]
    if tag in ("latest", "main", "master", "edge", "nightly"):
        return "floating" if tag != "latest" else "latest"
    # heuristic: digit-anywhere → semver-ish
    return "semver" if any(c.isdigit() for c in tag) else "floating"


def parse_volume(v: Any) -> tuple[str, str, str]:
    """Return (host, container, mode). Mode '' if unspecified."""
    if isinstance(v, dict):
        return (v.get("source", ""), v.get("target", ""), v.get("read_only") and "ro" or "rw")
    parts = str(v).split(":")
    if len(parts) == 2:
        return (parts[0], parts[1], "")
    if len(parts) >= 3:
        return (parts[0], parts[1], parts[2])
    return (str(v), "", "")


def parse_env(env: Any) -> dict[str, str]:
    """Normalize env (list or map) → dict of key -> source descriptor."""
    out: dict[str, str] = {}
    if env is None:
        return out
    if isinstance(env, list):
        for entry in env:
            s = str(entry)
            if "=" in s:
                k, v = s.split("=", 1)
                out[k] = f"inline `{v}`" if v else "inline (empty)"
            else:
                # Compose treats bare tokens as host-env names; surface once here (not again in anomalies).
                out[s] = "malformed list entry (no '='; Compose treats as host-env name)"
    elif isinstance(env, dict):
        for k, v in env.items():
            if v is None:
                out[k] = "host env (no default)"
            else:
                vs = str(v)
                if vs.startswith("${") and vs.endswith("}"):
                    out[k] = "env"
                else:
                    out[k] = f"inline `{vs}`"
    return out


def normalize_labels(labels: Any) -> list[str]:
    """Compose `labels` may be dict, list, None, or absent. Never iterate a non-collection."""
    if labels is None:
        return []
    if isinstance(labels, dict):
        return [f"{k}={v}" for k, v in labels.items()]
    if isinstance(labels, list):
        return [str(x) for x in labels]
    return []


def extract_service(name: str, raw: dict) -> ServiceFacts:
    image = raw.get("image", "")
    healthcheck = bool(raw.get("healthcheck"))
    logging = bool(raw.get("logging"))

    labels_iter = normalize_labels(raw.get("labels"))
    watchtower = any(
        "centurylinklabs.watchtower.enable" in str(l) and "true" in str(l).lower() for l in labels_iter
    )

    sec_opts = raw.get("security_opt", []) or []
    security_opt = any("no-new-privileges" in str(s) and "true" in str(s).lower() for s in sec_opts)

    ports = [str(p) for p in (raw.get("ports") or [])]
    volumes = [parse_volume(v) for v in (raw.get("volumes") or [])]

    nets = raw.get("networks", []) or []
    if isinstance(nets, dict):
        networks = list(nets.keys())
    else:
        networks = [str(n) for n in nets]

    env = parse_env(raw.get("environment"))

    secrets = raw.get("secrets", []) or []
    secrets_refs = []
    for s in secrets:
        if isinstance(s, dict):
            secrets_refs.append(s.get("source", str(s)))
        else:
            secrets_refs.append(str(s))

    depends = raw.get("depends_on", []) or []
    if isinstance(depends, dict):
        depends_on = [
            f"{k} ({v.get('condition', 'started')})" if isinstance(v, dict) else f"{k} ({str(v)})"
            for k, v in depends.items()
        ]
    else:
        depends_on = [str(d) for d in depends]

    return ServiceFacts(
        name=name,
        container=raw.get("container_name"),
        image=image,
        pin_kind=classify_pin(image),
        ports=ports,
        volumes=volumes,
        networks=networks,
        env=env,
        secrets_refs=secrets_refs,
        healthcheck=healthcheck,
        logging=logging,
        watchtower=watchtower,
        security_opt=security_opt,
        mem_limit=raw.get("mem_limit"),
        cpu_shares=raw.get("cpu_shares"),
        restart=raw.get("restart"),
        extra_hosts=[str(h) for h in (raw.get("extra_hosts") or [])],
        depends_on=depends_on,
        cap_drop=[str(c) for c in (raw.get("cap_drop") or [])],
        cap_add=[str(c) for c in (raw.get("cap_add") or [])],
        network_mode=raw.get("network_mode"),
    )


def hostname_check(stack_path: Path, repo_root: Path) -> tuple[list[str], list[str]]:
    """Run boundary-aware orundscore checks. Returns (stale_hits, bare_hits)."""
    if not shutil.which("rg"):
        return ([], [])
    rel = stack_path.relative_to(repo_root)
    rel_s = str(rel)
    stale_re = re.compile(r"(?<!ots)orundscore")
    bare_re = re.compile(r"\borundscore")

    def lines_from_completed(proc: subprocess.CompletedProcess[str]) -> list[str]:
        return [l for l in proc.stdout.splitlines() if l.strip()]

    def fallback_from_fixed_string() -> tuple[list[str], list[str]]:
        """If PCRE2 `rg` times out, use fixed-string search then Python filter (no lookbehind in rg)."""
        try:
            r2 = subprocess.run(
                ["rg", "-F", "orundscore", rel_s],
                cwd=repo_root,
                capture_output=True,
                text=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            logger.warning("rg fallback (-F orundscore) also timed out for %s", rel_s)
            return ([], [])
        raw = [l for l in r2.stdout.splitlines() if l.strip()]
        return ([l for l in raw if stale_re.search(l)], [l for l in raw if bare_re.search(l)])

    try:
        stale = subprocess.run(
            ["rg", "--pcre2", "(?<!ots)orundscore", rel_s],
            cwd=repo_root,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        logger.warning("rg --pcre2 stale pattern timed out for %s; using fallback search", rel_s)
        return fallback_from_fixed_string()
    except FileNotFoundError:
        return ([], [])

    try:
        bare = subprocess.run(
            ["rg", "--pcre2", r"\borundscore", rel_s],
            cwd=repo_root,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        logger.warning("rg --pcre2 bare pattern timed out for %s; using fallback search", rel_s)
        stale_lines = lines_from_completed(stale)
        _, bare_lines = fallback_from_fixed_string()
        return (stale_lines, bare_lines)

    return (lines_from_completed(stale), lines_from_completed(bare))


def load_stack(stack_path: Path, repo_root: Path) -> StackFacts:
    compose_path: Path
    for name in ("compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml"):
        p = stack_path / name
        if p.exists():
            compose_path = p
            break
    else:
        sys.exit(f"ERROR: no compose file in {stack_path}")

    with compose_path.open() as f:
        compose = yaml.safe_load(f) or {}

    services = [extract_service(n, raw or {}) for n, raw in (compose.get("services") or {}).items()]

    interesting = {".env", ".env.example", "README.md"}
    extra = sorted(
        p.name for p in stack_path.iterdir()
        if p.is_file() and p.name not in interesting and not p.name.startswith(".") and p.suffix not in (".yaml", ".yml")
    )

    stale, bare = hostname_check(stack_path, repo_root)

    return StackFacts(
        name=stack_path.name,
        path=stack_path,
        compose=compose_path,
        services=services,
        top_secrets=compose.get("secrets", {}) or {},
        top_networks=compose.get("networks", {}) or {},
        top_volumes=compose.get("volumes", {}) or {},
        has_env=(stack_path / ".env").exists(),
        has_env_example=(stack_path / ".env.example").exists(),
        has_readme=(stack_path / "README.md").exists(),
        extra_files=extra,
        stale_hostname_hits=stale,
        bare_orundscore_hits=bare,
    )


# ---------- markdown rendering ----------

PIN_BADGE = {
    "digest": "✓ digest",
    "semver": "✓ semver tag",
    "latest": "✗ `:latest`",
    "floating": "✗ floating tag",
}


def fmt_check(b: bool) -> str:
    return "✓" if b else "✗ missing"


def render_inventory(stack: StackFacts) -> str:
    lines: list[str] = []
    A = lines.append

    A(f"# INVENTORY — {stack.name}")
    A("")
    A(f"**Path:** `{stack.name}/{stack.compose.name}` · **Generated:** auto via `docs/hive/tools/inventory.py`")
    A("")

    # ---- Services ----
    A("## Services")
    A("")
    A("| Name | Container | Image | Pin | Ports | Notes |")
    A("|---|---|---|---|---|---|")
    for s in stack.services:
        notes = []
        if s.network_mode:
            notes.append(f"`network_mode: {s.network_mode}`")
        if s.depends_on:
            notes.append(f"depends_on: {', '.join(s.depends_on)}")
        if s.cap_drop or s.cap_add:
            notes.append(f"caps drop=[{','.join(s.cap_drop)}] add=[{','.join(s.cap_add)}]")
        ports = ", ".join(f"`{p}`" for p in s.ports) or "n/a"
        container = f"`{s.container}`" if s.container else "—"
        A(f"| `{s.name}` | {container} | `{s.image}` | {PIN_BADGE.get(s.pin_kind, '?')} | {ports} | {'; '.join(notes) or '—'} |")
    A("")

    # ---- Volumes ----
    A("## Volumes")
    A("")
    if stack.top_volumes:
        named = ", ".join(f"`{k}`" for k in stack.top_volumes.keys())
        A(f"Top-level named volumes: {named}.")
        A("")
    has_binds = any(s.volumes for s in stack.services)
    if has_binds:
        A("| Service | Host | Container | Mode |")
        A("|---|---|---|---|")
        for s in stack.services:
            for host, ctr, mode in s.volumes:
                mode_disp = mode if mode else "(default)"
                A(f"| {s.name} | `{host}` | `{ctr}` | {mode_disp} |")
        A("")
    if not has_binds and not stack.top_volumes:
        A("None.")
        A("")

    # ---- Networks ----
    A("## Networks")
    A("")
    if stack.top_networks:
        for n, cfg in stack.top_networks.items():
            ext = " (external)" if (isinstance(cfg, dict) and cfg.get("external")) else ""
            A(f"- `{n}`{ext}")
    else:
        A("No top-level `networks:` declared — services use compose-default project bridge.")
    A("")

    # ---- extra_hosts ----
    eh = [(s.name, h) for s in stack.services for h in s.extra_hosts]
    if eh:
        A("## extra_hosts")
        A("")
        for svc, h in eh:
            ok = " ✓" if "otsorundscore" in h else " ⚠ check"
            A(f"- `{svc}`: `{h}`{ok}")
        A("")

    # ---- Secrets surface ----
    A("## Secrets surface (keys only — no values)")
    A("")
    if stack.top_secrets:
        A("Compose-level `secrets:`:")
        A("")
        A("| Secret | Source | Used by |")
        A("|---|---|---|")
        for sname, sdef in stack.top_secrets.items():
            src = sdef.get("file", "external") if isinstance(sdef, dict) else "?"
            users = ", ".join(s.name for s in stack.services if sname in s.secrets_refs) or "—"
            A(f"| `{sname}` | `{src}` | {users} |")
        A("")
    has_env_keys = any(s.env for s in stack.services)
    if has_env_keys:
        A("Service environment keys:")
        A("")
        A("| Service | Key | Source |")
        A("|---|---|---|")
        for s in stack.services:
            for k, v in s.env.items():
                A(f"| `{s.name}` | `{k}` | {v} |")
        A("")
    A(f"`.env` present: {'YES' if stack.has_env else 'no'}; `.env.example` present: {'YES' if stack.has_env_example else 'no'}.")
    A("")

    # ---- Hostname check ----
    A("## Hostname check (per acme-sh/AGENTS.md boundary-aware regex)")
    A("")
    if stack.stale_hostname_hits:
        A("**STALE hits** (`(?<!ots)orundscore`):")
        A("")
        for line in stack.stale_hostname_hits[:20]:
            A(f"- `{line}`")
        if len(stack.stale_hostname_hits) > 20:
            A(f"- … and {len(stack.stale_hostname_hits) - 20} more")
        A("")
    else:
        A("`rg --pcre2 '(?<!ots)orundscore'`: **0 hits.** No stale hostnames.")
        A("")

    # ---- Gap matrix ----
    A("## Gaps vs baseline ([_baseline/PROPOSAL.md](../_baseline/PROPOSAL.md))")
    A("")
    headers = ["Item"] + [f"`{s.name}`" for s in stack.services]
    rows: list[list[str]] = []
    rows.append(["`security_opt: no-new-privileges:true`"] + [fmt_check(s.security_opt) for s in stack.services])
    rows.append(["`restart: on-failure:5`"] + [
        "✓" if s.restart == "on-failure:5" else (f"variant `{s.restart}`" if s.restart else "✗ missing")
        for s in stack.services
    ])
    rows.append(["watchtower label"] + [fmt_check(s.watchtower) for s in stack.services])
    rows.append(["`mem_limit`"] + [
        f"✓ `{s.mem_limit}`" if s.mem_limit else "✗ missing" for s in stack.services
    ])
    rows.append(["`cpu_shares`"] + [
        f"✓ `{s.cpu_shares}`" if s.cpu_shares else "✗ missing" for s in stack.services
    ])
    rows.append(["`TZ` env"] + [
        "✓" if "TZ" in s.env else "✗ missing" for s in stack.services
    ])
    rows.append(["image pin"] + [PIN_BADGE.get(s.pin_kind, "?") for s in stack.services])
    rows.append(["`healthcheck`"] + [fmt_check(s.healthcheck) for s in stack.services])
    rows.append(["`logging` block"] + [fmt_check(s.logging) for s in stack.services])

    A("| " + " | ".join(headers) + " |")
    A("|" + "|".join(["---"] * len(headers)) + "|")
    for row in rows:
        A("| " + " | ".join(row) + " |")
    A("")

    A("Stack-level:")
    A("")
    A(f"- `.env.example`: {'✓' if stack.has_env_example else '✗ missing'}")
    A(f"- `README.md`: {'✓' if stack.has_readme else '✗ missing'}")
    if stack.extra_files:
        A(f"- Other files in stack folder: {', '.join('`'+f+'`' for f in stack.extra_files)}")
    A("")

    # ---- Auto-detected anomalies ----
    anomalies: list[str] = []
    for s in stack.services:
        for k, v in s.env.items():
            if "REPLACE" in v.upper() or "CHANGEME" in v.upper() or "PLACEHOLDER" in v.upper():
                anomalies.append(f"`{s.name}` env `{k}` looks like a placeholder: {v}")
        # docker.sock rw warning
        for host, ctr, mode in s.volumes:
            if "docker.sock" in host and mode != "ro":
                anomalies.append(f"`{s.name}` mounts `docker.sock` as `{mode or 'default rw'}` — consider `:ro` if container only needs to read")

    if anomalies:
        A("## Auto-detected anomalies")
        A("")
        for a in anomalies:
            A(f"- {a}")
        A("")

    A("## Notes")
    A("")
    A(
        "Auto-generated by `docs/hive/tools/inventory.py`. Stack-specific narrative "
        "(scope questions, RACI follow-ups, action priority) belongs in this stack's "
        "`PROPOSAL.md` — see [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md) for the fleet-wide standard."
    )
    A("")

    return "\n".join(lines)


# ---------- driver ----------

def find_repo_root(start: Path) -> Path:
    cur = start.resolve()
    for p in [cur] + list(cur.parents):
        if (p / "HIVE_OBJECTIVE.md").exists():
            return p
    sys.exit(f"ERROR: could not locate HIVE_OBJECTIVE.md walking up from {start}")


def stacks_root(repo_root: Path) -> Path:
    """Directory that contains stack folders (e.g. acme-sh). Monorepo: repo/stacks/."""
    nested = repo_root / "stacks"
    if (nested / "acme-sh").is_dir() or (nested / "databases").is_dir():
        return nested
    if (repo_root / "acme-sh").is_dir():
        return repo_root
    return nested


STACKS = [
    "acme-sh", "code-server", "codex-docs", "databases",
    "dozzle", "homepage", "it-tools", "ollama",
    "openresume", "portainer", "searxng", "watchtower",
]


def process(stack_name: str, repo_root: Path, write: bool) -> str:
    sr = stacks_root(repo_root)
    stack_path = sr / stack_name
    if not stack_path.is_dir():
        sys.exit(f"ERROR: stack folder not found: {stack_path}")
    facts = load_stack(stack_path, repo_root)
    md = render_inventory(facts)
    if write:
        out_dir = repo_root / "docs" / "hive" / "proposals" / stack_name
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "INVENTORY.md").write_text(md)
        print(f"  wrote {out_dir / 'INVENTORY.md'} ({len(md.splitlines())} lines)")
    return md


def main() -> int:
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stack", nargs="?", help="stack folder name (e.g. acme-sh)")
    ap.add_argument("--all", action="store_true", help="process every known stack")
    ap.add_argument("--stdout", action="store_true", help="print to stdout, do not write file")
    ap.add_argument("--repo-root", type=Path, help="override repo root detection")
    args = ap.parse_args()

    if not args.stack and not args.all:
        ap.error("provide a stack name or --all")

    repo_root = args.repo_root or find_repo_root(Path(__file__).parent)

    if args.all:
        for s in STACKS:
            print(f"[{s}]")
            process(s, repo_root, write=not args.stdout)
        return 0

    md = process(args.stack, repo_root, write=not args.stdout)
    if args.stdout:
        print(md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
