# PIPELINE — CS2 → GoldSrc/Xash3D (piloto AK-47)

Documento técnico del port. Para instalar, ver `INSTALL.md`. Para licencias, `NOTICE.md`.

## 1. Visión general

Transformación: viewmodel de *Source 1* de los packs CS2 (`v_rif_ak47.mdl/.vvd/.dx90.vtx/.ani`,
textura VTF, sonidos) → `v_ak47.mdl` GoldSrc (formato IDST v10) que el DLL clásico de CS
encuentra por los mismos índices de secuencia que el modelo stock.

```
SourceIO (mdl/vvd/vtx) ─┐
                        ├─► malla LOD0 (29 960 triángulos, 21 756 vértices)
anim_decoder (.ani) ────► 69 huesos, 11 secuencias, pose CONST+FRAME
                        ├─► escala×0.837 + traslación (bbox arma → bbox AK stock)
ref CS 1.5 (SMD) ───────┴─► brazos re-apuntados (alineación por dirección de hueso)
VTF ─► BMP 8 bits ────────► ak47.bmp 512×512
CS2 wav ─► PCM 22050/16 mono ─► sound/weapons/cs2_ak47_*.wav
studiomdl-sven (parchado) ► v_ak47.mdl (10x IDST, 6 secuencias, 52 huesos, 3 texturas)
```

## 2. Dependencias

```bash
sudo apt install python3 python3-venv build-essential git   # Debian/Ubuntu
bash tools/setup_tools.sh     # clona y compila SourceIO, studiomdl-sven, halflife-tools, venv
```

En `tools/vendor/` (gitignored) quedan las herramientas compiladas. Nada de
`vendor/` se commitea; `tools/cstrike_port.py` y `tools/anim_decoder.py` sí.

## 3. Build completo

```bash
tools/vendor/venv/bin/python tools/cstrike_port.py build ak47   # escribe work/ak47/* + compila
tools/vendor/venv/bin/python tools/cstrike_port.py preview ak47 # PNGs de pose bind y animaciones
tools/vendor/venv/bin/python tools/cstrike_port.py zip ak47     # dist/ak47-cs2-goldsrc.zip
```

## 4. Decisiones y restricciones duras de formato (GoldSrc/FWGS)

| Restricción | Consecuencia |
|---|---|
| `s_vertex_t` = {hueso, pos}; skinning **un hueso por vértice** | los 3 pesos VVD se colapsan al dominante |
| `lookup_vertex` deduplica con 2 decimales | vértices casi idénticos se fusionan (bien) |
| Texturas del MDL = **BMP paletizado 8 bits** | VTF 2048² se baja a 512² y se paleta (`Image.ADAPTIVE, 256`) |
| MAXSTUDIOVERTS por defecto del fork = 4096 | se recompila studiomdl con `-DMAXSTUDIOVERTS=65536` (y TRIS/BONES/SEQS) — ver `setup_tools.sh` |
| Un modelo = 1 o varios SMD "body"; un body = 32k triángulos | 31 673 triángulos del AK+brazos entran con el límite ampliado (y con 32768 por poco no) |
| Secuencias: el DLL de CS busca por índice | orden fijado a la receta: `idle1, reload, draw, shoot1, shoot2, shoot3` |
| 5001 = muzzle flash en attachment 0; 5004 = wav en attachment | se conservan los 5001 `"22"` de csbeta71 y los 5004 de recarga/draw del stock |
| Ángulos SMD = R = Rz·Ry·Rx (radianes) | extracción/reinserción numérica verificada (error < 1e-13) |

## 5. Retargeting de animaciones CS2

`tools/anim_decoder.py` decodifica el formato **FRAMEANIM** (header
`StudioFrameAnim` = 3×int32 + 12 de reserva + 1 flag/hueso):

- Datos **constantes** (`CONST_POS2/CONST_ROT2/RAW_POS/RAW_ROT`) se leen una vez y se
  propagan a frames sin datos (esto era lo que rompía con SourceIO: su assert asume
  `constant_offset>0 ⇒ frame_length==0`, falso en CS2).
- Datos **por frame**: `ANIM_ROT2/ANIM_POS` (Quat48S + half floats), `ANIM_ROT/FULL_ANIM_POS`.
- Secuencias multi-sección (`.ani` externo con block table de 3 bloques) se concatenan
  con la misma contabilidad de frames que SourceIO (primeras N secciones = 30 frames,
  las dos últimas reparten el resto).
- Huesos sin datos se rellenan con la **pose bind de Source** por componente (pos/rot),
  no con el a_base.
- `@ak47_idle` (1 frame) es la pose "brazos arriba": la bind del MDL (brazos colgando)
  NO es la pose de juego; por eso el preview se renderiza con delta skinning sobre
  bind.

Los quats decodificados tienen norma 1 exacta (verificado en las 11 animaciones).
Errores de ángulo vs bind: a_base solo difiere en los 4 huesos raíz de brazos
(90°, milimétrico de giro).

**Verificación visual** (`preview`): rasterizador software propio en el tool:
- idle f0: manos en guardamanos y pistolete ✓
- draw f8: subida del arma con ambas manos ✓
- fire1 f6: pose de disparo ✓
- reload f50: arma abajo, manos al guardamanos y cerrojo ✓
- Winding corregido por triángulo contra la normal media (los triángulos cuya
  diagonal no coincide con la normal se voltean a la escritura).
