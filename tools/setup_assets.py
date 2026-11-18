#!/usr/bin/env python3
"""
Downloads and converts the exact CS2GO + optional Archi assets needed for
Godot 4 into assets/models/ (and assets/audio/archi/ if --archi-sounds is set):
  - Map: Dust2 ONLY (dust2.glb, dust2-physics.glb, dust2-cables.glb)
  - Agents: 1 CT (ctm-sas.glb) + 1 T (tm-phoenix.glb) + view-hands.glb
  - Gloves: default gloves (5027.glb, 5030.glb)
  - Weapons: ALL 34 weapon viewmodels + ALL animation clips (idle, draw, reload,
             shoot1, lookat01 inspect, etc.) + world weapon GLBs
  - Grenades: he, flash, smoke, molotov, incendiary, decoy + clips
  - Animations: locomotion, c4, bayonet, grips

Requirements: git, node (v18+), npm
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
CACHE = os.path.join(TOOLS, ".cache")
ASSETS = os.path.join(ROOT, "assets")


def run(cmd, cwd=None):
    print("+", " ".join(cmd))
    subprocess.check_call(cmd, cwd=cwd)


def ensure_node_deps():
    if not os.path.isdir(os.path.join(TOOLS, "node_modules", "@gltf-transform")):
        run(["npm", "install", "--no-audit", "--no-fund"], cwd=TOOLS)


def sparse_clone_cs2go(dest):
    sparse_paths = [
        "packages/assets/public/models/maps/dust2.glb.gz",
        "packages/assets/public/models/maps/dust2-physics.glb.gz",
        "packages/assets/public/models/maps/dust2-cables.glb.gz",
        "packages/assets/public/models/maps/dust2-bomb.bin.gz",
        "packages/assets/public/models/agents/view-hands.glb",
        "packages/assets/public/models/agents/roster/ctm-sas.glb",
        "packages/assets/public/models/agents/roster/tm-phoenix.glb",
        "packages/assets/public/models/gloves/5027.glb",
        "packages/assets/public/models/gloves/5030.glb",
        "packages/assets/public/models/ak-47.glb",
        "packages/assets/public/models/m4a1_s.glb",
        "packages/assets/public/models/usp-s.glb",
        "packages/assets/public/models/awp.glb",
        "packages/assets/public/models/bayonet.glb",
        "packages/assets/public/models/c4.glb",
        "packages/assets/public/models/viewmodels",
        "packages/assets/public/models/grenades",
        "packages/assets/public/models/animations/locomotion",
        "packages/assets/public/models/animations/c4",
        "packages/assets/public/models/animations/bayonet",
        "packages/assets/public/models/animations/grips",
    ]
    if os.path.isdir(os.path.join(dest, ".git")):
        run(["git", "sparse-checkout", "set", "--no-cone", *sparse_paths], cwd=dest)
        run(["git", "pull", "--ff-only"], cwd=dest)
    else:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        run([
            "git", "clone", "--depth", "1", "--filter=blob:none", "--sparse",
            "https://github.com/3kh0/cs2go.git", dest,
        ])
        run(["git", "sparse-checkout", "set", "--no-cone", *sparse_paths], cwd=dest)


def sparse_clone_archi_sounds(dest):
    if os.path.isdir(os.path.join(dest, ".git")):
        run(["git", "pull", "--ff-only"], cwd=dest)
    else:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        run([
            "git", "clone", "--depth", "1", "--filter=blob:none", "--sparse",
            "https://github.com/ShadowNigth/archi.git", dest,
        ])
        run(["git", "sparse-checkout", "set", "sound"], cwd=dest)


def build_conversion_manifest(src_models, dst_models):
    manifest = []

    def queue(rel_src, rel_dst):
        inp = os.path.join(src_models, rel_src)
        out = os.path.join(dst_models, rel_dst)
        if os.path.isfile(inp):
            manifest.append({"input": inp, "output": out})

    # 1. Dust2 map + physics + cables
    queue("maps/dust2.glb.gz", "maps/dust2.glb")
    queue("maps/dust2-physics.glb.gz", "maps/dust2-physics.glb")
    queue("maps/dust2-cables.glb.gz", "maps/dust2-cables.glb")
    bomb_bin = os.path.join(src_models, "maps/dust2-bomb.bin.gz")
    if os.path.isfile(bomb_bin):
        os.makedirs(os.path.join(dst_models, "maps"), exist_ok=True)
        shutil.copy2(bomb_bin, os.path.join(dst_models, "maps/dust2-bomb.bin.gz"))

    # 2. 1 CT agent + 1 T agent + first-person hands + gloves
    queue("agents/roster/ctm-sas.glb", "agents/ctm-sas.glb")
    queue("agents/roster/tm-phoenix.glb", "agents/tm-phoenix.glb")
    queue("agents/view-hands.glb", "agents/view-hands.glb")
    queue("gloves/5027.glb", "gloves/5027.glb")
    queue("gloves/5030.glb", "gloves/5030.glb")

    # 3. World models
    for wm in ["ak-47.glb", "m4a1_s.glb", "usp-s.glb", "awp.glb", "bayonet.glb", "c4.glb"]:
        queue(wm, wm)

    # 4. ALL 34 weapon viewmodels (prefer non-hd when available since it has no meshopt,
    #    and convert all clips in each weapon's animation subfolder)
    vm_src = os.path.join(src_models, "viewmodels")
    if os.path.isdir(vm_src):
        for entry in sorted(os.listdir(vm_src)):
            full = os.path.join(vm_src, entry)
            if os.path.isfile(full) and entry.endswith(".glb") and not entry.endswith("-hd.glb"):
                queue(f"viewmodels/{entry}", f"viewmodels/{entry}")
            elif os.path.isdir(full):
                for clip in sorted(os.listdir(full)):
                    if clip.endswith(".glb"):
                        queue(f"viewmodels/{entry}/{clip}", f"viewmodels/{entry}/{clip}")

    # 5. Grenades + animations
    for folder in ["grenades", "animations/locomotion", "animations/c4", "animations/bayonet", "animations/grips"]:
        fsrc = os.path.join(src_models, folder)
        if not os.path.isdir(fsrc):
            continue
        for root_dir, _, files in os.walk(fsrc):
            for fn in sorted(files):
                if fn.endswith(".glb"):
                    rel = os.path.relpath(os.path.join(root_dir, fn), src_models).replace("\\", "/")
                    queue(rel, rel)

    return manifest


def main():
    parser = argparse.ArgumentParser(description="Fetch & convert CS2GO assets for Godot 4")
    parser.add_argument("--archi-sounds", action="store_true", help="Also fetch .wav sounds from ShadowNigth/archi")
    args = parser.parse_args()

    ensure_node_deps()

    cs2go_dir = os.path.join(CACHE, "cs2go")
    sparse_clone_cs2go(cs2go_dir)

    src_models = os.path.join(cs2go_dir, "packages/assets/public/models")
    dst_models = os.path.join(ASSETS, "models")
    manifest = build_conversion_manifest(src_models, dst_models)
    manifest_path = os.path.join(CACHE, "convert_manifest.json")
    os.makedirs(CACHE, exist_ok=True)
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"Processing {len(manifest)} GLB files for Godot 4...")
    run(["node", "--max-old-space-size=4096", os.path.join(TOOLS, "convert_glb.mjs"), "--batch", manifest_path])

    if args.archi_sounds:
        archi_dir = os.path.join(CACHE, "archi")
        sparse_clone_archi_sounds(archi_dir)
        dst_archi = os.path.join(ASSETS, "audio", "archi")
        if os.path.isdir(dst_archi):
            shutil.rmtree(dst_archi)
        shutil.copytree(os.path.join(archi_dir, "sound"), dst_archi)
        print("Copied Archi .wav sounds into assets/audio/archi/")

    print("\nDone! Open project.godot in Godot 4.3+ to import all models and play Dust II.")


if __name__ == "__main__":
    main()
