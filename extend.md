# Extender `swi` con Fexl

`swi` tiene una **consola Fexl** y un **driver Fexl persistente** que decide el
layout y los atajos. Este documento explica cómo usarlos, cómo agregar scripting
y si se puede hacer "en caliente".

> **Scripting ≠ extender la UI.** Scripting es cambiar valores/comportamiento
> desde Fexl (§2–§4). Extender la UI es agregar un panel, un widget o un modo
> nuevo, que implica tocar código C/IR, ABI, Makefile y tests: ver **§8**.

---

## 1. Modelo mental

```
termbox ──evento──> motor (IR/C) ──EV……──> ui.fxl (Fexl, persistente)
                         ^                       │
                         └── comandos del frame ─┘
```

- **El motor** es dueño de los `Document` (el texto) y de cada tecla de edición.
  Nunca le pasa el buffer a Fexl.
- **Fexl** es dueña del layout (alto de consola, ancho del file manager, tabs
  colapsadas), del texto de estado y de la tabla de atajos.
- El archivo que manda es `swi/ui.fxl`. Cambiarlo cambia la UI **sin tocar C**.

---

## 2. Usar la consola

1. `Ctrl+E` (o `F2`) abre/fija la consola y le da el foco.
2. Escribí una expresión Fexl, p. ej.:
   ```
   say "hola desde fexl"
   regex.count "a" "banana"
   ```
3. `Enter` la evalúa con `swi_eval` (preload `load_basic`, `load_output`,
   `load_regex`, `load_script`). La salida aparece en el log de la consola.
4. `Esc` devuelve el foco al buffer.

Atajos relacionados: `Ctrl+F` file manager, `Ctrl+B` colapsar tabs,
`Ctrl+T` tab nueva, `Ctrl+W` cerrar tab. Los `F2/F3/F4` también funcionan, pero
**F3 lo intercepta el escritorio** (abre el launcher), por eso existen los
equivalentes con Ctrl.

---

## 3. Protocolo (referencia)

### Motor → Fexl

Cada evento son **4 bytes**, sin lines ni parseo de strings:

```
[codigo_evento, console_h, tabs_col, fileman_w]
```

| Byte | Código | Evento |
|---|---|---|
| `i` | 105 | INIT (al arrancar) |
| `2` | 50 | toggle consola |
| `3` | 51 | toggle file manager |
| `4` | 52 | toggle tabs colapsadas |
| `m` | 109 | cambio de modo (`console_h` trae 0..3) |
| `c` | 99 | comando ejecutado |
| `t` | 116 | cambio de tabs |
| `q` | 113 | salir |

Los tres bytes de estado los guarda el motor; Fexl los recibe, los transforma
y los devuelve. Por eso el driver puede ser **stateless**: no necesita guardar
estado entre eventos (sí es un proceso persistente, pero cada evento viaja
completo).

### Fexl → motor

Frame de líneas terminado con `.` y `fflush stdout`:

```
CONSOLE_H 03        ; 0 = off, 3 = brief, 10 = extended
TABS_COL 00         ; 0 = expandido, 1 = colapsado
FILEMAN_W 00        ; 0 = off, 40 = ancho del panel
STATUS NORMAL       ; texto libre (una palabra)
LOG CMD             ; mensaje para el log
BIND C-E console.toggle
...
.
```

Los `BIND` se reenvían **en cada frame** y `main.c` los usa de verdad:
`has_bind("console.toggle")` decide si la tecla actúa. Si quitás un `BIND` de
`ui.fxl`, ese atajo deja de funcionar aunque la tecla siga en el código. Si el
driver no está disponible (`nbind == 0`), se usa el mapping histórico por
robustez. Ver §5 para cablear uno nuevo de punta a punta.

---

## 4. Cómo agregar scripting

### 4.1 Cambiar el layout

Editá `swi/ui.fxl`. Ejemplo: consola siempre extendida y file manager más
ancho:

