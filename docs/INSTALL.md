# Instalación — AK-47 de CS2 para Counter-Strike (GoldSrc / Xash3D FWGS)

**Requisitos:** un Counter-Strike 1.5/1.6 clásico o **Xash3D FWGS** con el juego `cstrike` instalado localmente. No redistribuir: ver `NOTICE.md`.

## Instalación rápida

1. Haz una copia de seguridad de los archivos que vas a sustituir:
   - `cstrike/models/v_ak47.mdl`
   - `cstrike/sound/weapons/ak47-1.wav`
   - `cstrike/sound/weapons/ak47-2.wav`
2. Copia el contenido de la carpeta `cstrike/` de este ZIP encima de tu `cstrike/` (fusiona directorios).
3. (Recomendado) Renombra primero los archivos originales a `*.bak` en vez de sobrescribir.
4. Arranca el juego con `-game cstrike` (Xash3D) o normalmente (CS 1.6).

## Qué instala cada archivo

| Archivo | Qué hace |
|---|---|
| `cstrike/models/v_ak47.mdl` | Viewmodel del AK-47: malla y animaciones CS2 + **brazos de Cyberpunk 2077** (Gorilla izquierda / Skin Pale derecha; contenido derivado de CD Projekt Red y goribby — solo uso personal, ver `NOTICE.md`) |
| `cstrike/sound/weapons/cs2_ak47_01.wav` | Disparo CS2 (variación 1), 22050 Hz 16-bit mono PCM |
| `cstrike/sound/weapons/cs2_ak47_02.wav` | Disparo CS2 (variación 2) |
| `cstrike/sound/weapons/cs2_ak47_03.wav` | Disparo CS2 (variación 3) |
| `cstrike/sound/weapons/cs2_ak47_distant.wav` | Disparo CS2 (versión lejana) |
| `cstrike/sound/weapons/ak47-1.wav` | **Reemplazo** del sonido de disparo stock (copia de `cs2_ak47_01.wav`). El DLL de CS reproduce `ak47-1.wav` para el AK; sin este reemplazo no cambia ningún sonido |
| `cstrike/sound/weapons/ak47-2.wav` | Igual, con la variación 2 |

Los sonidos de recarga y de montar el cerrojo (`ak47_clipin/clipout/boltpull`) **no existen en el paquete CS2**: el modelo sigue usando los clásicos de CS 1.x, que se cargan desde tu instalación.

## Cómo restaurar el juego original

Devuelve los `.bak` que guardaste o reinstala/verifica los archivos del juego con Steam.

## Verificación rápida en Xash3D FWGS

1. `cstrike` → modo GUNGAME o un mapa cualquiera.
2. Toma el AK-47 como primera arma; la vista en primera persona mostrará el modelo CS2.
3. Prueba **R** (recarga: 75 frames de animación CS2) y disparo en ráfaga.
4. Si algo va mal (modelo invisible, T-pose, sonidos dobles): borra `v_ak47.mdl` y restaura el `.bak`.

## Notas

- El viewmodel está horneado a la escala de GoldSrc (longitud del AK ≈ 31 unidades, como el stock).
- Secuencias: `idle1`, `reload`, `draw`, `shoot1..shoot3` (índices 0-5), idéntico al v_ak47 original: el DLL de CS las encuentra por índice.
- Muzzle flash (event 5001) en el hueso `muzzle`; disparo servido por el DLL (evento 5004 del viewmodel no emite sonido de disparo para no doblarlo).
- Animaciones CS2 re-apuntadas (no hay rig CS 1.6): huesos por hueso, con datos constantes + por frame decodificados del `.ani` original.
