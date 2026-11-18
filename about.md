# About: arquitectura de `swi`

## Idea central

El editor tiene dos dueños bien separados:

- **El motor IR/C** guarda los `Document` (el texto) y ejecuta cada tecla de
  edición. Nunca le pasa el buffer entero a Fexl.
- **El driver Fexl** (`ui.fxl`) decide `console_h`, `tabs_col`, `fileman_w`,
  `STATUS`, `LOG` y la tabla `BIND`. Es un proceso persistente: se arranca una
  vez y recibe eventos por pipes.

`main.c` es el pegamento: `in.c` entrega un `InEvent`, `state.ll` lo convierte
en `SwiAction`, y los módulos `win_editor.ll`/`console.ll` la ejecutan. Los
eventos estructurales (teclas de panel, resize, cambio de modo, `:w`, salida)
también viajan al driver como `EV ...` y vuelven como un frame terminado en
`.`.

## ¿Por qué `fexlswi` es un binario aparte?

`fexl-regex0` no puede evaluar strings dinámicos con `evaluate` (solo formas
quoted), así que la consola no podía correr dentro del driver. La solución fue:

- `ui.fxl` recibe `FUI_EVAL` y decide el `STATUS`/`LOG`.
- El intérprete real corre en un hijo `fexlswi0`, invocado con `fork/exec`.
- `eval.c` acumula las líneas de la consola en un script de sesión por PID y
  re-evalúa el script completo, así que las definiciones sobreviven.

El binario `fexlswi0` es **estático y autocontenido**: `swi` lo usa
dinámicamente como proceso, no como librería compartida. El sufijo `0` evita
que Fexl cargue `main.fxl`.

## ¿Por qué `swi` tiene módulos regex?

No son opcionales: `format.ll` (resaltado de búsqueda) llama a
`regex_compile`, `rx_charclass_*`, `rx_run` y `thread_*`, y `document.ll`
usa `replace_all`. Los patrones de usuario se evalúan en `fexlswi`, pero el
resaltado en pantalla se calcula dentro del editor con esos módulos.

## ¿Por qué no hay `swi0`?

Fue una analogía temporal con `fexlswi0`. Sin driver, `ui_sync` devolvía
siempre `fileman_w=0` y `console_h=3`, así que F2/F3 no abrían nada. Se
eliminó: hay un solo `swi` por perfil.

## Perfiles

| Target | Flags | Uso |
|---|---|---|
| `fast` | `-O0`, sin LTO | iterar con símbolos |
| `opt` | `-Oz` + LTO con `globaldce` | binario mínimo optimizado |
| `selfh` | `-Oz` + LTO sin pases extra | build desde fuentes |

Los tres compilan con target `x86_64-linux-musl`. `fexlswi` tiene sus propios
`opt`/`selfh`, ambos estáticos.

## Sesión

`memory.ll` es el único dueño de la sesión: un `E` por tab con cursor y foco,
un `A` con el índice activo, un `L` con el layout y `last_dir` con el cwd. Al
arrancar, el foco se fuerza al buffer para que las flechas no queden capturadas
por un panel abierto en la sesión anterior.

## Layout

`canvas_layout_panels()` en `canvas.ll` calcula los rects de tabs, buffer,
consola y file manager. Fexl pone los pesos; `main.c` solo dibuja con
`out_cell`/`out_fill`/`out_text`.

El panel de consola se dibuja **después** del editor para que no quede tapado,
y el file manager agrega `..` como primera entrada porque `fsio_list_dir`
excluye `.` y `..`.
