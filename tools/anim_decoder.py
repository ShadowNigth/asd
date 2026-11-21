"""decoders.py — Decodificador standalone FRAMEANIM para Source 1.

Reconstruye, para cada animación, un array (frames, bones, 7) con
(pos_xyz, quat_xyzw) en espacio LOCAL (relativo al padre), replicando la
lógica de SourceIO pero soportando datos constantes + por frame mezclados
(que SourceIO no soporta) y sin tocar el árbol de SourceIO.
"""
from __future__ import annotations

import math
import struct
from dataclasses import dataclass
from pathlib import Path

import numpy as np

RAW_POS, RAW_ROT, ANIM_POS, ANIM_ROT = 0x1, 0x2, 0x4, 0x8
FULL_ANIM_POS, CONST_POS2, CONST_ROT2, ANIM_ROT2 = 0x10, 0x20, 0x40, 0x80

ANIMDESC_FMT = "iIf4I15I2HIf"
ANIMDESC_SIZE = struct.calcsize(ANIMDESC_FMT)


@dataclass
class AnimSection:
    anim_block: int
    anim_offset: int


@dataclass
class AnimDesc:
    index: int
    entry_offset: int
    name: str
    fps: float
    flags: int
    frame_count: int
    animblock_id: int
    animblock_offset: int
    section_offset: int
    section_frame_count: int


def parse_animdescs(mdl_bytes: bytes, local_anim_offset: int, count: int):
    descs = []
    off = local_anim_offset
    for i in range(count):
        entry = off
        (base_prt, name_offset, fps, flags, frame_count,
         movement_count, movement_offset, ikrule_zero_frame_offset, *unused1,
         animblock_id, animblock_offset, ikrule_count, ikrule_offset,
         animblock_ikrule_offset, local_hierarchy_count, local_hierarchy_offset,
         section_offset, section_frame_count, zero_frame_span, zero_frame_count,
         zero_frame_offset, stall_time) = struct.unpack_from(ANIMDESC_FMT, mdl_bytes, entry)
        name = read_ascii(mdl_bytes, entry + name_offset)
        descs.append(AnimDesc(i, entry, name, fps, flags, frame_count,
                              animblock_id, animblock_offset, section_offset, section_frame_count))
        off = entry + ANIMDESC_SIZE
    return descs


def read_ascii(data: bytes, off: int) -> str:
    end = data.index(b'\x00', off)
    return data[off:end].decode('utf-8', errors='replace')


