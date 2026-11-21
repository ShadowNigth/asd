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
CP2077 MultiRig (.blend) ┴─► brazos Cyberpunk 2077 (28 487 triángulos) re-apuntados a huesos CS2
VTF ─► BMP 8 bits ────────► ak47.bmp 512×512
CS2 wav ─► PCM 22050/16 mono ─► sound/weapons/cs2_ak47_*.wav
studiomdl-sven (parchado) ► v_ak47.mdl (10x IDST, 6 secuencias, 50 huesos)
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

## 6. Trasplante de brazos Cyberpunk 2077 (la parte delicada)

El viewmodel CS2 **no trae brazos** (los 21 756 vértices están skinned a huesos de
arma, predominantemente `weapon_hand_r`, índice 48: el arma es hija rígida de la
muñeca derecha). El pack tampoco incluye rig de cámara ni mallas de brazos
(el `.blend`/mdl de archi está pensado como prop de weapon para cinemáticas o
para el rig de brazos que CS2 renderiza en un modelo aparte).

Los brazos vienen del rig público **Cyberpunk2077-MultiRig** de goribby
(`Cyberpunk_Rig.blend`, Blender 4.x, parseado headless con `bpy`):

- Variante elegida (keyart/locked): **Gorilla Arm izquierda** (shell, dedos, placas,
  cables, nudillos, decals) + **Skin Pale derecha** (antebrazo/palma + uñas).
  Ver `INCLUDE` en `tools/blender_export_cp2077.py`.
- Exportación: rest-pose, skinning por matriz de reposo (`matrix_local`), dominio
  del vertex group por triángulo.
- **Corrección de orientación** (`--corr full`): `corr(b) = R_dst · R_srcᵀ` por hueso
  estructural (ForeArm/Hand/fingers), componiendo en jerarquía. La rest-pose de
  CP2077 cuelga hacia abajo-delante mientras el bind CS2 mira al arma; el factor
  uniforme de escala es la razón de longitudes de antebrazo (≈31.3 en unidades
  del .blend) en ambos lados.
- **Ancla única por triángulo**: los tres vértices de cada cara cuelgan del hueso
  ancla de la esquina con mayor peso dominante (antes cada esquina iba a su propio
  hueso y los triángulos que cruzaban huesos se estiraban como cintas).
- Huesos máquina/músculo de CP2077 (raíces desconectadas, sin correspondencia en
  el esqueleto CS2) se anclan al hueso estructural más cercano en rest-pose.
- Texturas: UVs del .blend + bake Cycles de los grupos de nodos (albedo por
  material) → BMP 8 bits; decals como `{`-BMP (clave azul), recortados a ≤512.
- Normales re-orientadas por el mismo corr; viento corregido por triángulo
  contra la normal media.

Resultado: brazos gorilla completos (izquierda) y piel pálida (derecha),
respetando el pack de archi: la geometría del arma queda rígida respecto a la
muñeca derecha (`weapon_hand_r`), igual que en CS2. Las animaciones de brazo
del pack son las que definen la pose; el arma, los brazos y la manipulación
duran lo que duran sus curvas (verificado en idle/draw/reload con el
rasterizador software: `ak47_idle`, `ak47_draw`, `ak47_reload`, `ak47_fire1..3`).

**Limitaciones conocidas**:
- El pack de archi publica el arma sin brazos; la relación arma↔brazos en
  pantalla es la que definen las curvas FRAMEANIM del pack (brazos que entran
  desde los laterales/bottom, como en el bind). No hay garantía de
  "manos sobre el arma" perfecta en todos los cuadros: es el dato original.
- Los cables/nudillos de CP2077 deforman bien en idle/draw; en reload muy
  contorsionado los decals pueden bailar unos mm. Aceptable para piloto.
- El esqueleto GoldSrc no soporta IK; no hay intención de añadirlo.

**Historial de intentos fallidos** (para no repetir): corrección `full` por-bone
sin jerarquía (cintas estiradas), alineación por dirección de hueso v1/v2
(brazos desconectados / bbox explotada), y composición compartida global Kabsch
(descartada: el bind CP2077 es ~anti-paralelo al bind CS2 en toda la cadena,
con swings de 125-156° uniformes).

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
