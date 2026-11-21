#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Prepara todas las dependencias externas del pipeline de conversión.
#  Uso:  bash tools/setup_tools.sh
#  Requiere: python3, python3-venv, gcc, git, make  (NO requiere sudo)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO_ROOT/tools/vendor"
mkdir -p "$VENDOR"
cd "$VENDOR"

echo "==> [1/5] SourceIO (parser de .mdl/.vvd/.vtx/.ani/.vtf de Source 1, MIT)"
if [ ! -d "$VENDOR/SourceIO" ]; then
    git clone --depth 1 https://github.com/REDxEYE/SourceIO.git
else
    echo "    SourceIO ya presente, se omite."
fi

echo "==> [2/5] halflife-tools (decompilador GoldSrc decompmdl, para modelos de referencia)"
if [ ! -d "$VENDOR/halflife-tools" ]; then
    git clone --depth 1 https://github.com/Toodles2You/halflife-tools.git
fi
if [ ! -f "$VENDOR/bin/decompmdl" ]; then
    mkdir -p "$VENDOR/bin"
    ( cd "$VENDOR/halflife-tools" && \
      gcc -O2 -Wno-discarded-qualifiers -I src -include pch.h \
        src/common.c src/math.c src/decompile.c src/studio.c src/model.c \
        src/texture.c src/animation.c src/sprite.c src/wad.c src/info.c \
        -lm -o "$VENDOR/bin/decompmdl" )
fi

echo "==> [3/5] studiomdl (compilador GoldSrc/Xash3D, fork Sven Co-op multiplataforma)"
if [ ! -d "$VENDOR/studiomdl-sven" ]; then
    git clone --depth 1 https://github.com/bacontsu/studiomdl-sven-crossplatfrom.git
fi
if [ ! -f "$VENDOR/bin/studiomdl" ]; then
    mkdir -p "$VENDOR/bin"
    ( cd "$VENDOR/studiomdl-sven" && \
      python3 - <<'PY'
import re
s = open('Makefile').read()
s = s.replace('$(CC) $(OPTS) $(STUDIOMDL_OBJECTS) $(STUDIOMDL_COMMON_OBJECTS) -o $@',
              '$(CC) $(OPTS) $(STUDIOMDL_OBJECTS) $(STUDIOMDL_COMMON_OBJECTS) -o $@ -lm')
# Xash3D admite modelos muy grandes; se amplía el límite de vértices por submodelo.
s = s.replace('STUDIOMDL_DEFINES=-DSTUDIOMDL',
              'STUDIOMDL_DEFINES=-DSTUDIOMDL -DMAXSTUDIOVERTS=65536 -DMAXSTUDIOTRIANGLES=65536 -DMAXSTUDIOBONES=256 -DMAXSTUDIOSEQUENCES=2048')
open('Makefile', 'w').write(s)
PY
      make ARCH=-m64 >/dev/null && cp build/bin-x86_64/studiomdl "$VENDOR/bin/studiomdl" )
fi

echo "==> [4/5] venv de Python con numpy / pillow / fast-simplification"
if [ ! -d "$VENDOR/venv" ]; then
    python3 -m venv "$VENDOR/venv"
    "$VENDOR/venv/bin/pip" install --quiet --upgrade pip
    "$VENDOR/venv/bin/pip" install --quiet numpy pillow fast-simplification
fi

echo "==> [5/5] Verificación"
"$VENDOR/bin/studiomdl" 2>&1 | head -2 || true
"$VENDOR/bin/decompmdl" -help 2>&1 | head -2 || true
"$VENDOR/venv/bin/python" -c "import numpy, PIL, fast_simplification; print('venv OK')"

echo
echo "✓ Dependencias listas en tools/vendor/"
echo "  Siguiente paso:  tools/vendor/venv/bin/python tools/source_to_goldsrc.py --help"
