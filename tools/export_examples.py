#!/usr/bin/env python3
"""Recreate the five exact SVG previews locally. Requires only Python and Foundry."""

from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
result = subprocess.run(
    ["forge", "script", "script/RenderExamples.s.sol:RenderExamples", "-vv"],
    cwd=ROOT, text=True, capture_output=True,
)
if result.returncode:
    raise SystemExit(result.stdout + result.stderr)
images = re.findall(r"IMAGE:([a-z-]+):0x([0-9a-fA-F]+)", result.stdout)
assert {name for name, _ in images} == {"shift-lead", "foreman", "supervisor", "kodes", "captain"}
destination = ROOT / "docs/images"
destination.mkdir(parents=True, exist_ok=True)
for name, content in images:
    svg = bytes.fromhex(content)
    (destination / f"{name}.svg").write_bytes(svg)
    print(f"{name}.svg: {len(svg)} bytes")
