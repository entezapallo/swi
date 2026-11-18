# Agregar formateadores de sintaxis (vía Fexl)

El formateo no vive en el editor: Fexl calcula los spans y el motor solo los
aplica. Así se pueden cambiar patrones sin recompilar.

## Dónde está cada pieza

| Archivo | Rol |
|---|---|
| `ui.fxl` | define los patrones con `regex.compile`, corre `regex.spans` y emite líneas `SPANS` |
| `tui/fexl_ui.h/.c` | evento `FUI_FMT` ('F'), parser de `SPANS <style> <start,end;...>` en `UiFrame.span[]` |
| `tui/main.c` | `fmt_send()` escribe el buffer a `/tmp/swi_fmt_input.txt`, pide spans y los aplica con `fmt_add_span()` |
| `tui/win_editor.ll` | `win_editor_fmt()`, `win_editor_clear_spans()` y `hl_style_at()` |
| `regex/format.ll` | `fmt_create`, `fmt_clear`, `fmt_add_span`, `fmt_cache_*` |
| `abi/tui_abi.h` | constantes `FMT_SEARCH`, `FMT_KEYWORD`, `FMT_STRING`, `FMT_COMMENT`, `FMT_NUMBER` |

## API de Fexl usada

```
(regex.compile pattern)               -> regex | void
(regex.spans prog text max)           -> "start,end;start,end;..."
(regex.count prog text)               -> num
(abregex.session)                     -> sesión
(abregex.define session defs)         -> 1 ok / 0 error
(abregex.compile session name)        -> regex | void
```

`regex.spans` devuelve un string de pares `start,end`. El intérprete lo emite
tal cual en el frame y el C lo parsea.

## Ejemplo instalado

En `ui.fxl`:

```fexl
\pat_string=(regex.compile "[A-Za-z_][A-Za-z0-9_]*")
\pat_number=(regex.compile "[0-9]+")

\emit_fmt=
    (\txt
    say ["SPANS 3 " (regex.spans pat_string txt 512)]
    say ["SPANS 5 " (regex.spans pat_number txt 512)]
    say "."
    fflush stdout
    )
```

Cuando el motor manda `FUI_FMT`, el driver lee `/tmp/swi_fmt_input.txt`,
emite los `SPANS` y vuelve al loop normal.

El frame llega así:

```
SPANS 3 2,5;9,14
SPANS 5 22,24
.
```

`fexl_ui.c` convierte cada par en `FmtSpan {start, len, style}` y `main.c`
hace:

```c
win_editor_clear_spans(ed);
for (...)
    fmt_add_span(win_editor_fmt(ed), start, len, style);
win_editor_set_highlight(ed, g_last_pattern, ...);   /* búsqueda, estilo 1 */
```

## Estilos y colores

| style_id | Nombre | Color |
|---|---|---|
| 0 | NONE | normal |
| 1 | SEARCH | amarillo bold |
| 2 | KEYWORD | cian |
| 3 | STRING | verde |
| 4 | COMMENT | gris |
| 5 | NUMBER | magenta |

Prioridad en `draw_span`: selección visual > búsqueda > sintaxis > normal.

## Agregar un formateador nuevo

1. **Elegir el `style_id`** libre (p. ej. 6 para tipos) en `abi/tui_abi.h` y
   agregar el color en `draw_span()` (`win_editor.ll`).
2. **Definir el patrón en `ui.fxl`**:
   ```fexl
   \pat_type=(regex.compile "[A-Z][A-Za-z0-9_]*")
   ```
   Para sets más grandes usar `abregex.session` + `abregex.define` +
   `abregex.compile`.
3. **Emitir la línea en `emit_fmt`**:
   ```fexl
   say ["SPANS 6 " (regex.spans pat_type txt 512)]
   ```
4. **No hace falta tocar C**: el parser de `SPANS` ya es genérico y el
   `style_id` viaja en la línea.
5. **Probar**: abrir un archivo, ver los colores, editar una línea y
   confirmar que los spans se recalculan (el hook está en `dispatch()`,
   `flags & 1`).

## Cuándo se recalcula

- Al abrir un archivo (`fmt_send(ed)` tras `canvas_open`).
- Después de cada edición (`flags & 1` en `dispatch()`).

Si querés elegir el set por extensión del archivo, pasá la extensión como
byte extra del evento `FUI_FMT` y branchá en `ui.fxl` con `eq`.

## Trampas

- Los patrones se escriben como strings Fexl normales: `"key"` funciona;
  `~P key ~P` agrega espacios al patrón. Para literales con comillas usá
  `abregex.define` o un string con escapes.
- `regex.spans` con un patrón que solo matcha vacío (`[^"]*`) devuelve nada.
- El texto viaja por `/tmp/swi_fmt_input.txt`, no por el paquete de 4 bytes.
- Si el driver no está vivo, `fmt_send()` no hace nada y el editor sigue
  funcionando sin colores de sintaxis.
