#!/usr/bin/env python3
"""
cstrike_port.py — Port de viewmodels Source 1 (CS2GO de archi) a GoldSrc/Xash3D.

Subcomandos (en orden de pipeline):
  python tools/cstrike_port.py prep       # verifica vendor/ y fuentes
  python tools/cstrike_port.py build      # genera work/<weapon>/*.smd, .bmp, .qc, .mdl
  python tools/cstrike_port.py preview    # renderiza PNGs de la pose bind (verificación visual)
  python tools/cstrike_port.py zip        # empaqueta dist/<weapon>-goldsrc.zip

Todo se ejecuta con el venv de tools/vendor/venv.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VENDOR = REPO_ROOT / 'tools' / 'vendor'
sys.path.insert(0, str(VENDOR))
os.environ.setdefault('NO_BPY', '1')
os.environ.setdefault('STUDIOMDL_BIN', str(VENDOR / 'bin' / 'studiomdl'))

import numpy as np  # noqa: E402

from SourceIO.library.utils import FileBuffer  # noqa: E402
import SourceIO.library.models.mdl.structs.local_animation as _la  # noqa: E402
_la.StudioAnimDesc.read_animations = lambda self, buffer, bones, ani_buffer=None, block_table=None: None
from SourceIO.library.models.mdl.v49 import MdlV49  # noqa: E402
from SourceIO.library.models.mdl.structs.header import MdlHeaderV49  # noqa: E402
from SourceIO.library.models.vtx.v7.vtx import Vtx  # noqa: E402
from SourceIO.library.models.vvd import Vvd  # noqa: E402
from SourceIO.library.source1.vtf import load_texture  # noqa: E402

from anim_decoder import AnimDecoder, decode_animation  # noqa: E402  (tools/anim_decoder.py)

sys.path.insert(0, str(REPO_ROOT / 'tools'))

def _cs2_bind_json(build) -> dict:
    """Pose bind del viewmodel CS2 escalado (mundo gun-units) para blender_export_cp2077."""
    bones = []
    mats = mats_scale_translate(build.mdl.bones, build.scale, build.offset)
    for i, b in enumerate(build.mdl.bones):
        m = mats[i]
        bones.append({'name': b.name, 'parent': int(b.parent_id),
                      'abs_pos': [float(x) for x in m[:3, 3]],
                      'abs_rot': [float(x) for x in m[:3, :3].flatten()]})
    return {'bones': bones, 'scale': float(build.scale), 'offset': [float(x) for x in build.offset]}


def _prepare_cp2077_arms(build, wdir: Path, recipe) -> None:
    """Genera work/<weapon>/cp2077_arms.smd.json + cp_*.bmp (pipeline bpy headless)."""
    bind_path = wdir / 'cs2_bind.json'
    bind_path.write_text(json.dumps(_cs2_bind_json(build)))
    blend = REPO_ROOT / recipe.get('cp2077_blend', 'work/cyberpunk-multirig/Cyberpunk_Rig.blend')
    script = REPO_ROOT / 'tools' / 'blender_export_cp2077.py'
    bpy_py = VENDOR / 'bpy-venv' / 'bin' / 'python'
    stublibs = VENDOR / 'stublibs'
    blpy_libs = next(iter((VENDOR / 'bpy-venv' / 'lib').glob('python*/site-packages/bpy.libs')), None)
    ld = '%s:%s' % (stublibs, blpy_libs) if blpy_libs else str(stublibs)
    env = dict(os.environ, LD_LIBRARY_PATH=ld)
    cmd = [str(bpy_py), str(script), '--blend', str(blend),
           '--cs2bind', str(bind_path), '--out-tris', str(wdir / 'cp2077_arms.smd.json'), '--corr', recipe.get('cp2077_corr', 'full'),
           '--bake-dir', str(wdir)]
    print('+ ' + ' '.join(cmd))
    subprocess.run(cmd, check=True, env=env)
    _cp2077_pngs_to_bmps(wdir)


def load_cp2077_arm_tris(wdir: Path):
    frag = json.loads((wdir / 'cp2077_arms.smd.json').read_text())
    tris = []
    for mat, tri in frag['tris']:
        corners = []
        for item in tri:
            b, p, n, uv = item[0], item[1], item[2], item[3]
            corners.append((int(b), np.array(p, dtype=np.float64),
                            np.array(n, dtype=np.float64), np.array(uv, dtype=np.float64)))
        tris.append((mat, corners))
    return tris, frag


def _cp2077_pngs_to_bmps(wdir: Path) -> None:
    """PNG horneados -> BMP 8 bits (formato GoldSrc); decals -> {BMP azul-clave."""
    from PIL import Image
    frag = json.loads((wdir / 'cp2077_arms.smd.json').read_text())
    for mat, bmp_name in frag['materials'].items():
        png = wdir / (bmp_name.replace('{', '').replace('.bmp', '.png'))
        if not png.exists():
            print('AVISO: falta textura horneada', png)
            continue
        im = Image.open(png).convert('RGBA')
        if max(im.size) > 512:  # límite vanilla GoldSrc
            w, h = im.size
            f = 512 / max(w, h)
            im = im.resize((max(1, int(w * f)), max(1, int(h * f))), Image.LANCZOS)
        if bmp_name.startswith('{'):
            arr = np.array(im)
            key = arr[..., 3] < 128
            rgb = arr[..., :3].copy()
            rgb[key] = (0, 0, 255)
            base = Image.fromarray(rgb).quantize(colors=255, method=Image.MEDIANCUT)
            pal = list(base.getpalette())          # 768 entradas
            pal = pal[:765] + [0, 0, 255] + [0] * (768 - 765)
            indices = np.array(base)
            indices[key] = 255
            out = Image.fromarray(indices.astype(np.uint8), 'P')
            out.putpalette(pal)
            out.save(wdir / bmp_name, 'BMP')
        else:
            rgb = im.convert('RGB')
            if max(rgb.size) > 512:
                rgb = rgb.resize((512, 512), Image.LANCZOS)
            rgb.convert('P', palette=Image.MEDIANCUT, colors=256).save(wdir / bmp_name, 'BMP')
        print('bmp', bmp_name)

# ── Recetas de armas (pilotos) ───────────────────────────────────────────────
WEAPONS = {
    'ak47': {
        'src_dir': '/tmp/archi/CS2GO.Pack.Director.s.Cut.-.Rifles/EXTRAIDOS/m_cs2_ak47',
        'mdl': '#pak/models/weapons/v_rif_ak47.mdl',
        'preview_png': 'preview.png',
        'vtf': 'materials/models/weapons/cs2/weapon_rif_ak47/ak47_c.vtf',
        'sound_dir': '#pak/sound/weapons/ak47',
        'modelname': 'v_ak47.mdl',
        'gun_length_ref': 31.2063,          # largo del AK de referencia (SMD CS 1.5)
        'ref_bbox_center': (0.20115, -20.17045, 2.54755),
        'arm_source': 'cp2077',           # 'cs15' = brazos CS 1.5 trasplantados | 'cp2077' = Gorilla Arms/piel CP2077
        'cp2077_blend': 'work/cyberpunk-multirig/Cyberpunk_Rig.blend',
        'arm_reference_smd': '/tmp/ref/tmp/ref/out71/ak47_template.smd',
        'arm_materials': ('hand.bmp', 'thumb.bmp'),
        'arm_map': {   # hueso CS 1.6 -> hueso CS2 (trasplante de brazos)
            0: 1, 1: 2,                       # raíz/mano trasera -> antebrazo/mano D
            15: 21, 16: 22, 17: 23,           # pulgar D
            2: 24, 3: 25, 4: 26, 5: 26,       # índice D
            6: 27, 7: 28, 8: 29,              # medio D
            9: 30, 10: 31, 11: 32,            # anular D
            12: 33, 13: 34, 14: 35,           # meñique D
            24: 3, 25: 4,                     # raíz/mano delantera -> antebrazo/mano I
            26: 5, 27: 6, 28: 7, 29: 7,       # pulgar I
            30: 8, 31: 9, 32: 10,             # índice I
            33: 11, 34: 12, 35: 13,           # medio I
            36: 14, 37: 15, 38: 16,           # anular I
            39: 17, 40: 18, 41: 19,           # meñique I
        },
        # secuencias GoldSrc (orden del DLL CS 1.x) -> (animdesc CS2, fps)
        'sequences': [
            ('idle1', '@ak47_idle', 30, None),
            ('reload', '@ak47_reload', 30, [(5004, 13, 'weapons/ak47_clipout.wav'),
                                             (5004, 57, 'weapons/ak47_clipin.wav')]),
            ('draw',   '@ak47_draw', 30, [(5004, 11, 'weapons/ak47_boltpull.wav')]),
            ('shoot1', '@ak47_fire1', 30, [(5001, 0, '22')]),
            ('shoot2', '@ak47_fire2', 30, [(5001, 0, '22')]),
            ('shoot3', '@ak47_fire3', 30, [(5001, 0, '22')]),
        ],
        'attachments': [('muzzle', 49), ('bolt', 52)],
        'sounds': {  # cs2 -> GoldSrc (22050 Hz 16-bit mono)
            'cs2_ak47_01.wav': 'ak47_01.wav',
            'cs2_ak47_02.wav': 'ak47_02.wav',
            'cs2_ak47_03.wav': 'ak47_03.wav',
            'cs2_ak47_distant.wav': 'ak47_distant.wav',
            'ak47-1.wav': 'ak47_01.wav',   # reemplazo del sonido stock (DLL hardcodea ak47-1/2.wav)
            'ak47-2.wav': 'ak47_02.wav',
        },
    },
}

# ─────────────────────────────────────────────────────────────────────────────
#  Utilidades matemáticas
# ─────────────────────────────────────────────────────────────────────────────

def quat_to_matrix(q) -> np.ndarray:
    x, y, z, w = q
    n = x * x + y * y + z * z + w * w
    s = 2.0 / max(n, 1e-12)
    xx, yy, zz = x * x * s, y * y * s, z * z * s
    xy, xz, yz = x * y * s, x * z * s, y * z * s
    wx, wy, wz = w * x * s, w * y * s, w * z * s
    m = np.eye(3)
    m[0, 0] = 1 - (yy + zz); m[0, 1] = xy - wz;     m[0, 2] = xz + wy
    m[1, 0] = xy + wz;       m[1, 1] = 1 - (xx + zz); m[1, 2] = yz - wx
    m[2, 0] = xz - wy;       m[2, 1] = yz + wx;       m[2, 2] = 1 - (xx + yy)
    return m


def matrix_to_euler_goldsrc(m: np.ndarray) -> np.ndarray:
    """Inversa de R = Rz(ez)·Ry(ey)·Rx(ex). Radianes."""
    r20 = m[2, 0]
    ey = math.atan2(-r20, math.hypot(m[2, 1], m[2, 2]))
    ex = math.atan2(m[2, 1], m[2, 2])
    ez = math.atan2(m[1, 0], m[0, 0])
    return np.array([ex, ey, ez], dtype=np.float64)


def euler_goldsrc_to_matrix(e) -> np.ndarray:
    ex, ey, ez = e
    Rx = np.array([[1, 0, 0], [0, math.cos(ex), -math.sin(ex)], [0, math.sin(ex), math.cos(ex)]])
    Ry = np.array([[math.cos(ey), 0, math.sin(ey)], [0, 1, 0], [-math.sin(ey), 0, math.cos(ey)]])
    Rz = np.array([[math.cos(ez), -math.sin(ez), 0], [math.sin(ez), math.cos(ez), 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def bones_local_matrix(pos, quat) -> np.ndarray:
    m = np.eye(4)
    m[:3, :3] = quat_to_matrix(np.asarray(quat, dtype=np.float64))
    m[:3, 3] = np.asarray(pos, dtype=np.float64)
    return m


def abs_bind_mats(bones):
    mats = []
    for b in bones:
        local = bones_local_matrix(b.position, b.quat)
        mats.append(local if b.parent_id < 0 else mats[b.parent_id] @ local)
    return mats


def mats_scale_translate(bones, scale, offset: np.ndarray):
    """Matrices world con traslación local escalada y `offset` sumado a LAS RAÍCES."""
    mats = []
    for i, b in enumerate(bones):
        lp = np.asarray(b.position, dtype=np.float64) * scale
        if b.parent_id < 0:
            lp = lp + offset
        local = bones_local_matrix(lp, b.quat)
        mats.append(local if b.parent_id < 0 else mats[b.parent_id] @ local)
    return mats


# ─────────────────────────────────────────────────────────────────────────────
#  SMD: parseo de referencia / escritura
# ─────────────────────────────────────────────────────────────────────────────

NODE_RE = re.compile(r'^\s*(\d+)\s+"([^"]+)"\s+(-?\d+)\s*$', re.M)
FRAME_RE = re.compile(
    r'^\s*(\d+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s*$', re.M)
VERTEX_RE = re.compile(
    r'^\s*(\d+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s*$')


def parse_smd(path: Path):
    txt = path.read_text(encoding='utf-8', errors='replace')
    nodes_sec = txt.split('nodes', 1)[1].split('end', 1)[0]
    skel_sec = txt.split('skeleton', 1)[1].split('end', 1)[0]
    tri_sec = txt.split('triangles', 1)[1]
    names, parents = {}, {}
    for idx, name, parent in NODE_RE.findall(nodes_sec):
        names[int(idx)] = name
        parents[int(idx)] = int(parent)
    # primer bloque de pose
    time_blocks = FRAME_RE.findall(skel_sec)
    bone_count = len(names)
    bind_rows = []
    for i, m in enumerate(re.finditer(r'time\s+(\d+)', skel_sec)):
        assert int(m.group(1)) == 0, 'solo soportamos el frame de pose (time 0)'
        break
    rows = FRAME_RE.findall(skel_sec)[:bone_count]
    bind = []
    for i in range(bone_count):
        tok = rows[i]
        pos = np.array([float(x) for x in tok[1:4]])
        eul = np.array([float(x) for x in tok[4:7]])
        bind.append((pos, eul))
    # triángulos
    tris = []  # (material, [3](bone, pos(3), nrm(3), uv(2)))
    cur_mat, cur = None, []
    for raw in tri_sec.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.lower().endswith('.bmp'):
            if len(cur) == 3:
                tris.append((cur_mat, cur))
            cur, cur_mat = [], line
            continue
        m = VERTEX_RE.match(line)
        if m:
            bone = int(m.group(1))
            pos = np.array([float(x) for x in m.group(2, 3, 4)])
            nrm = np.array([float(x) for x in m.group(5, 6, 7)])
            uv = np.array([float(m.group(8)), float(m.group(9))])
            cur.append((bone, pos, nrm, uv))
            if len(cur) == 3:
                tris.append((cur_mat, cur))
                cur = []
    if len(cur) == 3:
        tris.append((cur_mat, cur))
    return names, parents, bind, tris


def smd_nodes_block(bones) -> str:
    lines = ['nodes']
    for i, b in enumerate(bones):
        lines.append('  %d "%s" %d' % (i, b.name.replace('"', "'"), b.parent_id))
    lines.append('end')
    return '\n'.join(lines) + '\n'


def smd_skeleton_block(bones, scale, offset, per_frame=None):
    """per_frame: lista opcional de (pos(3), quat(4)) por hueso predecodificados."""
    out = ['skeleton']
    if per_frame is None:
        out.append('  time 0')
        for i, b in enumerate(bones):
            lp = np.asarray(b.position, dtype=np.float64) * scale + (offset if b.parent_id < 0 else np.zeros(3))
            rot = quat_to_matrix(b.quat)
            e = matrix_to_euler_goldsrc(rot)
            out.append('    %d %.6f %.6f %.6f %.6f %.6f %.6f' % (i, lp[0], lp[1], lp[2], e[0], e[1], e[2]))
    else:
        pass  # los anims se escriben frame a frame en otro sitio
    out.append('end')
    return '\n'.join(out) + '\n'


def winding_fix(corner_pos, corner_nrm):
    """Devuelve una permutación (0..2) que alinea winding con la normal media."""
    e1, e2 = corner_pos[1] - corner_pos[0], corner_pos[2] - corner_pos[0]
    fn = np.cross(e1, e2)
    if np.linalg.norm(fn) < 1e-10:
        return (0, 1, 2)
    navg = corner_nrm[0] + corner_nrm[1] + corner_nrm[2]
    return (0, 1, 2) if np.dot(fn, navg) >= 0 else (0, 2, 1)


# ─────────────────────────────────────────────────────────────────────────────
#  Construcción del modelo
# ─────────────────────────────────────────────────────────────────────────────

class WeaponBuild:
    def __init__(self, recipe):
        self.recipe = recipe
        src = Path(recipe['src_dir'])
        self.src_mdl = src / recipe['mdl']
        self.src = src
        self.mdl = MdlV49.from_buffer(FileBuffer(str(self.src_mdl)))
        self.vtx = Vtx.from_buffer(FileBuffer(str(self.src_mdl.with_suffix('.dx90.vtx'))))
        self.vvd = Vvd.from_buffer(FileBuffer(str(self.src_mdl.with_suffix('.vvd'))))
        self.header = MdlHeaderV49.from_buffer(FileBuffer(str(self.src_mdl)))
        self.anim_decoder = AnimDecoder(
            self.src_mdl, self.header.local_animation_offset, self.header.local_animation_count,
            self.header.anim_block_offset, self.header.anim_block_count)
        self.bind = [(np.array(b.position, dtype=np.float64), np.array(b.quat, dtype=np.float64))
                     for b in self.mdl.bones]
        self.anm_indices = {d.name: d for d in self.anim_decoder.descs}
        self.frames = {}
        for d in self.anim_decoder.descs:
            f = decode_animation(self.anim_decoder, d, len(self.mdl.bones))
            # relleno por componente: pos/rot sin datos -> pose bind de Source
            for bi in range(len(self.mdl.bones)):
                bp, bq = self.bind[bi]
                pos_missing = ~np.any(f[:, bi, 0:3] != 0.0, axis=1)
                rot_missing = ~np.any(f[:, bi, 3:7] != 0.0, axis=1)
                f[pos_missing, bi, 0:3] = bp
                f[rot_missing, bi, 3:7] = bq
            self.frames[d.name] = f

        self.scale, self.offset = self._compute_similarity()
        self.world_mats = mats_scale_translate(self.mdl.bones, self.scale, self.offset)
        self.report_fit = True

    # -- geometría del arma
    def gun_mesh(self):
        vvd_verts = self.vvd.lod_data[0]
        positions = vvd_verts['vertex'].astype(np.float64)
        normals = vvd_verts['normal'].astype(np.float64)
        uvs = vvd_verts['uv'].astype(np.float64)
        bone_ids = vvd_verts['bone_id']
        weights = vvd_verts['weight']
        dom = np.argmax(weights, axis=1)
        dominant = bone_ids[np.arange(len(bone_ids)), dom].astype(np.int64)

        tris = []
        for vtx_bp, bp in zip(self.vtx.body_parts, self.mdl.body_parts):
            for vtx_model, model in zip(vtx_bp.models, bp.models):
                if model.vertex_count == 0:
                    continue
                v_off = model.vertex_offset
                lod0 = vtx_model.model_lods[0]
                for vtx_mesh, mesh in zip(lod0.meshes, model.meshes):
                    for sg in vtx_mesh.strip_groups:
                        offset = 0
                        strips = sg.strips
                        sg_indices = sg.indices
                        sg_orig = sg.vertexes['original_mesh_vertex_index'].reshape(-1).astype(np.uint32)
                        # sg.indices indexa vértices del strip group (orden de strips concatenados)
                        base = 0
                        for t in range(0, len(sg_indices), 3):
                            tri = [int(v_off + sg_orig[int(sg_indices[t + k])]) for k in range(3)]
                            tris.append(tri)
        return positions, normals, uvs, dominant, tris

    def _compute_similarity(self):
        positions = self.vvd.lod_data[0]['vertex'].astype(np.float64)
        span = (positions.max(axis=0) - positions.min(axis=0))
        axis = int(np.argmax(span))
        scale = self.recipe['gun_length_ref'] / span[axis]
        cs2_center = (positions.max(axis=0) + positions.min(axis=0)) / 2.0
        ref_center = np.array(self.recipe['ref_bbox_center'])
        offset = ref_center - scale * cs2_center
        return scale, offset

    def scaled_points(self, pts):
        return self.scale * pts + self.offset

    # -- brazos de referencia -> espacio CS2 escalado
    def arm_fit(self):
        """Kabsch entre las articulaciones del ref y las del CS2 escalado.

        Devuelve (R, s, t) con p_cs2 ≈ s·R·p_ref + t, y el mapa de huesos usado.
        """
        path = Path(self.recipe['arm_reference_smd'])
        names, parents, bind, tris = parse_smd(path)
        bmap = self.recipe['arm_map']
        n = len(names)
        locals_ = []
        for i in range(n):
            pos, eul = bind[i]
            l = np.eye(4)
            l[:3, :3] = euler_goldsrc_to_matrix(eul)
            l[:3, 3] = pos
            locals_.append(l)
        abs_ = []
        for i in range(n):
            pr = parents[i]
            abs_.append(locals_[i] if pr < 0 else abs_[pr] @ locals_[i])

        P_ref, P_cs2, joint_map = [], [], []
        for rb, nb in bmap.items():
            P_ref.append(abs_[rb][:3, 3])
            P_cs2.append(self.world_mats[nb][:3, 3])
            joint_map.append((rb, nb))
        P_ref = np.array(P_ref)
        P_cs2 = np.array(P_cs2)
        c_ref, c_cs2 = P_ref.mean(0), P_cs2.mean(0)
        A = P_ref - c_ref
        B = P_cs2 - c_cs2
        H = A.T @ B
        U, S, Vt = np.linalg.svd(H)
        d = np.sign(np.linalg.det(Vt.T @ U.T))
        D = np.diag([1.0, 1.0, d])
        R = Vt.T @ D @ U.T
        scale = np.trace(D @ np.diag(S)) / (A * A).sum()
        t = c_cs2 - scale * R @ c_ref
        residual = np.linalg.norm((scale * R @ P_ref.T).T + t - P_cs2, axis=1)
        return R, scale, t, residual, bmap, tris, names, parents, abs_

    @staticmethod
    def _bone_directions(names, parents, abs_pos, bone_ids):
        """Dirección bind de cada hueso: hacia el centroide de sus hijos (o la suya propia)."""
        children = {i: [] for i in bone_ids}
        for i in bone_ids:
            pr = parents[i]
            if pr in children:
                children[pr].append(i)
        dirs = {}
        for i in bone_ids:
            kids = children[i]
            if kids:
                c = np.mean([abs_pos[k] for k in kids], axis=0)
                d = c - abs_pos[i]
            else:
                pr = parents[i]
                d = abs_pos[i] - (abs_pos[pr] if pr >= 0 else np.zeros(3))
            n = np.linalg.norm(d)
            dirs[i] = d / n if n > 1e-8 else np.array([1.0, 0.0, 0.0])
        return dirs

    @staticmethod
    def _rotation_between(a, b):
        a = a / max(np.linalg.norm(a), 1e-12)
        b = b / max(np.linalg.norm(b), 1e-12)
        v = np.cross(a, b)
        c = float(np.dot(a, b))
        if c > 0.999999:
            return np.eye(3)
        if c < -0.999999:
            axis = np.cross(a, np.array([1.0, 0, 0]))
            if np.linalg.norm(axis) < 1e-6:
                axis = np.cross(a, np.array([0, 1.0, 0]))
            axis /= np.linalg.norm(axis)
            return -np.eye(3) + 2 * np.outer(axis, axis)
        vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
        return np.eye(3) + vx + vx @ vx * (1.0 / (1.0 + c))

    def arm_mesh(self, fit_out=None):
        path = Path(self.recipe['arm_reference_smd'])
        names, parents, bind, tris = parse_smd(path)
        bmap = self.recipe['arm_map']
        keep = set(self.recipe['arm_materials'])
        n = len(names)
        locals_ = []
        for i in range(n):
            pos, eul = bind[i]
            l = np.eye(4)
            l[:3, :3] = euler_goldsrc_to_matrix(eul)
            l[:3, 3] = pos
            locals_.append(l)
        abs16 = []
        for i in range(n):
            pr = parents[i]
            abs16.append(locals_[i] if pr < 0 else abs16[pr] @ locals_[i])
        abs16_pos = [m[:3, 3] for m in abs16]
        abs2_pos = [self.world_mats[i][:3, 3] for i in range(len(self.mdl.bones))]
        ref_ids = sorted(bmap)
        dst_ids = [bmap[i] for i in ref_ids]
        dir16 = self._bone_directions(names, parents, abs16_pos, ref_ids)
        dir2 = self._bone_directions({i: self.mdl.bones[i].name for i in range(len(self.mdl.bones))},
                                     {i: self.mdl.bones[i].parent_id for i in range(len(self.mdl.bones))},
                                     abs2_pos, dst_ids)
        corr = {}
        for rb in ref_ids:
            corr[rb] = self._rotation_between(dir16[rb], dir2[bmap[rb]])

        tris_out = []
        for mat, tri in tris:
            if mat.lower() not in keep:
                continue
            corners = []
            ok = True
            for bone, pos, nrm, uv in tri:
                if bone not in bmap:
                    ok = False
                    break
                nb = bmap[bone]
                R = corr[bone]
                # posición y normal en espacio del mundo ref -> mundo cs2
                world = abs2_pos[nb] + R @ (pos - abs16_pos[bone])
                nworld = R @ nrm
                nworld /= max(np.linalg.norm(nworld), 1e-12)
                corners.append((nb, world, nworld, uv))
            if ok and len(corners) == 3:
                tris_out.append((mat.lower(), corners))
        if fit_out is not None:
            fit_out.update(mode='direction-alignment')
        return tris_out

    # -- escritura de SMDs
    def write_reference_smd(self, out_path: Path):
        positions, normals, uvs, dominant, tris = self.gun_mesh()
        positions = self.scaled_points(positions)
        arm_source = self.recipe.get('arm_source', 'cs15')
        wdir = Path(self.recipe.get('work_dir', str(out_path.parent)))
        mat_bmp = {}
        if arm_source == 'cp2077':
            arm_tris, frag = load_cp2077_arm_tris(wdir)
            mat_bmp = frag['materials']
            fit = {'mode': 'cp2077-full-orientation'}
        else:
            fit = {}
            arm_tris = self.arm_mesh(fit)
        if getattr(self, 'report_fit', False):
            self.fit = fit

        with out_path.open('w', encoding='utf-8', newline='\n') as f:
            f.write('version 1\n')
            f.write(smd_nodes_block(self.mdl.bones))
            f.write(smd_skeleton_block(self.mdl.bones, self.scale, self.offset))
            f.write('triangles\n')

            def emit_tri(mat, corners, uv_flip):
                pos3 = [c[1] for c in corners]
                nrm3 = [c[2] for c in corners]
                order = winding_fix(pos3, nrm3)
                f.write(mat + '\n')
                for k in order:
                    bone, pos, nrm, uv = corners[k]
                    v = 1.0 - uv[1] if uv_flip else uv[1]
                    f.write('    %i %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f\n' % (
                        bone, pos[0], pos[1], pos[2], nrm[0], nrm[1], nrm[2], uv[0], v))

            # arma: single bone por esquina (dominante)
            for tri in tris:
                corners = []
                for vi in tri:
                    corners.append((int(dominant[vi]), positions[vi], normals[vi], uvs[vi]))
                emit_tri('ak47.bmp', corners, uv_flip=True)
            for mat, corners in arm_tris:
                emit_tri(mat_bmp.get(mat, mat), corners, uv_flip=False)
            f.write('end\n')

    def write_anim_smd(self, out_path: Path, anim_name: str):
        frames = self.frames[anim_name]
        bones = self.mdl.bones
        roots = [i for i, b in enumerate(bones) if b.parent_id < 0]
        with out_path.open('w', encoding='utf-8', newline='\n') as f:
            f.write('version 1\n')
            f.write(smd_nodes_block(bones))
            f.write('skeleton\n')
            for fid in range(frames.shape[0]):
                f.write('  time %d\n' % fid)
                for i, b in enumerate(bones):
                    lp = frames[fid, i, 0:3] * self.scale
                    if i in roots:
                        lp = lp + self.offset
                    e = matrix_to_euler_goldsrc(quat_to_matrix(frames[fid, i, 3:7]))
                    f.write('    %i %.6f %.6f %.6f %.6f %.6f %.6f\n' % (
                        i, lp[0], lp[1], lp[2], e[0], e[1], e[2]))
            f.write('end\n')

    # -- texturas / sonidos / qc
    def export_texture(self, out_bmp: Path, size: int = 512):
        from PIL import Image
        with open(self.src / self.recipe['vtf'], 'rb') as fh:
            rgba, height, width = load_texture(fh)
        if rgba is None:
            raise RuntimeError('No se pudo decodificar el VTF')
        arr = np.asarray(rgba, dtype=np.float32).reshape(height, width, 4)
        arr = np.clip(arr[..., :3] * 255.0, 0, 255).astype(np.uint8)
        im = Image.fromarray(arr, 'RGB').resize((size, size), Image.LANCZOS)
        im = im.convert('P', palette=Image.ADAPTIVE, colors=256)
        if out_bmp.suffix.lower() != '.bmp':
            out_bmp = out_bmp.with_suffix('.bmp')
        im.save(out_bmp, 'BMP')
        return out_bmp

    def export_sounds(self, out_dir: Path):
        out_dir.mkdir(parents=True, exist_ok=True)
        src_dir = self.src / self.recipe['sound_dir']
        for out_name, src_name in self.recipe['sounds'].items():
            convert_wav(src_dir / src_name, out_dir / out_name)

    def write_qc(self, path: Path, cdir: Path, smd_dir: Path):
        r = self.recipe
        lines = [
            '// Generado por tools/cstrike_port.py — NO editar a mano',
            '$modelname "%s"' % r['modelname'],
            '$cd "%s"' % smd_dir,
            '$cdtexture "%s"' % cdir,
            '$body studio "%s"' % (smd_dir / 'ak47_reference.smd').name.replace('.smd', ''),
        ]
        for att_name, bone in r['attachments']:
            lines.append('$attachment %d "%s" 0 0 0' % (
                0 if att_name == 'muzzle' else 1,
                self.mdl.bones[bone].name))
        for seq_name, cs2_anim, fps, events in r['sequences']:
            if events:
                lines.append('$sequence %s {' % seq_name)
                lines.append('    "%s"' % cs2_anim.lstrip('@'))
                for ev, fr, opt in events:
                    lines.append('    { event %d %d "%s" }' % (ev, fr, opt))
                lines.append('    fps %d' % fps)
                lines.append('}')
            else:
                lines.append('$sequence %s "%s" fps %d' % (seq_name, cs2_anim.lstrip('@'), fps))
        # anims: studiomdl toma nombre base sin @
        path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def convert_wav(src: Path, dst: Path):
    """CS2 wav (44.1 kHz, 16-bit, estéreo/mono) -> 22050 Hz 16-bit mono PCM."""
    try:
        from scipy.signal import resample_poly
    except ImportError:
        resample_poly = None
    with wave.open(str(src), 'rb') as w:
        ch, sw, fr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
        assert sw == 2, 'se esperaba s16'
        data = np.frombuffer(raw, dtype='<i2').astype(np.float64)
        if ch == 2:
            data = data.reshape(-1, 2).mean(axis=1)
        elif ch != 1:
            raise ValueError('canales no soportados: %d' % ch)
    if fr == 44100:
        if resample_poly is not None:
            data = resample_poly(data, 1, 2)
        else:  # decimación con filtro FIR sencillo
            kernel = np.array([0.25, 0.5, 0.25]) * 2
            data = np.convolve(data, kernel, mode='same')[::2]
    elif fr != 22050:
        raise ValueError('frecuencia inesperada: %d' % fr)
    data = np.clip(data, -32768, 32767).astype('<i2')
    with wave.open(str(dst), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(data.tobytes())


# ─────────────────────────────────────────────────────────────────────────────
#  CLI
# ─────────────────────────────────────────────────────────────────────────────

def work_dir(weapon: str) -> Path:
    return REPO_ROOT / 'work' / weapon


def cmd_build(args):
    recipe = WEAPONS[args.weapon]
    build = WeaponBuild(recipe)
    wdir = work_dir(args.weapon)
    wdir.mkdir(parents=True, exist_ok=True)
    recipe['work_dir'] = str(wdir)
    if recipe.get('arm_source') == 'cp2077':
        _prepare_cp2077_arms(build, wdir, recipe)
    # SMDs
    ref_smd = wdir / 'ak47_reference.smd'
    build.write_reference_smd(ref_smd)
    for seq_name, cs2_anim, fps, _ in recipe['sequences']:
        anim_smd = wdir / (cs2_anim.lstrip('@') + '.smd')
        build.write_anim_smd(anim_smd, cs2_anim)
    # textura
    bmp = build.export_texture(wdir / 'ak47.bmp', size=args.texture_size)
    # sonidos
    build.export_sounds(wdir / 'sound')
    # textura de brazos (BMP 8 bits del modelo de referencia)
    if recipe.get('arm_source', 'cs15') == 'cs15':
        for arm_bmp in ('hand.bmp', 'thumb.bmp'):
            src_bmp = Path(recipe['arm_reference_smd']).parent / 'maps_8bit' / arm_bmp
            shutil.copy(src_bmp, wdir / arm_bmp)
    # QC
    build.write_qc(wdir / 'ak47.qc', wdir, wdir)
    if not args.no_compile:
        studiomdl = os.environ.get('STUDIOMDL_BIN') or str(VENDOR / 'bin' / 'studiomdl')
        proc = subprocess.run([studiomdl, '-i', 'ak47.qc'], cwd=str(wdir),
                              capture_output=True, text=True)
        print(proc.stdout)
        if proc.returncode != 0 or 'ERROR' in proc.stdout.upper():
            print(proc.stderr)
            raise SystemExit('studiomdl falló (código %d)' % proc.returncode)
        print('compilado:', wdir / 'v_ak47.mdl')
    if getattr(build, 'fit', None):
        print('arm fit:', build.fit)
    print('scale', build.scale, 'offset', build.offset)
    print('build dir:', wdir)


def _parse_smd_tris(path: Path):
    """Lee el SMD de referencia y devuelve (lista de triángulos (bone,pos3,nrm3,uv2))."""
    txt = path.read_text(encoding='utf-8', errors='replace')
    body = txt.split('triangles', 1)[1]
    tris = []
    cur = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line or line == 'end':
            continue
        p = line.split()
        if p[0].isdigit() and len(p) == 9:
            bone = int(p[0])
            pos = np.array([float(x) for x in p[1:4]])
            nrm = np.array([float(x) for x in p[4:7]])
            uv = np.array([float(p[7]), float(p[8])])
            cur.append((bone, pos, nrm, uv))
            if len(cur) == 3:
                tris.append(cur)
                cur = []
    return tris


def render_smd(path: Path, out_png: Path, camera: str = 'side', size=(900, 650),
               cull_backfaces: bool = True, arm_color=(210, 170, 125), gun_color=(70, 72, 78)):
    """Rasterizador software mínimo para verificación visual del bind pose."""
    from PIL import Image, ImageDraw

    tris = _parse_smd_tris(path)
    if not tris:
        raise RuntimeError('SMD sin triángulos: %s' % path)
    all_pts = np.array([c[1] for t in tris for c in t])
    center = (all_pts.max(0) + all_pts.min(0)) / 2.0
    extent = (all_pts.max(0) - all_pts.min(0)).max()

    if camera == 'side':      # mirando desde +X
        axes = (np.array([0, -1, 0]), np.array([0, 0, 1]))   # u(derecho) , v(arriba)
        view_dir = np.array([1.0, 0, 0])
    elif camera == 'front':   # mirando desde -Y (hacia el hocico)
        axes = (np.array([1, 0, 0]), np.array([0, 0, 1]))
        view_dir = np.array([0, -1.0, 0])
    elif camera == 'top':
        axes = (np.array([1, 0, 0]), np.array([0, -1, 0]))
        view_dir = np.array([0, 0, 1.0])
    else:
        raise ValueError(camera)
    u_ax, v_ax = axes

    def project(p):
        d = p - center
        return np.array([np.dot(d, u_ax), np.dot(d, v_ax)]), np.dot(d, view_dir)

    scale = (min(size) * 0.42) / (extent / 2.0)
    img = Image.new('RGB', size, (24, 24, 28))
    dr = ImageDraw.Draw(img)

    def to_px(uv2):
        return (size[0] / 2 + uv2[0] * scale, size[1] / 2 - uv2[1] * scale)

    # painter: de lejos a cerca
    keyed = []
    for t in tris:
        pts = [c[1] for c in t]
        nrm = [c[2] for c in t]
        uvd, depths = [], []
        for p, n in zip(pts, nrm):
            uv2, dep = project(p)
            uvd.append(uv2)
            depths.append(dep)
        keyed.append((float(np.mean(depths)), uvd, nrm, t))
    keyed.sort(key=lambda x: x[0])

    n_culled = 0
    for depth, uvd, nrm, t in keyed:
        p3 = [c[1] for c in t]
        fn = np.cross(p3[1] - p3[0], p3[2] - p3[0])
        navg = nrm[0] + nrm[1] + nrm[2]
        # culling por cara orientada a la cámara
        facing = np.dot(fn, view_dir) >= 0
        # luz frontal tipo headlight + relleno cenital
        navg = navg / max(np.linalg.norm(navg), 1e-12)
        shade = 0.45 + 0.45 * max(0.0, float(np.dot(navg, view_dir))) + 0.25 * max(0.0, float(navg[2] if len(navg) > 2 else 0.0))
        shade = min(1.0, shade)
        is_arm = (t[0][0] < 48)  # vértices del arma usan huesos >= 48 (armas: miembros 1..41)
        base = arm_color if is_arm else gun_color
        col = tuple(int(min(255, c * shade)) for c in base)
        if cull_backfaces and not facing:
            n_culled += 1
            continue
        poly = [to_px(u) for u in uvd]
        dr.polygon(poly, fill=col)
    dr.text((8, 8), '%s — triángulos traseros culled: %d/%d' % (camera, n_culled, len(keyed)),
            fill=(200, 200, 200))
    img.save(out_png)
    print('guardado', out_png, '| culled', n_culled, '/', len(keyed))


def parse_smd_skeleton_frames(path: Path):
    """Devuelve dict frame -> lista (pos, euler) por hueso (orden nodes)."""
    txt = path.read_text(encoding='utf-8', errors='replace')
    nodes_sec = txt.split('nodes', 1)[1].split('end', 1)[0]
    n_bones = len(re.findall(r'^\s*\d+\s+"', nodes_sec, re.M)) == 0 and None or len(re.findall(r'"[^"]+"', nodes_sec))
    skel = txt.split('skeleton', 1)[1].split('end', 1)[0]
    frames = {}
    cur_time = None
    cur_rows = []
    for raw in skel.splitlines():
        line = raw.strip()
        m = re.match(r'^time\s+(\d+)$', line)
        if m:
            if cur_time is not None:
                frames[cur_time] = cur_rows
            cur_time = int(m.group(1))
            cur_rows = []
            continue
        m2 = re.match(r'^(\d+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)\s+([-\d.e]+)$', line)
        if m2:
            tok = m2.groups()
            pos = np.array([float(tok[1]), float(tok[2]), float(tok[3])])
            eul = np.array([float(tok[4]), float(tok[5]), float(tok[6])])
            cur_rows.append((pos, eul))
    if cur_time is not None:
        frames[cur_time] = cur_rows
    return frames


def render_anim_frame(ref_smd: Path, anim_smd: Path, frame: int, out_png: Path,
                      camera: str = 'side', size=(900, 650)):
    tris = _parse_smd_tris(ref_smd)
    bind_frames = parse_smd_skeleton_frames(ref_smd)
    nodes_sec = ref_smd.read_text(encoding='utf-8', errors='replace').split('nodes', 1)[1].split('end', 1)[0]
    parents = [int(m.group(3)) for m in re.finditer(r'^\s*(\d+)\s+"([^"]+)"\s+(-?\d+)', nodes_sec, re.M)]
    n_bones = len(parents)

    def build_mats(rows):
        locals_ = []
        for i in range(n_bones):
            pos, eul = rows[i]
            l = np.eye(4)
            l[:3, :3] = euler_goldsrc_to_matrix(eul)
            l[:3, 3] = pos
            locals_.append(l)
        abs_ = []
        for i in range(n_bones):
            pr = parents[i]
            abs_.append(locals_[i] if pr < 0 else abs_[pr] @ locals_[i])
        return abs_

    abs_bind = build_mats(bind_frames[0])
    frames = parse_smd_skeleton_frames(anim_smd)
    if frame not in frames:
        raise SystemExit('frame %d no existe en %s (0..%d)' % (frame, anim_smd, max(frames)))
    abs_anim = build_mats(frames[frame])
    delta = [abs_anim[i] @ np.linalg.inv(abs_bind[i]) for i in range(n_bones)]
    delta_rot = [d[:3, :3] for d in delta]

    from PIL import Image, ImageDraw
    all_pts = []
    moved = []
    for t in tris:
        corners = []
        for bone, pos, nrm, uv in t:
            wp = delta[bone] @ np.array([*pos, 1.0])
            wn = delta_rot[bone] @ nrm
            corners.append((bone, wp[:3], wn, uv))
        moved.append(corners)
        all_pts.extend(c[1] for c in corners)
    all_pts = np.array(all_pts)
    center = (all_pts.max(0) + all_pts.min(0)) / 2.0
    extent = (all_pts.max(0) - all_pts.min(0)).max()

    if camera == 'side':
        axes = (np.array([0, -1, 0]), np.array([0, 0, 1]))
        view_dir = np.array([1.0, 0, 0])
    elif camera == 'front':
        axes = (np.array([1, 0, 0]), np.array([0, 0, 1]))
        view_dir = np.array([0, -1.0, 0])
    else:
        axes = (np.array([1, 0, 0]), np.array([0, -1, 0]))
        view_dir = np.array([0, 0, 1.0])
    u_ax, v_ax = axes

    def project(p):
        d = p - center
        return np.array([np.dot(d, u_ax), np.dot(d, v_ax)]), np.dot(d, view_dir)

    scale = (min(size) * 0.42) / (extent / 2.0)
    img = Image.new('RGB', size, (24, 24, 28))
    dr = ImageDraw.Draw(img)

    def to_px(u):
        return (size[0] / 2 + u[0] * scale, size[1] / 2 - u[1] * scale)

    keyed = []
    for corners in moved:
        uvd, depths = [], []
        for bone, pos, nrm, uv in corners:
            u, dep = project(pos)
            uvd.append(u)
            depths.append(dep)
        keyed.append((float(np.mean(depths)), uvd, corners))
    keyed.sort(key=lambda x: x[0])
    light = np.array([0.5, 0.6, 0.8])
    light /= np.linalg.norm(light)
    n_culled = 0
    for depth, uvd, corners in keyed:
        p3 = [c[1] for c in corners]
        fn = np.cross(p3[1] - p3[0], p3[2] - p3[0])
        navg = corners[0][2] + corners[1][2] + corners[2][2]
        facing = np.dot(fn, view_dir) >= 0
        if not facing:
            n_culled += 1
            continue
        navg = navg / max(np.linalg.norm(navg), 1e-12)
        shade = 0.45 + 0.45 * max(0.0, float(np.dot(navg, view_dir))) + 0.25 * max(0.0, float(navg[2]))
        shade = min(1.0, shade)
        is_arm = corners[0][0] < 48
        base = (210, 170, 125) if is_arm else (70, 72, 78)
        col = tuple(int(min(255, c * shade)) for c in base)
        dr.polygon([to_px(u) for u in uvd], fill=col)
    dr.text((8, 8), 'anim %s frame %d (%s)' % (anim_smd.stem, frame, camera), fill=(200, 200, 200))
    img.save(out_png)
    print('guardado', out_png)


def cmd_preview(args):
    recipe = WEAPONS[args.weapon]
    wdir = work_dir(args.weapon)
    ref = wdir / 'ak47_reference.smd'
    if not ref.exists():
        raise SystemExit('primero ejecuta: build')
    if args.anim:
        render_anim_frame(ref, wdir / (args.anim + '.smd'), args.frame,
                          wdir / ('preview_%s_f%d_%s.png' % (args.anim, args.frame, args.camera)),
                          camera=args.camera)
        return
    for cam in ('side', 'front', 'top'):
        render_smd(ref, wdir / ('preview_%s.png' % cam), camera=cam)


def cmd_zip(args):
    import zipfile
    weapon = args.weapon
    recipe = WEAPONS[weapon]
    out_zip = REPO_ROOT / 'dist' / ('%s-cs2-goldsrc.zip' % weapon)
    out_zip.parent.mkdir(parents=True, exist_ok=True)
    doc_files = [REPO_ROOT / 'docs' / 'INSTALL.md', REPO_ROOT / 'docs' / 'NOTICE.md']
    with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
        game_root = REPO_ROOT / 'game'
        for path in sorted(game_root.rglob('*')):
            if path.is_file():
                zf.write(path, path.relative_to(game_root))
        for doc in doc_files:
            if doc.exists():
                zf.write(doc, doc.name)
        zf.writestr('LEEME.txt',
                    'AK-47 de CS2 para GoldSrc/Xash3D FWGS\n'
                    '1) Lee INSTALL.md y NOTICE.md\n'
                    '2) Copia cstrike/ encima de tu cstrike/ (haz backup antes)\n')
    print('creado', out_zip)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    ap_build = sub.add_parser('build')
    ap_build.add_argument('weapon', choices=sorted(WEAPONS))
    ap_build.add_argument('--texture-size', type=int, default=512)
    ap_build.add_argument('--no-compile', action='store_true')
    ap_build.set_defaults(func=cmd_build)
    ap_prev = sub.add_parser('preview')
    ap_prev.add_argument('weapon', nargs='?', default='ak47', choices=sorted(WEAPONS))
    ap_prev.add_argument('--anim', type=str, default=None, help='ak47_idle|ak47_draw|...')
    ap_prev.add_argument('--frame', type=int, default=0)
    ap_prev.add_argument('--camera', choices=['side', 'front', 'top'], default='side')
    ap_prev.set_defaults(func=cmd_preview)
    ap_z = sub.add_parser('zip')
    ap_z.add_argument('weapon', nargs='?', default='ak47', choices=sorted(WEAPONS))
    ap_z.set_defaults(func=cmd_zip)
    args = ap.parse_args()
    args.func(args)


if __name__ == '__main__':
    main()
