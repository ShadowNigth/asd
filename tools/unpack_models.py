#!/usr/bin/env python3
"""
Optional offline helper: unpacks all .glb.gz models in assets/models/ into
plain .glb files if you want to inspect or re-import them in the Godot Editor.
No internet connection is needed; ModelLoader also loads .glb.gz directly at runtime.
"""
import gzip
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(ROOT, "assets", "models")

count = 0
for dirpath, _, filenames in os.walk(MODELS_DIR):
    for fn in sorted(filenames):
        if not fn.endswith(".glb.gz"):
            continue
        src = os.path.join(dirpath, fn)
        dst = src[:-3]
        with gzip.open(src, "rb") as f_in, open(dst, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
        count += 1

print(f"Unpacked {count} .glb models into {MODELS_DIR}")
