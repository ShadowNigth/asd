#!/usr/bin/env python3
"""
blender_export_cp2077.py — Extrae los brazos de Cyberpunk 2077 (MultiRig de goribby)
y los re-orienta al skeleton del viewmodel CS2 para el port GoldSrc.

Se ejecuta con el Blender headless (bpy) del venv tools/vendor/bpy-venv:

  tools/vendor/bpy-venv/bin/python tools/blender_export_cp2077.py \
      --blend work/cyberpunk-multirig/Cyberpunk_Rig.blend \
      --cs2bind work/ak47/cs2_bind.json \
      --out-tris work/ak47/cp2077_arms.smd.json \
      --bake-dir work/ak47

Variante de brazos (pedido del usuario, igual que el keyart de CP2077):
  brazo IZQUIERDO = Gorilla Arms (cyberware, cromo) + brazo DERECHO = piel Skin Pale.
  Sets completos: Fingers_Left + Meshes_GorillaArms_Left (10 piezas) +
  submesh_01_LOD_1.002 + submesh_02_LOD_1.002 (antebrazo/mano der) + Nails Right.

El mesh del rig CP2077 fue esculpido EN la pose de la rig (no en rest):
todos los cálculos usan las matrices de POSE (pb.matrix), no las de reposo.

Cada vértice se reasigna a un hueso CS2 (single weight, regla de hueso dominante)
y se re-orienta con una corrección por hueso corr = R_cs2 @ R_src^-1 (orientación
completa, corrige también twist), escalado globalmente por s = longitudes de
antebrazo CS2 / CP2077.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

# ── Selección de meshes (imágenes: izquierda = cromo gorilla, derecha = piel) ──
LEFT_GORILLA = [
    'Fingers_Left',               # dedos cromo (Gorilla Arms Fingers Reed)
    'submesh_00_LOD_1.005',       # antebrazo "Skin Pale Gorilla Arms"
    'submesh_00_LOD_1.025',       # cyberware dorso de la mano (a0_005 wa)
    'submesh_00_LOD_1.027',       # piel antebrazo->mano
    'submesh_01_LOD_1.004',       # wires (cables rojos)
    'submesh_02_LOD_1.004',       # knuckles (nudillos cromo)
    'submesh_03_LOD_1.002',       # cuff de muñeca (strongarms end)
    'submesh_04_LOD_1',           # decal funda en antebrazo
    'submesh_05_LOD_1',           # decal entre dedos
    'submesh_06_LOD_1',           # decal mugre bajo cyberware
]
RIGHT_HUMAN = [
    'submesh_01_LOD_1.002',       # antebrazo Skin Pale
    'submesh_02_LOD_1.002',       # mano Skin Pale
    'Nails Right',                # uñas (piel)
]
INCLUDE = LEFT_GORILLA + RIGHT_HUMAN
MESH_SIDE = {n: 'L' for n in LEFT_GORILLA}
MESH_SIDE.update({n: 'R' for n in RIGHT_HUMAN})

# ── Mapa de huesos CP2077 -> hueso CS2 (v_rif_ak47.mdl) ─────────────────────
CS2 = {'L_Forearm': 3, 'L_Hand': 4, 'L_Twist': 20,
       'R_Forearm': 1, 'R_Hand': 2, 'R_Twist': 36,
       'L_Thumb': 5, 'L_Index': 8, 'L_Middle': 11, 'L_Ring': 14, 'L_Pinky': 17,
       'R_Thumb': 21, 'R_Index': 24, 'R_Middle': 27, 'R_Ring': 30, 'R_Pinky': 33}

DIRECT = {}
for side in ('L', 'R'):
    P = 'Left' if side == 'L' else 'Right'
    p = 'l' if side == 'L' else 'r'
    F, H = CS2[side+'_Forearm'], CS2[side+'_Hand']
    th, ix, md, rg, pk = (CS2[side+'_Thumb'], CS2[side+'_Index'], CS2[side+'_Middle'],
                          CS2[side+'_Ring'], CS2[side+'_Pinky'])
    for src, dst in [(f'{P}ForeArm', F), (f'{P}Hand', H),
                     (f'{P}HandThumb1', th), (f'{P}HandThumb2', th+1), (f'{P}HandThumb3', th+2),
                     (f'{P}HandIndex1', ix), (f'{P}HandIndex2', ix+1), (f'{P}HandIndex3', ix+2),
                     (f'{P}HandMiddle1', md), (f'{P}HandMiddle2', md+1), (f'{P}HandMiddle3', md+2),
                     (f'{P}HandRing1', rg), (f'{P}HandRing2', rg+1), (f'{P}HandRing3', rg+2),
                     (f'{P}HandPinky1', pk), (f'{P}HandPinky2', pk+1), (f'{P}HandPinky3', pk+2),
                     (f'{P}InHandThumb', th), (f'{P}InHandIndex', ix), (f'{P}InHandMiddle', md),
                     (f'{P}InHandRing', rg), (f'{P}InHandPinky', pk),
                     (f'{p}_Wrist_0_JNT', H), (f'{p}_Wrist_1_JNT', H), (f'{p}_Wrist_2_JNT', H),
                     (f'{p}_wrist_A_mscl_JNT', H), (f'{p}_wrist_B_mscl_JNT', H), (f'{p}_wrist_C_mscl_JNT', H),
                     (f'{p}_elbow_bend_A_mscl_JNT', F), (f'{p}_elbow_bend_B_mscl_JNT', F),
                     (f'{p}_elbow_back_mscl_JNT', F),
                     (f'{p}_biceps_A_mscl_JNT', F), (f'{p}_triceps_mscl_JNT', F),
                     (f'{p}_SHL_0_JNT', F), (f'{p}_SHL_1_JNT', F),
                     (f'{p}_ind_knuckle_top_mscl_JNT', ix), (f'{p}_ind_knuckle_bot_mscl_JNT', ix),
                     (f'{p}_ind_knuckle_B_top_mscl_JNT', ix),
                     (f'{p}_mid_knuckle_top_mscl_JNT', md), (f'{p}_mid_knuckle_bot_mscl_JNT', md),
                     (f'{p}_mid_knuckle_B_top_mscl_JNT', md),
                     (f'{p}_ring_knuckle_top_mscl_JNT', rg), (f'{p}_ring_knuckle_bot_mscl_JNT', rg),
                     (f'{p}_ring_knuckle_B_top_mscl_JNT', rg),
                     (f'{p}_pinky_knuckle_top_mscl_JNT', pk), (f'{p}_pinky_knuckle_bot_mscl_JNT', pk),
                     (f'{p}_pinky_knuckle_B_top_mscl_JNT', pk),
                     (f'{p}_thumb_side_mscl_JNT', th),
                     (f'{p}_thumb_thumb_A_bot_mscl_JNT', th), (f'{p}_thumb_thumb_A_top_mscl_JNT', th),
                     (f'{p}_pinkyBase_A_bot_mscl_JNT', pk)]:
        DIRECT[src] = dst

# textura GoldSrc por material CP2077 ('cp_' + nombre corto; decals con prefijo '{')
MATERIAL_BM_P = {
    'Skin Pale': 'cp_skin.bmp',
    'Skin Pale Gorilla Arms': 'cp_skin_ga.bmp',
    'Gorilla Arms Fingers Reed': 'cp_fingers.bmp',
    'ml_a0_005_wa__strongarms_cyberware_masksset': 'cp_cyberware.bmp',
    'ml_a0_005_ma__strongarms_end_masksset': 'cp_endm.bmp',
    'knuckles': 'cp_knuckles.bmp',
    'wires': 'cp_wires.bmp',
    'decal_holstered_forearm_01': '{cp_dechol.bmp',
    'decal_betewwn_fingers': '{cp_decfing.bmp',
    'decal_under_cyberware': '{cp_decund.bmp',
    'Nails Skin': 'cp_nails.bmp',
}
DECAL_MATS = {n for n in MATERIAL_BM_P if MATERIAL_BM_P[n].startswith('{')}


def cp2cs2(name: str, side_hint: str):
    if name in DIRECT:
        return DIRECT[name]
    m = re.match(r'^([lr])_', name)
    if m:
        side = 'L' if m.group(1) == 'l' else 'R'
    elif name.startswith('Left'):
        side = 'L'
    elif name.startswith('Right'):
        side = 'R'
    else:
        side = side_hint
    F, H = CS2[side+'_Forearm'], CS2[side+'_Hand']
    low = name.lower()
    if 'wrist' in low:
        return H
    if 'elbow' in low or 'biceps' in low or 'triceps' in low or 'shl' in low or 'deltoid' in low:
        return F
    for key, slot in (('thumb', 'Thumb'), ('ind', 'Index'), ('index', 'Index'),
                      ('mid', 'Middle'), ('ring', 'Ring'), ('pinky', 'Pinky')):
        if key in low:
            return CS2[side + '_' + slot]
    # Hips/Spine/Legs/etc. en la región del codo -> clamp al antebrazo
    return F


def quat_of_matrix3(r):
    m = np.array(r.to_3x3() if hasattr(r, 'to_3x3') else r, dtype=np.float64)
    # normalizar columnas por si hay drift numérico
    u, _, vh = np.linalg.svd(m)
    if np.linalg.det(u @ vh) < 0:
        u[:, -1] *= -1
    return u @ vh


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--blend', required=True)
    ap.add_argument('--cs2bind', required=True)
    ap.add_argument('--out-tris', required=True)
    ap.add_argument('--bake-dir', default=None)
    ap.add_argument('--bake-size', type=int, default=512)
    ap.add_argument('--corr', choices=['full', 'direction'], default='full')
    ap.add_argument('--no-bake', action='store_true')
    args = ap.parse_args()

    _cp2cs2_cache = {}
    def cp2cs2_cached(name, side_hint):
        key = (name, side_hint)
        if key not in _cp2cs2_cache:
            _cp2cs2_cache[key] = cp2cs2(name, side_hint)
        return _cp2cs2_cache[key]

    bind = json.loads(Path(args.cs2bind).read_text())
    cs2_abs = [np.array(m['abs_pos'], dtype=np.float64) for m in bind['bones']]
    cs2_rot = [np.array(m['abs_rot'], dtype=np.float64).reshape(3, 3) for m in bind['bones']]
    scale_global = bind['scale']

    bpy.ops.wm.open_mainfile(filepath=args.blend)

    rig = bpy.data.objects['Rig']
    mw = np.array(rig.matrix_world, dtype=np.float64)

    # matrices REST en mundo: el mesh está esculpido en rest
    # (obj.bound_box está stale en este .blend; las co del
    #  vértice crudo coinciden con los huesos en rest, no con la pose)
    pose_abs, pose_rot = {}, {}
    for bone in rig.data.bones:
        M = mw @ np.array(bone.matrix_local, dtype=np.float64)
        pose_abs[bone.name] = M[:3, 3]
        pose_rot[bone.name] = quat_of_matrix3(M[:3, :3])

    # escala global CP2077 -> CS2: razón de longitudes de antebrazo
    lens = []
    for side in ('L', 'R'):
        P = 'Left' if side == 'L' else 'Right'
        F, H = CS2[side+'_Forearm'], CS2[side+'_Hand']
        src = np.linalg.norm(pose_abs[f'{P}Hand'] - pose_abs[f'{P}ForeArm'])
        dst = np.linalg.norm(cs2_abs[H] - cs2_abs[F])
        if src > 1e-8:
            lens.append(dst / src)
    s = float(np.mean(lens))
    print('arm scale cp2077->cs2: %.4f (forearm ratios: %s)' % (s, ['%.4f' % x for x in lens]))
    print('cs2 gun scale (info):', scale_global)

    # ── helpers compartidos (modo direction y full) ──────────────────────────
    cp_children, cp_parents = {}, {}
    for b in rig.data.bones:
        if b.parent:
            cp_children.setdefault(b.parent.name, []).append(b.name)
            cp_parents[b.name] = b.parent.name
    STRUCT = ('ForeArm', 'Hand', 'HandThumb1', 'HandThumb2',
              'HandIndex1', 'HandIndex2', 'HandIndex3',
              'HandMiddle1', 'HandMiddle2', 'HandMiddle3',
              'HandRing1', 'HandRing2', 'HandRing3',
              'HandPinky1', 'HandPinky2', 'HandPinky3')

    def _is_struct(name):
        if name.startswith(('l_', 'r_')):
            return False
        if name.startswith(('Left', 'Right')):
            base = ('Left', 'Right')[0] != None and None
            if name.startswith('Left'):
                base = name[4:]
            else:
                base = name[5:]
        else:
            base = name
        return any(base == st for st in STRUCT)

    def _structural_ancestor(name):
        cur = name
        seen = set()
        while cur and cur not in seen:
            seen.add(cur)
            if _is_struct(cur):
                return cur
            cur = cp_parents.get(cur)
        return None

    def _side_of(name):
        return 'L' if name.startswith(('Left', 'l_')) else 'R'

    struct_names = [n for n in pose_abs if _is_struct(n)]
    nearest_cache = {}

    def _nearest_struct(name):
        if name in nearest_cache:
            return nearest_cache[name]
        p = pose_abs[name]
        best, best_d = None, np.inf
        for sn in struct_names:
            d = np.linalg.norm(pose_abs[sn] - p)
            if d < best_d:
                best_d, best = d, sn
        nearest_cache[name] = best
        return best

    def placement(src):
        anc = _structural_ancestor(src)
        if anc is None:
            anc = _nearest_struct(src)
        return anc

    if args.corr == 'direction':
        def _rot_between(a, b):
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

        def _directions(abs_pos, children, parents, keys):
            dirs = {}
            for k in keys:
                kids = children.get(k, [])
                if kids:
                    c = np.mean([abs_pos[i] for i in kids], axis=0)
                    d = c - abs_pos[k]
                else:
                    pr = parents.get(k)
                    d = abs_pos[k] - abs_pos[pr] if pr is not None else np.array([1.0, 0, 0])
                n = np.linalg.norm(d)
                dirs[k] = d / n if n > 1e-8 else np.array([1.0, 0, 0])
            return dirs

        src_keys = list(pose_abs)
        # hijos por hueso CS2 (por índice)
        cs2_children, cs2_parents = {}, {}
        for i, b in enumerate(bind['bones']):
            if b['parent'] >= 0:
                cs2_children.setdefault(b['parent'], []).append(i)
                cs2_parents[i] = b['parent']
        dir_src = _directions(pose_abs, cp_children, cp_parents, src_keys)
        cs2_abs_d = {i: cs2_abs[i] for i in range(len(cs2_abs))}
        dir_dst = _directions(cs2_abs_d, cs2_children, cs2_parents, list(range(len(cs2_abs))))

        # ── corrección jerárquica: corr(b) = corr(padre_estructural) @ swing_local(b) ──
        corr_cache = {}

        def corr_for(struct_src):
            # struct_src SIEMPRE es estructural (placement() lo garantiza)
            if struct_src in corr_cache:
                return corr_cache[struct_src]
            side = _side_of(struct_src)
            cs2_bone = cp2cs2_cached(struct_src, side)
            parent_src = cp_parents.get(struct_src)
            parent = _structural_ancestor(parent_src) if parent_src else None
            if parent is None and parent_src and parent_src in pose_abs:
                # subir por ancestros reales hasta topar con uno estructural o raíz
                cur = parent_src
                seen = set()
                while cur and cur not in seen:
                    seen.add(cur)
                    if _is_struct(cur):
                        parent = cur
                        break
                    cur = cp_parents.get(cur)
            if parent is None:
                R_parent = np.eye(3)
                cs2_parent = None
                R_src_parent = np.eye(3)
            else:
                cs2_parent = cp2cs2_cached(parent, _side_of(parent))
                R_parent = corr_for(parent)
                R_src_parent = pose_rot[parent]
            # marco local: dirección del hueso relativa al padre ESTRUCTURAL
            R_dst_parent = np.eye(3) if cs2_parent is None else cs2_rot[cs2_parent]
            src_local_dir = R_src_parent.T @ dir_src[struct_src]
            dst_local_dir = R_dst_parent.T @ dir_dst[cs2_bone]
            swing = _rot_between(src_local_dir, dst_local_dir)
            corr = R_parent @ swing
            corr_cache[struct_src] = corr
            return corr
    else:
        # orientación completa: corr(b) = R_dst @ R_src^T
        # (composición exacta en jerarquía; re-orienta el hueso 1:1 a bind CS2)
        def corr_for(struct_src):
            side = _side_of(struct_src)
            cs2_bone = cp2cs2_cached(struct_src, side)
            return cs2_rot[cs2_bone] @ pose_rot[struct_src].T

    # recolección de tris
    tris_out = []
    materials_used = {}
    unmapped = {}
    for name in INCLUDE:
        o = bpy.data.objects.get(name)
        if o is None:
            print('AVISO: no existe el objeto', name)
            continue
        mesh = o.data
        uv_layer = mesh.uv_layers.active
        if uv_layer is None:
            print('AVISO: sin UVs', name)
            continue
        gi = {g.index: g.name for g in o.vertex_groups}
        dominant = []  # (grupo_dominante, peso) por vértice
        for v in mesh.vertices:
            if v.groups:
                g = max(v.groups, key=lambda g: g.weight)
                dominant.append((gi[g.group], g.weight))
            else:
                dominant.append((None, 0.0))
        M4 = o.matrix_world  # mathutils Matrix
        # vértices en mundo
        verts_w = [np.array(M4 @ v.co, dtype=np.float64) for v in mesh.vertices]
        normals_w = []
        Mrot = quat_of_matrix3(np.array(o.matrix_world.to_3x3(), dtype=np.float64))
        for v in mesh.vertices:
            n = Mrot @ np.array(v.normal, dtype=np.float64)
            normals_w.append(n / max(np.linalg.norm(n), 1e-12))
        uvs = [tuple(uv.uv) for uv in uv_layer.data]
        mesh.calc_loop_triangles()
        mat_name = mesh.materials[0].name if mesh.materials and mesh.materials[0] else 'Skin Pale'
        materials_used.setdefault(mat_name, {})
        side_hint = MESH_SIDE[name]
        for tri in mesh.loop_triangles:
            # ── ancla ÚNICA por triángulo ──────────────────────────────
            # antes cada esquina se anclaba a SU hueso → un triángulo podía
            # quedar repartido entre dos marcos distintos y se estiraba
            # hasta convertirse en cinta. Ahora todo el triángulo cuelga del
            # hueso ancla de la esquina con mayor peso dominante.
            tri_vi = [mesh.loops[li].vertex_index for li in tri.loops]
            best_vi = max(tri_vi, key=lambda vi: dominant[vi][1])
            src_best = dominant[best_vi][0]
            if src_best is None:
                anc = 'LeftForeArm' if side_hint == 'L' else 'RightForeArm'
            else:
                anc = placement(src_best)
            cs2_bone = cp2cs2_cached(anc, side_hint)
            for vi in tri_vi:
                src = dominant[vi][0]
                if src is not None and src not in DIRECT:
                    unmapped[src] = unmapped.get(src, 0) + 1
            C = corr_for(anc)
            T = pose_abs[anc]
            cs2_pos = cs2_abs[cs2_bone]
            corners = []
            for li in tri.loops:
                vi = mesh.loops[li].vertex_index
                p = verts_w[vi]
                p_new = cs2_pos + s * (C @ (np.array(p) - T))
                n_new = C @ normals_w[vi]
                n_new /= max(np.linalg.norm(n_new), 1e-12)
                uv = uvs[mesh.loops[li].index]
                corners.append((cs2_bone, p_new, n_new, uv))
            tris_out.append((mat_name, corners))

    print('tris extraídos:', len(tris_out))
    print('huesos CP2077 sin mapa directo (clamp):', dict(sorted(unmapped.items())))

    Path(args.out_tris).write_text(json.dumps({
        'tris': [[mat, [[int(b), [float(v) for v in p], [float(v) for v in n], [float(uv[0]), float(uv[1])]]
                          for b, p, n, uv in tri]] for mat, tri in tris_out],
        'materials': MATERIAL_BM_P,
        'bake_size': args.bake_size,
    }))
    print('escrito', args.out_tris)

    # ── bake de texturas (Cycles, pase DIFFUSE color, sin lighting) ──
    if args.no_bake:
        return
    bake_dir = Path(args.bake_dir)
    bake_dir.mkdir(parents=True, exist_ok=True)
    # el .blend guarda colecciones con exclude=True (Cyberware/Gorilla fuera por
    # defecto); hay que re-habilitar todo para que el bake seleccione las mallas
    def _set_all_exclude(lc, exc):
        lc.exclude = exc
        for c in lc.children:
            _set_all_exclude(c, exc)
    _set_all_exclude(bpy.context.view_layer.layer_collection, False)
    for o in bpy.data.objects:
        o.hide_render = (o.type == 'MESH' and o.name not in INCLUDE)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 1
    for mat_name in sorted(set(m for m, _ in tris_out)):
        if mat_name in DECAL_MATS:
            print('decal (composite directo, sin bake):', mat_name)
            continue  # los decals se componen desde el PNG _d01 (alpha propio)
        m = bpy.data.materials.get(mat_name)
        if m is None or not m.use_nodes:
            continue
        img = bpy.data.images.new('bake_%s' % mat_name, args.bake_size, args.bake_size, alpha=False)
        # nodo target
        node = m.node_tree.nodes.new('ShaderNodeTexImage')
        node.image = img
        node.select = True
        m.node_tree.nodes.active = node
        # seleccionar objetos con este material
        objs = [bpy.data.objects[n] for n in INCLUDE
                if bpy.data.objects.get(n) and any(mm and mm.name == mat_name for mm in bpy.data.objects[n].data.materials)]
        for o in bpy.context.view_layer.objects:
            o.select_set(o in objs)
        if objs:
            bpy.context.view_layer.objects.active = objs[0]
            try:
                bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, target='IMAGE_TEXTURES', margin=8)
            except Exception as ex:
                print('BAKE FALLÓ', mat_name, ex)
            img.filepath_raw = str(bake_dir / (MATERIAL_BM_P[mat_name].replace('{', '').replace('.bmp', '.png')))
            img.file_format = 'PNG'
            img.save()
            print('bake', mat_name, '->', img.filepath_raw)
        m.node_tree.nodes.remove(node)
    # decals: compuesto directo del _d01 con su alpha
    for mat_name in sorted(DECAL_MATS):
        m = bpy.data.materials.get(mat_name)
        if m is None or not m.use_nodes:
            continue
        out_png = bake_dir / (MATERIAL_BM_P[mat_name].replace('{', '').replace('.bmp', '.png'))
        nt = m.node_tree
        mix = next((n for n in nt.nodes if n.type == 'MIX_RGB'), None)
        gamma = next((n for n in nt.nodes if n.type == 'GAMMA'), None)
        rgb = next((n for n in nt.nodes if n.type == 'RGB'), None)
        tex2 = next((n for n in nt.nodes if n.type == 'TEX_IMAGE' and n.name == 'Image Texture'), None)
        if tex2 is None:
            tex2 = next(n for n in nt.nodes if n.type == 'TEX_IMAGE' and '_d01' in (n.image.name if n.image else ''))
        img = tex2.image
        w, h = img.size
        pix = np.array(img.pixels[:], dtype=np.float64).reshape(h, w, 4)
        c2 = pix[..., :3]
        alpha = pix[..., 3]
        if mix is not None and gamma is not None and rgb is not None:
            fac = mix.inputs[0].default_value
            blend = mix.blend_type
            g = gamma.inputs['Gamma'].default_value
            c1 = np.array(rgb.outputs[0].default_value[:3], dtype=np.float64) ** (1.0 / max(g, 1e-6))
            c1 = np.broadcast_to(c1, c2.shape)
            if blend == 'MULTIPLY':
                c = c1 * c2
            elif blend == 'MIX':
                c = (1 - fac) * c1 + fac * c2
            elif blend == 'OVERLAY':
                c = np.where(c1 < 0.5, 2 * c1 * c2, 1 - 2 * (1 - c1) * (1 - c2))
            else:
                c = c2
            if abs(fac - 1.0) < 1e-6 and blend == 'MIX':
                c = c2
        else:
            c = c2
        out = np.empty((h, w, 4), dtype=np.float64)
        out[..., :3] = np.clip(c, 0, 1)
        out[..., 3] = alpha
        # guarda PNG RGBA vía imagen temporal
        tmp = bpy.data.images.new('decal_out', w, h, alpha=True)
        tmp.pixels = out[::-1].astype(np.float32).reshape(-1)  # Blender pixels = bottom-up
        tmp.filepath_raw = str(out_png)
        tmp.file_format = 'PNG'
        tmp.save()
        print('decal', mat_name, '->', out_png)


if __name__ == '__main__':
    main()