- Imágenes commiteadas: `preview_idle.png`, `preview_draw.png`, `preview_reload.png`,
  `preview_bind.png` (generadas con `preview`; rasterizador software en el tool).

## 6. Trasplante de brazos (la parte delicada)

El viewmodel CS2 **no trae brazos** (los 21 756 vértices están skinned a huesos de
arma 48-67). Los brazos vienen del `v_ak47.mdl` de CS 1.5 (beta, repo de referencia):
`hand.bmp` (187 tris) + `thumb.bmp` (384 tris), ~571 triángulos.

Mapeo de huesos (transverso: la cadena "izquierda" CS 1.5 es la del gatillo trasero →
huesos DERECHOS CS2; la delantera → huesos IZQUIERDOS CS2; pulgar→Finger0 por
orden X en ambas manos):

```
ref0→R_Forearm(1), ref1→R_Hand(2),
ref15,16,17→R_Finger0, ref2-5→R_Finger1, ref6-8→R_Finger2, ref9-11→R_Finger3, ref12-14→R_Finger4
ref24→L_Forearm(3), ref25→L_Hand(4),
ref26-29→L_Finger0, ref30-32→L_Finger1, ref33-35→L_Finger2, ref36-38→L_Finger3, ref39-41→L_Finger4
```

Colocación (v1: Kabsch global → malo; v2: alineación por dirección):

Para cada hueso mapeado, `Q = rotation_from_to(dir_ref, dir_cs2)` con
`dir = normalizar(media(pos_abs(hijos)) − pos_abs(hueso))` y, para hojas, `dir = dir_entrante`.
Cada vértice se coloca: `v' = pos_cs2 + Q·(v − pos_ref)`. Cada articulación queda
EXACTAMENTE en su posición CS2; el rollo alrededor del eje óseo es el mínimo giro.

Resultado: manos en los dos puntos de agarre con holgura de dedos consistente;
el antebrazo trasero se orienta hacia la cámara como en CS 1.x.

**Limitaciones conocidas**: las manos son pose estática "puño de sujeción" (no
discrepan de la animación porque van skinned a los huesos CS2 y las animaciones
mueven los huesos); en recargas muy contorsionadas los dedos pueden interpenetrar
el guardamanos 1-2 mm (herencia de la malla 1.5). Aceptable para piloto.

## 7. Sonidos

| Conversión | Destino |
|---|---|
| `ak47_01/02/03.wav` 44.1k stereo 16b → media + resample 2:1 (polyphase sinc) | `sound/weapons/cs2_ak47_0{1,2,3}.wav` |
| `ak47_distant.wav` 44.1k mono → 2:1 | `sound/weapons/cs2_ak47_distant.wav` |
| copias para el DLL hardcodeado | `sound/weapons/ak47-1.wav`, `ak47-2.wav` |

AA: `scipy.signal.resample_poly` (anti-aliasing FIR del polyphase). Recarga/cerrojo
sin equivalentes CS2 → se conservan los clásicos vía eventos 5004.

## 8. QC generado (resumen)

```
$body studio "ak47_reference"
$attachment 0 "muzzle" 0 0 0          # eventos 5001 del DLL
$attachment 1 "v_weapon_ak47_bolt" 0 0 0
$sequence idle1 "ak47_idle" fps 30
$sequence reload { "ak47_reload" fps 30 { event 5004 13 clipout } { event 5004 57 clipin } }
$sequence draw   { "ak47_draw"   fps 30 { event 5004 11 boltpull } }
$sequence shoot1/2/3 { "ak47_fireN" fps 30 { event 5001 0 "22" } }
```

Compilación: `studiomdl -i ak47.qc` → `v_ak47.mdl` (IDST v10, 52 huesos tras
optimización, 179 frames totales, ~1.0 MB).
Verificación: descompilado con decompmdl (`-info`): 6 secuencias en orden DLL ✓;
frame counts 1/75/31/24×3 ✓; attachments por nombre resueltos ✓.

## 9. Qué falta (roadmap)

- [ ] Probar en Xash3D FWGS encendido (este entorno solo compila y rasteriza; la
      verificación en-engine queda a cargo del usuario).
- [ ] Más armas CS2GO (galil, famas, m4a1-s/m4a4, aug, awp...) — la receta es
      declarativa en `WEAPONS` (tools/cstrike_port.py); falta texturizar y validar cada una.
- [ ] Muzzle flash sprite personalizado (actualmente usa el 5001 stock).
- [ ] Recargas: localizar `ak47_clipout/in` equivalentes en CS2 base game_sounds si existen.

## 10. Estructura del repo

```
game/cstrike/          → archivos del mod (instalables tal cual)
dist/                  → ZIP instalable (generado; commiteado a propósito)
tools/cstrike_port.py  → pipeline completo (build/preview/zip)
tools/anim_decoder.py  → decodificador FRAMEANIM standalone
tools/setup_tools.sh   → setup de vendor/
docs/                  → este documento, INSTALL, NOTICE
work/                  → intermediarios (gitignored, se regenera)
```
