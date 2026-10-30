#!/usr/bin/env python3
"""Builds plans/previews/guns.html from the real part lists (WeaponModels.luau via tools/gun_json).
Run from the repo root:  python3 tools/gun_preview.py"""
import subprocess, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
data = subprocess.run(["lune", "run", "tools/gun_json"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()
tpl = (root / "tools" / "gun_preview_template.html").read_text()
(root / "plans" / "previews" / "guns.html").write_text(tpl.replace("/*GUN_DATA*/null", data))
print("wrote plans/previews/guns.html")