```fexl
\ch2=10                      ; en vez del toggle
\fw2=((eq ce 51) 60 0)       ; F3 -> 60 columnas
```

Atención: `num` (líneas 16–23) solo mapea `0,1,2,3,10,40` porque este build de
Fexl no tiene `as_str`. Si querés otro valor (p. ej. 60), agregalo:

```fexl
((eq n 60) "60" ...)
```

### 4.2 Cambiar el texto de estado

`STATUS` acepta una palabra (sin espacios, porque el C lo lee con `%63s`):

```fexl
\st2="LISTO"
```

### 4.3 Usar otro script sin recompilar

La ruta se inyecta en compilación con `UI_SCRIPT_DEF` en `swi/Makefile`:

```make
UI_SCRIPT_DEF := -DSWI_UI_SCRIPT="\"$(abspath $(CURDIR)/ui.fxl)\""
```

Cambiala por tu archivo y recompilá. Para **no recompilar**, podés pasarle una
variable de entorno a `main.c` (no implementado hoy): usar `getenv("SWI_UI")`
y default a `SWI_UI_SCRIPT`.

### 4.4 Requisitos del script

`fexlswi0` **no** trae los builtins preloadados. Todo script debe empezar:

```fexl
load_basic
load_output
load_cmp
load_file
load_str
load_extend
load_regex
load_script
evaluate \;
```

`evaluate \;` evalúa el resto del archivo con esos módulos en scope. Sin eso
aparecen `Undefined symbol say/on line N`.

---

## 5. Cablear una acción nueva (BIND de verdad)

Hoy los BIND son informativos. Para que un BIND nuevo **ejecute** una acción:

1. **`ui.fxl`**: agregar `say "BIND C-X mi.accion"` dentro de `emit`.
2. **`tui/fexl_ui.h`**: agregar el código de evento, p. ej. `FUI_MI = 'x'`.
3. **`tui/fexl_ui.c`**: nada (el paquete es genérico).
4. **`tui/main.c`**: en el loop, antes de `state_step`, manejar la tecla:
   ```c
   if (ev.type == IN_EV_CHAR && (ev.mods & IN_MOD_CTRL) && ev.ch == 'x') {
       mi_accion();                       /* C o IR */
       ui_sync(FUI_MI, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
       continue;
   }
   ```
5. Agregar un test en `swi/test/` y correr `make test`.

Para acciones que cambien layout, la lógica va en `ui.fxl` (el `case` del
evento) y el C solo aplica lo que devuelve el frame.

---

## 6. Hot reload (ya implementado)

El loop de `main.c` guarda `st_mtime` **y** `st_mtim.tv_nsec` de `ui.fxl` con
`stat()`, así que detecta ediciones dentro del mismo segundo. Si cambió:

```c
fexl_ui_stop();
fexl_ui_start(SWI_FEXL_BIN, SWI_UI_SCRIPT);
ui_sync(FUI_INIT, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
log_add("ui.fxl recargado");
```

Como el estado vive en C, el editor sigue donde estaba: texto, cursor, tabs,
foco, layout y directorio se conservan. Los BIND del nuevo script quedan
activos en el primer frame. Editar `ui.fxl` **no recompila** (se sacó del
Makefile como dependencia de `main.o`; solo se embebe su ruta).

Si `ui.fxl` tiene un error, `fexl_ui_event()` captura la línea `Undefined
symbol`/`syntax error`, conserva el último frame bueno y reporta el error en el
log; el editor no cambia de layout por un script roto. El reintento es un loop
acotado a dos intentos, no recursión.

Las definiciones de la consola sí sobreviven al reload: `eval.c` guarda un
script de sesión por PID con todo lo escrito y lo re-evalúa completo. Cada
`Enter` pasa primero por el evento `FUI_EVAL`, así que el driver también decide
el `STATUS` (`EVAL`) y el `LOG`. Lo que no sobrevive es una definición hecha
directamente dentro del driver (`\\mi_fn=...` en `ui.fxl`), porque el intérprete
se reinicia.

