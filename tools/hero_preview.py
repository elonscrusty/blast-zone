#!/usr/bin/env python3
"""Builds plans/previews/heroes.html from the real roster and gun part lists (tools/hero_json).
Run from the repo root:  python3 tools/hero_preview.py"""
import subprocess, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
data = subprocess.run(["lune", "run", "tools/hero_json"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()
tpl = (root / "tools" / "hero_preview_template.html").read_text()
(root / "plans" / "previews" / "heroes.html").write_text(tpl.replace("/*HERO_DATA*/null", data))
print("wrote plans/previews/heroes.html")
