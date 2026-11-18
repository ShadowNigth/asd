# CS2GO Godot 4 Port (Dust II Vertical Slice)

Recreación limpia en **Godot 4.3+** usando la lógica de simulación de `3kh0/cs2go` y `cstrike15_src` (para uso personal y educativo), configurada inicialmente con:
- **Mapa:** `de_dust2` completo (geometría, colisiones físicas, cielo HDR, iluminación solar, zonas de compra, Bombsite A/B, radar calibrado y callouts).
- **Agentes:** 1 por bando (`ctm-sas` para CT y `tm-phoenix` para T), más brazos en primera persona (`view-hands`) y guantes.
- **Todas las armas (34 armas + cuchillos + C4 + granadas):** estadísticas reales, patrones de *recoil*, dispersión dinámica, penetración de paredes, zoom de miras, silenciador (M4A1-S / USP-S), animaciones (`idle`, `draw`, `reload`, `shoot1`) e **inspección de arma (`F` -> `lookat01`)**.
- **Sonidos y efectos:** disparos cercanos/lejanos, recarga, pasos, C4, trazadoras (`tracer-core`/`tracer-glow`), fogonazo, impactos, humo, fuego de molotov/incendiaria y ceguera de flashbang.

## Modelos 3D (`.glb`) ya incluidos y convertidos

Los `.glb` originales de `3kh0/cs2go` usan `EXT_meshopt_compression`, `KHR_mesh_quantization` y texturas `KTX2` (`KHR_texture_basisu`), que Godot 4 no soporta directamente. Todos los modelos necesarios (**294 archivos**: Dust II + física + cables, CT `ctm-sas`, T `tm-phoenix`, `view-hands`, guantes `5027`, las 34 armas con todas sus animaciones incluyendo `lookat01` de inspección, cuchillo bayonet, C4 y granadas) **ya fueron convertidos y colocados dentro de `assets/models/`**:

- Geometría decodificada y descuantizada (`dequantize`), deduplicada (`dedup`) y limpiada (`prune`).
- Texturas KTX2 transcodificadas a **WebP** (`EXT_texture_webp`, soportado nativamente por Godot 4.3+).
- Guardados como `.glb.gz` (~74 MB en total) para mantener el proyecto liviano; el autoload `ModelLoader` (`scripts/systems/model_loader.gd`) los descomprime y carga automáticamente en tiempo de ejecución mediante `GLTFDocument.append_from_buffer()`.
- *(Opcional)* Si preferís tener los `.glb` descomprimidos en disco para inspeccionarlos en el editor de Godot o exportarlos, ejecutá sin internet:
  ```bash
  python3 tools/unpack_models.py
  ```

Abrí `project.godot` en **Godot 4.3+** y presioná **F5**.

## Controles
- **W / A / S / D:** Moverse (física estilo Source con *air-strafing*)
- **Shift:** Caminar en silencio | **Ctrl:** Agacharse | **Espacio:** Saltar
- **Click Izq:** Disparar / Plantar C4 / Lanzar granada
- **Click Der:** Zoom (AWP, SSG 08, AUG, SG 553, SCAR-20, G3SG1) / Silenciador (M4A1-S, USP-S) / Ataque fuerte con cuchillo
- **F:** Inspeccionar arma (`lookat01`)
- **R:** Recargar | **G:** Soltar arma | **E:** Plantar / Desactivar C4
- **B:** Menú de compra (en zona de compra)
- **1–3:** Primaria / Pistola / Cuchillo | **4:** C4 | **6–9:** Granadas (HE, Flash, Smoke, Molotov/Incendiaria)
- **Tab:** Scoreboard | **M:** Cambiar bando | **Esc:** Pausa