---

## 7. Trampas conocidas

- `as_str` no existe en este build: usá `num` o literales.
- `fflush stdout` es obligatorio al final de cada frame; sin él la salida
  queda buffered y el motor espera para siempre.
- El binario `fexlswi0` se invoca por **ruta absoluta** (`EVAL_DEF`) y el
  script por **ruta absoluta** (`UI_SCRIPT_DEF`). Si `main.o` se compiló con la
  ruta relativa de fallback (`../Fexl/...`), el driver muere con `exit 127` al
  arrancar desde fuera de `swi/`. Forzá el rebuild si tocás el Makefile.
- `fexl_ui_event` reinicia el driver automáticamente si el hijo murió, e
  ignora `SIGPIPE`, así que un fallo del script no tumba el editor.
- `eval.c` usa un script de sesión y un temporal de salida con PID
  (`/tmp/swi_fexl_session_<pid>.fxl`, `/tmp/swi_eval_<pid>.out`), lanza el
  intérprete con `fork/exec` (sin shell) y reinicia la sesión al arrancar.
- El protocolo tiene un evento `FUI_EVAL` ('x'); `ui.fxl` responde con
  `STATUS EVAL` y el motor agrega la salida real al log.
- Los buffers nuevos usan `doc_new()` (en memoria) y una ruta única por
  PID/contador: no truncan `/tmp/swi_untitled.txt` al abrir.
- La sesión la escribe C con `memory.ll` (tabs, cursor, foco, layout, cwd);
  Fexl solo transforma el estado que recibe en cada evento.
- Los eventos son bytes: si agregás un código nuevo, no puede ser `10` (LF),
  porque se confundiría con el final de línea del frame.

---

## 8. Extender la UI (esto NO es scripting)

Scripting cambia **valores** que el motor ya sabe interpretar. Extender la UI
agrega **cosa nueva**: un panel, un widget, un modo, una forma de mostrar
datos. Eso no se hace desde `ui.fxl` solo: se agrega código y se conecta al
protocolo.

### 8.1 Mapa de archivos

| Archivo | Para qué sirve al extender |
|---|---|
| `tui/out.h`, `tui/out.c` | Única forma de dibujar: `out_cell`, `out_fill`, `out_text`, `out_cursor`. Paleta `OUT_*` y atributos `OUT_ATTR_*`. |
| `tui/in.h`, `tui/in.c` | Eventos de entrada: `IN_EV_KEY/CHAR/RESIZE`, códigos `IN_KEY_*`. |
| `tui/state.ll` | Máquina de modos (0 NORMAL, 1 INSERT, 2 VISUAL, 3 COMMAND) y `SwiAction`. |
| `tui/win_editor.ll` | Dibujo del buffer, cursor, gutter, resaltado. |
| `tui/console.ll` | Línea de comandos y builtins (`:w`, `:e`, etc.). |
| `abi/tui_abi.h` | Espejo en C de los structs usados por el IR. Si agregás struct IR, agregalo acá. |
| `tui/canvas.ll` | `canvas_layout_panels()`: geometría de tabs/buffer/consola/file manager. |
| `tui/main.c` | Dibujo de tabs, consola y file manager; loop de foco; sesión. |
| `ui.fxl` | Dueño del layout: decide cuánto espacio ocupa cada panel. |
| `tui/fexl_ui.h/.c` | `UiFrame`: lo que Fexl devuelve al motor. |
| `Makefile` | Listas `TUI_LL`, `ENGINE_LL`, `ALL_C`, targets de test. |
| `test/` | Un arnés por módulo IR nuevo. |

### 8.2 Dos caminos

**A) Chrome de UI en C (rápido).** Si el panel es puramente presentación
(tabs, consola, file manager hoy), lo implementás directo en `main.c` con un
`static struct`, dibujás con `out_text`/`out_fill` y manejás teclas en el loop.
No tiene test IR separado, pero es válido y es lo que ya hace el código actual.

