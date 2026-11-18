# Handoff TUI — lo cerrado

Solo decisiones que el usuario dijo o confirmó. Las propuestas sin confirmar y las preguntas abiertas se dejaron afuera.

---

## 1. Dos motores

- Una cosa es el motor del editor y otra el motor de la TUI.
- El motor del editor es el de jotter (`textbuffer`, índice de líneas, `document`, `history`, `find`, `format`, regex y abregex, `fsio`). No sabe que existe ninguna interfaz.
- El motor de la TUI es `state`, `canvas`, `window`, `console`, `memory` y `rec/` (las consultas son de la TUI), más el C (`main`, `in`, `out`).
- La relación es en un solo sentido: el motor de la TUI usa al del editor; el del editor nunca sabe que el otro existe.
- Entre dos módulos IR se llama con `declare`, sin header. Los headers de `abi/` existen solo donde cambia el lenguaje (C ↔ IR).

## 2. Piezas

**C**
- `main.c`: lee los argumentos de línea de comandos y se los pasa al IR. Corre el loop.
- `in.c` / `in.h`: lee de termbox y entrega el evento ya masticado (tipo, tecla en un enum propio, carácter, resize).
- `out.c` / `out.h`: dibuja con escalares sobre termbox.
- Termbox vive en el C; el IR no lo conoce.

**IR**
- `state`: el modo activo, y la tabla (tecla + modo → acción).
- `canvas`: la superficie y el motor de ventanas (abrir, cerrar, minimizar, maximizar). Los mensajes van en `canvas`.
- `window`: una abstracción de ventana; las ventanas concretas son datastructs.
- `console`: la línea de comandos (`:`).
- `memory`: pertenece a la TUI. Guarda, carga y maneja la sesión: ventanas abiertas con su ruta y cursor, macros, último directorio y la apertura de archivos.

## 3. Entrada

- `in.c` entrega solo el evento; el IR lo convierte en una acción (un datastruct) mirando el modo.
- El loop espera con timeout cuando hay un escaneo en curso y sin timeout cuando no (la solución clásica).
- Los argumentos los lee `main.c`.

## 4. Modos

Es vim-like: NORMAL, INSERT, VISUAL y COMMAND.

- NORMAL → INSERT (`i`), solo si la ventana es editable; en una ventana de solo lectura se rechaza.
- NORMAL → VISUAL (`v`).
- NORMAL → COMMAND (`:` o `/`).
- VISUAL → COMMAND (`:`).
- INSERT, VISUAL y COMMAND → NORMAL con `Esc`. En COMMAND, `Esc` cancela y `Enter` ejecuta.

## 5. Salida

- Dos barras: una con las ventanas y otra con los comandos, más el canvas.
- Colorscheme configurable en compilación; 256 colores.
- Todos los atributos de texto.
- Caracteres anchos (CJK, emoji): fuera del POC.

## 6. Ventanas

Una abstracción de ventana (abstracta), con un tipo de contenido por clase. El motor de ventanas abre, cierra, minimiza y maximiza.

- **Archivos**: lista plana de un directorio con una cabecera de ruta; solo las extensiones que `rec/` entiende, con un atajo para ver todo. Tamaño y fecha serían una mejora posterior.
- **Registros**: el visor de formatos; FASTQ primero.
- **Editor**: editor de texto con formateador de colores.

El visor de formatos y el editor de texto son parte de la TUI.

## 7. Editor y archivos grandes

- Un solo backend: el archivo se lee por chunks sobre mmap. Nada se carga completo, ni para leer ni para editar. Los chunks contienen chunks.
- `TextBuffer` es un chunk, no el archivo, y se queda como está.
- Los ~100 MB de jotter eran arbitrarios; el valor real es mayor y esa decisión queda superada.
- Un solo `Document` se mueve sobre varios chunks.
- Unidad de chunk: se asume y se afina después. Constante única, 10 000 caracteres de partida.
- Una línea más larga que el chunk se corta.
- Guardado: los chunks sin tocar se copian desde el mmap, los editados se escriben desde su `TextBuffer`, y todo va a un archivo nuevo.
- El `Document` lleva la lista de chunks editados con su diferencia de tamaño, para traducir el offset original al actual.
- INSERT funciona en cualquier archivo de texto. BCF y BAM son solo lectura por formato. Existe una excepción por tamaño que todavía no se conoce.

## 8. Consola y scripting

- Fexl es el lenguaje de scripts de la consola, y abregex se expone como funciones de Fexl. Son dos intérpretes, y el intérprete de regex es parte de Fexl.
- Las consultas (`QUAL ~ {LQRUN} && DP > 10`) siguen siendo predicados compilados en el engine.
- Fexl y el shim se precompilan a bitcode (`.bc`) y se linkean con regex. El Makefile con debug y release ya funciona; la configuración del link es perilleo de Makefile, no arquitectura.
- El scripting cubre acciones de la UI y también programación: switches, booleanos e init tools.
  - Switches: una opción de la UI que se prende y apaga con un booleano, y un operador `switch`.
  - Booleanos: variables `true` / `false`.
  - Init tools: un archivo que se ejecuta al arrancar.
- Los scripts corren con la TUI y sin ella (por lotes, tipo CID), y se ejecutan desde la consola.
- El intérprete no vive en `console`: `console` solo lo llama.
- La fusión de Fexl con el motor de la TUI es otro tema, para otra sesión.

## 9. ABI y headers

- `abi/` no lleva `main`. Los mains viven en `gui/main.c` y `tui/main.c`.
- Tres headers: `core_abi.h` (el engine completo, para testing), `gui_abi.h` y `tui_abi.h`. No hay un `query_abi.h` aparte: lo de consultas va en el ABI de la TUI.

## 10. Lo que le falta al motor del editor para la TUI

- Capa de chunks (mmap, cargar un chunk, traducir offsets, guardar) y `Document` sobre varios chunks.
- `fsio_mmap` y `fsio_munmap`.
- Regex: entrada pura `(ptr, len)`, `rx_search_any`, `rx_count`, `rx_spans`, `abregex_define_runtime`, fix de `@` sin escapar y fix del `.rxc` (el bitset de `CHAR_CLASS`, bloqueante).
- Todo `rec/`: fuentes, consultas, resultset, `scan_step`, `rec_read`, `rec_field`, `rec_spans`.
- Shim `bgzf_zlib.c` con zlib para BCF y BAM comprimidos.

## 11. Entregado (sin compilar ni probar)

- `in.h` e `in.c`.
- `state.ll` (la máquina de modos).
- Un `Makefile` mínimo solo para `in.h` / `in.c`.
