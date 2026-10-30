#!/usr/bin/env python3
"""Builds plans/previews/crowd.html: the 3 map sizes for 25 fighters, in 3D, from the real layouts.
Run from the repo root:  python3 tools/crowd_preview.py"""
import subprocess, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
data = subprocess.run(["lune", "run", "tools/crowd_json"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()
tpl = (root / "tools" / "crowd_preview_template.html").read_text()
(root / "plans" / "previews" / "crowd.html").write_text(tpl.replace("/*CROWD_DATA*/null", data))
print("wrote plans/previews/crowd.html")
