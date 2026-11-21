# NOTICE — Derechos de autor y atribución

Este repositorio es un **mod personal, sin ánimo de lucro**.

## Qué NO puedes redistribuir

Los archivos bajo `game/` y `dist/` contienen material derivado de
**Counter-Strike 2 / Counter-Strike: Source (Valve)** y de
**Counter-Strike 1.x (Valve)**:

- La malla, las animaciones y las texturas del arma provienen de los packs
  oficiales de viewmodels de CS2 (obtenidos por el usuario).
- Los brazos/manos son el modelo `v_ak47.mdl` de CS 1.5 (beta pública filtrada)
  descompilado y re-apuntado.
- Los sonidos son los .wav oficiales de CS2 convertidos a 22050 Hz mono.

**Prohibida su redistribución pública** (Workshop, foros, webs, mirror links).
Úsalos únicamente en tu instalación local. Los términos de Valve
(Software Model End User License Agreement) siguen aplicando.

## Herramientas (código de terceros, usado localmente)

| Herramienta | Origen | Licencia |
|---|---|---|
| SourceIO | https://github.com/REDxEYE/SourceIO | MIT |
| studiomdl-sven | https://github.com/bacontsu/studiomdl-sven-crossplatfrom | Half-Life 1 SDK LICENSE (Valve) |
| decompmdl (halflife-tools) | https://github.com/Toodles2You/halflife-tools | Half-Life 1 SDK LICENSE (Valve) |
| fast-simplification, numpy, pillow, scipy | PyPI | MIT/BSD |

El código de `tools/` es original de este proyecto (salvo los parches mínimos
al Makefile de studiomdl-sven documentados en `docs/PIPELINE.md`) y puede
usarse libremente. Las herramientas NO se redistribuyen en el ZIP: se clonan
y compilan con `tools/setup_tools.sh`.

## Atribución esperada

"Port de viewmodel CS2→GoldSrc por ShadowNigth", con enlace a este repositorio,
en cualquier fork personal.
