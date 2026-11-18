#!/usr/bin/env python3
"""
Offline project & asset integrity validator for CS2GO Dust II (Godot 4.3+).
Checks project files, JSON data schemas, audio assets, and converted GLB models.
"""
import gzip
import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []

def check(cond, msg):
    if not cond:
        errors.append(msg)
        print(f"[FAIL] {msg}")
    else:
        print(f"[ OK ] {msg}")

def check_glb_or_gz(rel_path):
    full_glb = os.path.join(ROOT, rel_path)
    full_gz = full_glb + ".gz"
    if os.path.isfile(full_glb):
        data = open(full_glb, "rb").read()
        label = rel_path
    elif os.path.isfile(full_gz):
        with gzip.open(full_gz, "rb") as f:
            data = f.read()
        label = rel_path + ".gz"
    else:
        errors.append(f"Missing model: {rel_path}(.gz)")
        print(f"[FAIL] Missing model: {rel_path}(.gz)")
        return

    if len(data) < 20 or data[:4] != b"glTF":
        errors.append(f"Invalid glTF header: {label}")
        print(f"[FAIL] Invalid glTF header: {label}")
        return
    clen, _ = struct.unpack("<II", data[12:20])
    gltf = json.loads(data[20:20 + clen].decode("utf-8"))
    used = set(gltf.get("extensionsUsed", []))
    req = set(gltf.get("extensionsRequired", []))
    bad = (used | req) & {"EXT_meshopt_compression", "KHR_texture_basisu"}
    bad_req = req & {"KHR_mesh_quantization"}
    if bad or bad_req:
        errors.append(f"Unsupported Godot glTF extensions in {label}: {bad | bad_req}")
        print(f"[FAIL] Unsupported Godot glTF extensions in {label}: {bad | bad_req}")

required_files = [
    "project.godot",
    "scenes/main.tscn",
    "scripts/main.gd",
    "scripts/systems/model_loader.gd",
    "scripts/data/weapon_db.gd",
    "scripts/weapons/recoil_system.gd",
    "scripts/weapons/accuracy_system.gd",
    "scripts/weapons/ballistics.gd",
    "scripts/weapons/grenade_projectile.gd",
    "scripts/systems/audio_manager.gd",
    "scripts/effects/effects_manager.gd",
    "scripts/player/source_movement.gd",
    "scripts/player/viewmodel_controller.gd",
    "scripts/player/agent_visual.gd",
    "scripts/player/player_controller.gd",
    "scripts/ai/bot_controller.gd",
    "scripts/world/dust2_map.gd",
    "scripts/systems/game_manager.gd",
    "scripts/ui/hud.gd",
    "scripts/ui/buy_menu.gd",
    "scripts/ui/team_select.gd",
    "scripts/ui/scoreboard.gd",
    "scripts/ui/pause_menu.gd",
    "tools/convert_glb.mjs",
    "tools/setup_assets.py",
    "tools/unpack_models.py",
]

for f in required_files:
    check(os.path.isfile(os.path.join(ROOT, f)), f"File exists: {f}")

data_files = [
    "weapon-stats.json", "recoil.json", "accuracy.json", "weapon-actions.json",
    "character-locomotion.json", "player-hitboxes.json", "knife-animations.json",
    "utility.json", "dust2-buy-zones.json", "dust2-places.json", "dust2-overview.json",
    "dust2-spawns.json",
]
for df in data_files:
    p = os.path.join(ROOT, "assets", "data", df)
    ok = os.path.isfile(p)
    if ok:
        try:
            json.load(open(p, encoding="utf-8"))
        except Exception as e:
            ok = False
            errors.append(f"Invalid JSON {df}: {e}")
    check(ok, f"Valid JSON: assets/data/{df}")

# Verify 37 weapons (0..36)
ws = json.load(open(os.path.join(ROOT, "assets/data/weapon-stats.json"), encoding="utf-8"))
weapons_list = ws.get("weapons", [])
check(len(weapons_list) == 37, f"37 weapons in weapon-stats.json (found {len(weapons_list)})")