**B) Módulo IR (recomendado para lógica real).** Si el panel tiene estado,
búsqueda, navegación o formateo, hacelo como módulo `.ll` para que entre en los
dos perfiles (fast y opt con LTO) y tenga su propio test.

### 8.3 Receta: agregar un panel "outline"

1. **ABI.** En `abi/tui_abi.h` declará el struct y las funciones:
   ```c
   extern void *outline_new(void);
   extern void  outline_destroy(void *o);
   extern int   outline_step(void *o, InEvent *ev);
   extern void  outline_draw(void *o, int32_t x, int32_t y,
                             int32_t w, int32_t h);
   ```

2. **Módulo IR** `tui/outline.ll`: mismo patrón que `win_editor.ll` —
   `define ptr @outline_new()`, `define void @outline_draw(...)`, con declares
   a `out_cell`/`out_text`. Compilación por módulo ya la hace la regla genérica
   `$(BUILD)/%.o: %.ll` con `opt -passes=verify` + `llc`.

3. **Test separado** `test/test_outline.c` y targets en el `Makefile`:
   ```make
   TUI_LL := state window canvas win_editor console memory outline
   $(BUILD)/test_outline: $(BUILD)/test_outline.o $(BUILD)/outline.o
       $(CLANG) $^ -o $@
   test: ... $(BUILD)/test_outline
       ./$(BUILD)/test_outline
   ```
   Verificá el módulo solo antes de integrar:
   ```bash
   opt-21 -passes=verify -disable-output tui/outline.ll
   ./build/test_outline
   ```

4. **Integración en `main.c`**: instanciar, dibujar en su rect y darle foco:
   ```c
   void *outline = outline_new();
   /* en draw(): el rect sale del layout, no hardcodeado */
   outline_draw(outline, ol_r.x, ol_r.y, ol_r.w, ol_r.h);
   /* en el loop: g_focus = 3 para el outline */
   ```
   Agregá un valor a `g_focus` (hoy 0=buffer, 1=consola, 2=file manager) y una
   rama en el loop antes de `state_step`.

5. **Protocolo Fexl.** Si querés que Fexl decida el tamaño del panel:
   - `fexl_ui.h`: agregá campo `int32_t outline_h` a `UiFrame`.
   - La respuesta del frame pasa a 5 bytes: `[ev, ch, tc, fw, oh]`. Actualizá
     `fexl_ui_event()` y **todas** las llamadas a `ui_sync(...)`.
   - `ui.fxl`: leer un quinto `fgetc` y emitir `say ["OUTLINE_H " (num oh)]`.
   - `fexl_ui.c`: parser de la nueva línea con `sscanf`.
   - `main.c`: usar `g_ui.outline_h` al calcular los rects.

6. **Selftest**: agregá un `SELF_CHECK` en `selftest()` y corré `make test`.

### 8.4 Modo nuevo vs. foco

- Si el panel **reemplaza la edición** (como COMMAND), agregá un modo en
  `state.ll`: cambia el `switch i32 %mode`, el enum en C y los tests de
  `test_state`. Es más invasivo y hay que actualizar la barra de estado.
- Si el panel **es un overlay con su propio foco** (como consola/file manager),
  usá `g_focus` en C: no tocás `state.ll` y la edición queda intacta. Es lo
  que hicimos acá.

### 8.5 Qué se puede hacer "en caliente" y qué no

| Cambio | ¿En caliente? |
|---|---|
| Alto de consola, ancho de file manager, texto de estado, BIND en `ui.fxl` | Sí, con el reload de §6 |
| Agregar un panel nuevo (C/IR), un modo o un builtin de consola | No: requiere recompilar |
| Agregar un valor numérico nuevo al protocolo | No: requiere recompilar C y Fexl |

La regla: **si el cambio es solo un valor que el motor ya entiende**, podés
hacerlo en caliente; **si agregás una palabra nueva al protocolo o código
nuevo**, hay que recompilar.
