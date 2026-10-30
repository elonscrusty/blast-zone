#!/usr/bin/env python3
"""Builds plans/previews/bench.html from the real part list (tools/bench_json).
Run from the repo root:  python3 tools/bench_preview.py"""
import subprocess, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
data = subprocess.run(["lune", "run", "tools/bench_json"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()
tpl = (root / "tools" / "bench_preview_template.html").read_text()
(root / "plans" / "previews" / "bench.html").write_text(tpl.replace("/*BENCH_DATA*/null", data))
print("wrote plans/previews/bench.html")