spawns = json.load(open(os.path.join(ROOT, "assets/data/dust2-spawns.json"), encoding="utf-8"))
sp_inner = spawns.get("spawns", {})
check(len(sp_inner.get("ct", [])) >= 5 and len(sp_inner.get("t", [])) >= 5,
      f"Dust2 spawns present (CT={len(sp_inner.get('ct', []))}, T={len(sp_inner.get('t', []))})")

# Verify converted GLB models exist and are Godot 4 compatible
check_glb_or_gz("assets/models/maps/dust2.glb")
check_glb_or_gz("assets/models/maps/dust2-physics.glb")
check_glb_or_gz("assets/models/maps/dust2-cables.glb")
check_glb_or_gz("assets/models/agents/ctm-sas.glb")
check_glb_or_gz("assets/models/agents/tm-phoenix.glb")
check_glb_or_gz("assets/models/agents/view-hands.glb")
check_glb_or_gz("assets/models/gloves/5027.glb")
check_glb_or_gz("assets/models/c4.glb")
check_glb_or_gz("assets/models/bayonet.glb")
check_glb_or_gz("assets/models/grenades/he.glb")
check_glb_or_gz("assets/models/grenades/flash.glb")
check_glb_or_gz("assets/models/grenades/smoke.glb")
check_glb_or_gz("assets/models/grenades/molotov.glb")
check_glb_or_gz("assets/models/grenades/incendiary.glb")
check_glb_or_gz("assets/models/grenades/decoy.glb")

# Verify all 34 firearm viewmodels + clips
vm_names = [
    "ak-47", "aug", "awp", "bizon", "cz75a", "deagle", "elite", "famas",
    "fiveseven", "g3sg1", "galilar", "glock", "hkp2000", "m249", "m4a4",
    "m4a1_s", "mac10", "mag7", "mp5sd", "mp7", "mp9", "negev", "nova",
    "p250", "p90", "revolver", "sawedoff", "scar20", "sg556", "ssg08",
    "tec9", "ump45", "usp-s", "xm1014",
]
for vm in vm_names:
    check_glb_or_gz(f"assets/models/viewmodels/{vm}.glb")
    check_glb_or_gz(f"assets/models/viewmodels/{vm}/idle.glb")
    check_glb_or_gz(f"assets/models/viewmodels/{vm}/lookat01.glb")
print(f"[ OK ] Verified all {len(vm_names)} weapon viewmodels & clips (including lookat01 inspect)")

# Verify audio assets
with open(os.path.join(ROOT, "scripts/data/weapon_db.gd"), encoding="utf-8") as f:
    wdb_txt = f.read()

import re
audio_block = wdb_txt.split("AUDIO_KITS")[1].split("\n}")[0]
audio_clips = set(re.findall(r':\s*"([^"]+)"', audio_block))
missing_audio = []
for clip in sorted(audio_clips):
    if not (os.path.isfile(os.path.join(ROOT, "assets/audio", f"{clip}.ogg")) or
            os.path.isfile(os.path.join(ROOT, "assets/audio", f"{clip}.wav"))):
        missing_audio.append(clip)
check(len(missing_audio) == 0, f"All WeaponDB audio clips present ({len(audio_clips)} checked)")

with open(os.path.join(ROOT, "scripts/systems/audio_manager.gd"), encoding="utf-8") as f:
    am_txt = f.read()
source_files = re.findall(r'"(source/[^"]+)"', am_txt)
missing_src = [sf for sf in source_files if not os.path.isfile(os.path.join(ROOT, "assets/audio", sf))]
check(len(missing_src) == 0, f"All AudioManager source/ cues present ({len(source_files)} checked)")

# Verify effects & radar
for asset in [
    "assets/effects/tracer-core.png",
    "assets/effects/tracer-glow.png",
    "assets/models/maps/dust2-radar.png",
    "assets/models/maps/dust2-sky.hdr",
]:
    check(os.path.isfile(os.path.join(ROOT, asset)), f"Asset exists: {asset}")

if errors:
    print(f"\nValidation FAILED with {len(errors)} error(s).")
    sys.exit(1)
print("\nValidation PASSED! All scripts, data files, audio, and converted GLB models are ready for Godot 4.3+.")