def parse_sections(mdl_bytes: bytes, desc: AnimDesc):
    if desc.section_offset == 0 or desc.section_frame_count == 0:
        return []
    n = (desc.frame_count // desc.section_frame_count) + 2
    secs = []
    for i in range(n):
        block, offset = struct.unpack_from('<2I', mdl_bytes, desc.entry_offset + desc.section_offset + i * 8)
        secs.append(AnimSection(block, offset))
    return secs


def parse_block_table(mdl_bytes: bytes, block_offset: int, block_count: int):
    table = []
    for i in range(block_count):
        a, b = struct.unpack_from('<2I', mdl_bytes, block_offset + i * 8)
        table.append((a, b))  # (data_offset, data_end) relativos al .ani
    return table


def _half3(b, p):
    return struct.unpack_from('<3e', b, p)


def _quat48s(b, p):
    a, b2, c = struct.unpack_from('<3H', b, p)
    ia = (b2 >> 15) + (a >> 15) * 2
    a &= 0x7FFF; b2 &= 0x7FFF
    d_neg = c >> 15; c &= 0x7FFF
    ib, ic, idd = (ia + 1) % 4, (ia + 2) % 4, (ia + 3) % 4
    q = [0.0, 0.0, 0.0, 0.0]
    q[ia] = (a - 16384) * (1 / 23168.0)
    q[ib] = (b2 - 16384) * (1 / 23168.0)
    q[ic] = (c - 16384) * (1 / 23168.0)
    q[idd] = math.sqrt(max(0.0, 1.0 - q[ia] ** 2 - q[ib] ** 2 - q[ic] ** 2))
    if d_neg:
        q[idd] = -q[idd]
    return q


def _quat48(b, p):
    raw_x, raw_y, raw_z = struct.unpack_from('<3H', b, p)
    x = (raw_x - 32768) * (1 / 32768)
    y = (raw_y - 32768) * (1 / 32768)
    z = ((raw_z & 0x7FFF) - 16384) * (1 / 16384)
    w = math.sqrt(max(0.0, 1.0 - x * x - y * y - z * z))
    if raw_z >> 15:
        w = -w
    return [x, y, z, w]


class AnimDecoder:
    def __init__(self, mdl_path: str | Path, local_anim_offset: int, local_anim_count: int,
                 anim_block_offset: int, anim_block_count: int,
                 ani_path: str | Path | None = None):
        self.mdl_path = Path(mdl_path)
        self.ani_path = Path(ani_path) if ani_path else self.mdl_path.with_suffix('.ani')
        self.mdl = self.mdl_path.read_bytes()
        self.ani = self.ani_path.read_bytes() if self.ani_path.exists() else None
        ident = self.mdl[:4]
        assert ident == b'IDST', ident
        self.local_anim_offset = local_anim_offset
        self.local_anim_count = local_anim_count
        self.anim_block_offset = anim_block_offset
        self.anim_block_count = anim_block_count
        self.descs = parse_animdescs(self.mdl, local_anim_offset, local_anim_count)
        self.block_table = parse_block_table(self.mdl, anim_block_offset, anim_block_count)


def decode_animation(decoder: AnimDecoder, desc: AnimDesc, bone_count: int):
    """Devuelve float64 array (frame_count, bone_count, 7) con pos local + quat local."""
    frames = np.zeros((desc.frame_count, bone_count, 7))
    sections = parse_sections(decoder.mdl, desc)

    def decode_block(buf: bytes, base: int, n_frames: int):
        constant_offset, frame_offset, frame_length = struct.unpack_from('<3i', buf, base)
        bone_flags = buf[base + 24: base + 24 + bone_count]
        const_data = {}
        if constant_offset > 0:
            p = base + constant_offset
            for bi in range(bone_count):
                fl = bone_flags[bi]
                d = const_data.setdefault(bi, {})
                if fl & CONST_ROT2:
                    d['rot'] = _quat48s(buf, p); p += 6
                if fl & RAW_ROT:
                    d['rot'] = _quat48(buf, p); p += 6
                if fl & RAW_POS:
                    d['pos'] = _half3(buf, p); p += 6
                if fl & CONST_POS2:
                    d['pos'] = struct.unpack_from('<3f', buf, p); p += 12
        frame_data: dict[int, dict[int, dict]] = {}
        if frame_offset > 0 and frame_length > 0:
            p = base + frame_offset
            for f in range(n_frames):
                for bi in range(bone_count):
                    fl = bone_flags[bi]
                    if not fl:
                        continue
                    d = {}
                    if fl & ANIM_ROT2:
                        d['rot'] = _quat48s(buf, p); p += 6
                    elif fl & ANIM_ROT:
                        d['rot'] = _quat48(buf, p); p += 6
                    if fl & ANIM_POS:
                        d['pos'] = _half3(buf, p); p += 6
                    elif fl & FULL_ANIM_POS:
                        d['pos'] = struct.unpack_from('<3f', buf, p); p += 12
                    if d:
                        frame_data[(f, bi)] = d
        out = []
        for f in range(n_frames):
            fd = {}
            for bi in range(bone_count):
                src = frame_data.get((f, bi), None)
                if src is None:
                    src = const_data.get(bi)
                if src:
                    fd[bi] = src
            out.append(fd)
        return out

    if not sections:
        # sin secciones: todo el bloque en el propio .mdl
        blocks = decode_block(decoder.mdl, desc.entry_offset + desc.animblock_offset, desc.frame_count)
        write_frames = blocks
        frame_cursor = 0
        for f, fd in enumerate(write_frames):
            for bi, src in fd.items():
                if 'pos' in src:
                    frames[frame_cursor + f, bi, 0:3] = src['pos']
                if 'rot' in src:
                    frames[frame_cursor + f, bi, 3:7] = src['rot']
        return frames

    frame_cursor = 0
    for si, sec in enumerate(sections):
        if frame_cursor >= desc.frame_count:
            break
        if si < len(sections) - 2:
            sec_frames = desc.section_frame_count
        else:
            sec_frames = desc.frame_count - (len(sections) - 2) * desc.section_frame_count
        sec_frames = min(sec_frames, desc.frame_count - frame_cursor)
        if sec_frames <= 0:
            break
        if sec.anim_block == 0:
            adjusted = sec.anim_offset + (desc.animblock_offset - sections[0].anim_offset)
            blocks = decode_block(decoder.mdl, desc.entry_offset + adjusted, sec_frames)
        else:
            if decoder.ani is None:
                raise RuntimeError(f'Se necesita {decoder.ani_path}')
            data_off, _ = decoder.block_table[sec.anim_block]
            blocks = decode_block(decoder.ani, data_off + sec.anim_offset, sec_frames)
        for f, fd in enumerate(blocks):
            gi = frame_cursor + f
            for bi, src in fd.items():
                if 'pos' in src:
                    frames[gi, bi, 0:3] = src['pos']
                if 'rot' in src:
                    frames[gi, bi, 3:7] = src['rot']
        frame_cursor += sec_frames
    return frames
