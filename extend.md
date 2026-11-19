# Extender la UI de `swi`

Este documento es para agregar **cosa nueva**: un panel, un widget, un modo, un
builtin de consola o una tecla. Eso implica tocar C/IR, ABI, Makefile y tests.

> **Extender la UI ≠ scripting.** Scripting es cambiar valores que el motor ya
> entiende (layout, BIND, STATUS, patrones de color) desde `ui.fxl`: ver
> **`scripting.md`**. Acá se explica cómo enseñarle al motor un valor, una
> tecla o un panel nuevo.

---

## 1. Modelo mental

```
termbox ──InEvent──> state.ll ──SwiAction──> win_editor.ll / console.ll
                          │                          │
                          └── ui_sync() ──> ui.fxl ──┘ (decide layout/BIND)
```

- **`in.c`** entrega eventos ya masticados (`IN_EV_KEY/CHAR/RESIZE`,
  códigos `IN_KEY_*`).
- **`state.ll`** es la máquina de modos (0 NORMAL, 1 INSERT, 2 VISUAL,
  3 COMMAND) y produce un `SwiAction`.
- **`win_editor.ll` / `console.ll`** ejecutan la acción sobre el `Document`.
- **`main.c`** es el pegamento: loop, foco, tabs, dibujo de paneles y sesión.
- **`ui.fxl`** decide cuánto espacio ocupa cada panel y qué atajos están
  activos. El protocolo completo está en `scripting.md`.

Regla de oro: **el motor de edición nunca depende de la TUI**, y la TUI nunca
mete código de edición en `main.c`. Si una acción tiene estado, va en un módulo
IR con su test.

---

## 2. Mapa de archivos

| Archivo | Para qué sirve al extender |
|---|---|
| `tui/out.h`, `tui/out.c` | Única forma de dibujar: `out_cell`, `out_fill`, `out_text`, `out_cursor`. Paleta `OUT_*`, atributos `OUT_ATTR_*`. |
| `tui/in.h`, `tui/in.c` | Eventos de entrada: tipos `IN_EV_*`, códigos `IN_KEY_*`, mods `IN_MOD_*`. |
| `tui/state.ll` | Modo activo, `state_step()`, tabla tecla+modo → `SwiAction`. |
| `tui/win_editor.ll` | Dibujo del buffer, cursor, gutter, movimientos y resaltado. Lee el texto con `doc_read()`. |
| `tui/console.ll` | Línea de comandos y builtins (`:w`, `:e`, …). |
| `tui/eval.ll` | Puente batch a Fexl: sesión por PID y `fork/exec`. |
| `tui/shell.ll` | Log, foco, BIND, tabs, sesión, `:swd`, `fmt_send` y toggles (migrados de `main.c`). |
| `tui/canvas.ll` | `canvas_layout_panels()`: geometría de tabs/buffer/consola/file manager. |
| `tui/fileman.ll` | Dueño del cwd, listado, selección y scroll del file manager. |
| `tui/memory.ll` | Sesión: tabs, cursor, foco, layout, `last_dir`. |
| `tui/main.c` | Dibujo de tabs, consola y file manager; loop de foco; hot reload; selftest. |
| `tui/fexl_ui.ll` | `UiFrame`: lo que Fexl devuelve al motor. Parser de `SPANS`/`BIND`. |
| `abi/tui_abi.h` | Espejo en C de los structs y funciones del IR. Si agregás algo al IR, agregalo acá. |
| `core/document.ll` | Dueño del texto: `doc_read`, `doc_length`, `doc_insert`, `doc_delete`. |
| `ui.fxl` | Dueño del layout y de los BIND. |
| `Makefile` | Listas `TUI_LL`, `ENGINE_LL`, `REGEX_LL`, `ALL_C` y targets de test. |
| `test/` | Un arnés por módulo IR nuevo. |

---

## 3. Dos caminos

**A) Chrome de UI en C (rápido).** Si el panel es puramente presentación
(tabs, consola y file manager hoy), implementalo directo en `main.c` con un
`static struct`, dibujá con `out_text`/`out_fill` y manejá teclas en el loop. No
tiene test IR separado, pero es válido y es lo que hace el código actual.

**B) Módulo IR (recomendado para lógica real).** Si el panel tiene estado,
búsqueda, navegación o formateo, hacelo como módulo `.ll`: entra en los cuatro
perfiles (`fast`, `opt`, `opt-full`, `selfh`) y tiene su propio test.

---

## 4. Receta: agregar un panel "outline"

### 4.1 ABI

En `abi/tui_abi.h` declará el struct y las funciones:

```c
extern void *outline_new(void);
extern void  outline_destroy(void *o);
extern int   outline_step(void *o, InEvent *ev);
extern void  outline_draw(void *o, int32_t x, int32_t y,
                          int32_t w, int32_t h);
```

### 4.2 Módulo IR

`tui/outline.ll`, mismo patrón que `win_editor.ll`:

```llvm
%Outline = type { ptr, i64 }        ; items, seleccion

define ptr @outline_new() { ... }
define void @outline_draw(ptr %o, i32 %x, i32 %y, i32 %w, i32 %h) {
  ; declare i32 @out_cell(i32, i32, i32, i32, i32, i32)
  ...
}
```

La regla genérica `$(BUILD)/%.o: %.ll` ya compila cualquier `.ll` de `tui/`
con `opt -passes=verify` + `llc`. Solo agregá el nombre a `TUI_LL`.

### 4.3 Test separado

```make
TUI_LL := state window canvas win_editor console memory outline

$(BUILD)/test_outline.o: test/test_outline.c tui/in.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_outline: $(BUILD)/test_outline.o $(BUILD)/outline.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

test: ... $(BUILD)/test_outline
	./$(BUILD)/test_outline
```

Verificá el módulo solo antes de integrar:

```bash
opt-21 -passes=verify -disable-output -mtriple=x86_64-linux-musl tui/outline.ll
make test && ./build/test_outline
```

### 4.4 Integración en `main.c`

```c
void *outline = outline_new();

/* en draw(): el rect sale del layout, nunca hardcodeado */
Rect ol = g_ui.rects[SWI_PANEL_OUTLINE];
outline_draw(outline, ol.x, ol.y, ol.w, ol.h);
```

Agregá un valor a `g_focus` (hoy 0=buffer, 1=consola, 2=file manager) y una
rama en el loop **antes** de `state_step`, para que la tecla no llegue al
editor:

```c
if (g_focus == 3 && outline_step(outline, &ev)) {
    ui_sync(FUI_OUTLINE, ...);
    continue;
}
```

### 4.5 Protocolo Fexl

Si querés que Fexl decida el tamaño del panel:

1. `tui/fexl_ui.h`: campo `int32_t outline_h` en `UiFrame`.
2. El paquete pasa a 5 bytes: `[ev, ch, tc, fw, oh]`. Actualizá
   `fexl_ui_event()` y **todas** las llamadas a `ui_sync(...)` (son ~10).
3. `ui.fxl`: leer un quinto `fgetc` y emitir `say ["OUTLINE_H " (num oh)]`,
   agregando `60` a la tabla `num`.
4. `fexl_ui.ll`: parser de la nueva línea con `sscanf`/`strtol`.
5. `main.c`: usar `g_ui.outline_h` en `canvas_layout_panels()`.

Recordá la regla del protocolo: un código nuevo no puede ser `10` (LF).

### 4.6 Selftest

Agregá un `SELF_CHECK` en `selftest()` (`tui/main.c`) y corré
`make test test-opt test-selfh`.

---

## 5. Agregar un builtin de consola (`:foo`)

Los builtins viven en `console_execute()` (`tui/console.ll`). Hoy el chain es:

```
:w → do_save → win_editor_save
:q → do_quit → win_editor_request_quit
:q! / :wq / :w <ruta> / :e <ruta>
:swd / :swd <ruta> → swi_set_wd      (directorio del file manager o ruta)
:pwd               → swi_print_wd    (solo muestra, no cambia)
/… → win_editor_search
otro → callback eval (Fexl) en el bloque `unknown`
```

`:swd` es un ejemplo real del patrón de abajo: `swi_set_wd()` está en
`tui/main.c` (no `static`, porque `console.ll` lo declara con `declare`) y
usa `fsio_chdir()` de `fsio/fsio_posix.ll`. Con `path == NULL` toma
`g_fm_cwd`; si no, usa la ruta dada. Normaliza con `getcwd()`, refresca el
file manager y loggea `wd: <abs>`. `session_load_all()` lo llama en modo
silencioso para restaurar el wd guardado en la sesión.

### 5.1 Pasos

1. **Constante** en `tui/console.ll`:
   ```llvm
   @CMD_FOO = private global [4 x i8] c"foo\00"
   ```

2. **Comparación** en `cmd_colon`, insertada en el chain de `strcmp` antes de
   `unknown` (el orden importa: `:e` y `:w` tienen prefijo, por eso van
   después de los exactos):
   ```llvm
   %rf = call i32 @strcmp(ptr %buf, ptr @CMD_FOO)
   %isf = icmp eq i32 %rf, 0
   br i1 %isf, label %do_foo, label %saveas_chk
   ```

3. **Rama de ejecución**:
   ```llvm
   do_foo:
     %r = call i32 @win_editor_foo(ptr %ed)
     ret i32 1                ; 1 = comando consumido
   ```

4. **Declaración** en `abi/tui_abi.h` si `win_editor_foo` es nuevo:
   ```c
   extern int32_t win_editor_foo(void *ed);
   ```

5. **Test**: agregá un caso en `test/test_console.c` con un stub de
   `win_editor_foo` y verificá que `console_execute()` devuelve 1 y que no
   cae al `eval` callback (`n_eval` queda en 0).

6. **Documentación**: una fila en la tabla de comandos de `cheatsheet.md`.

### 5.2 Trampas

- Si tu builtin tiene argumentos (`:w <ruta>`), parseá desde `%buf + 2` como
  hace `do_saveas`; no hardcodes el offset si el prefijo puede cambiar.
- Cualquier texto que no matchee un builtin cae en `unknown` y se manda a
  Fexl. Si querés que `:foo` **no** vaya a Fexl, consumilo con `ret i32 1`.
- `FUI_COMMAND` se emite en `main.c` cuando `console_execute()` devuelve 1;
  el driver Fexl solo decide el `LOG`.

---

## 6. Cablear una tecla nueva

Para una tecla que no existía (p. ej. `K` para "matar hasta el final"):

1. **`tui/in.h`**: si es una tecla especial, agregá el código al enum `InKey`;
   si es un carácter, no hace falta.
2. **`tui/state.ll`**: en `motion_of()` / `state_step()`, agregá la entrada a
   la tabla tecla+modo → acción. Usá `act(ptr %out, i32 %kind, ...)` con un
   `SWI_ACT_*` nuevo.
3. **`abi/tui_abi.h`**: agregá el valor al enum `SwiAction`.
4. **`tui/win_editor.ll`**: en `win_editor_step()`, agregá un `switch` para el
   kind nuevo y llamá a tu función IR.
5. **`test/test_state.c`**: verificá que con la tecla y el modo correctos se
   emite la acción esperada (y que en otro modo no).
6. **`test/test_win_editor.c`**: verificá el efecto sobre el `Document` con
   `doc_read()`/`doc_length()`.

Si la tecla es un atajo de **panel** (consola, file manager, tabs), no va en
`state.ll`: se maneja en el loop de `main.c` y se declara con un `BIND` en
`ui.fxl` (ver `scripting.md`, §6).

---

## 7. Extender el file manager

El file manager vive en **`tui/fileman.ll`** (esto es lo que migró de C a IR).
`main.c` solo crea el objeto, traduce las teclas del loop y dibuja en su rect:

| Función (IR) | Rol |
|---|---|
| `fileman_new/destroy` | ciclo de vida del struct `{ cwd, names, n, sel, top }` |
| `fileman_load` | listado vía `fsio_list_dir`; `..` siempre es la primera entrada |
| `fileman_set_sel` | selección con clamp |
| `fileman_scroll(fm, rows)` | ajusta `top` para que la selección quede visible |
| `fileman_chdir` | valida con `chdir`, normaliza con `getcwd`, recarga |
| `fileman_is_dir` | usa `fsio_list_dir` para decidir si una entrada es directorio |
| `fileman_parent` | sube un nivel (resuelve rutas relativas antes de recortar) |
| `fileman_draw` | cabecera `[files] <cwd>  sel/n` y entradas desde `top` |

En `main.c` quedan `fileman_open()` (abre un archivo o tab), `toggle_fileman()`
(`ui_sync(FUI_FILEMAN)` + `fileman_load` + `set_focus(2)`) y `g_fm_rows`, que se
calcula en `draw()` y usa el loop para `PageUp/Down`.

Para agregar, por ejemplo, orden por fecha:

1. `fsio_list_dir` entrega solo nombres; necesitás metadatos. Agregá un
   módulo IR `fsio/fsio_stat.ll` (o extendé `fsio_list_dir`) con `declare` en
   `abi/tui_abi.h`. Ojo: llamar a `stat(2)` desde IR con musl dio problemas
   en este build; `fsio_chdir`/`fsio_list_dir` son alternativas probadas.
2. Ordená en `fileman_load()` (IR) **después** de traer el listado, no en el
   IR de `fsio` (ese módulo no debe saber de UI).
3. Agregá una tecla en el loop de `main.c` (con su `BIND` en `ui.fxl`) para
   cambiar el criterio de orden.
4. Test: `test/test_fileman.c` ya cubre listado, scroll y dibujo;sumá ahí el
   caso de orden nuevo.

---

## 8. Foco y paneles

`g_focus` decide quién recibe las teclas:

| Valor | Panel |
|---|---|
| 0 | buffer (editor) |
| 1 | consola |
| 2 | file manager |
| 3 | panel nuevo (ej. outline) |

Reglas:

- El foco **siempre arranca en 0** al crear un editor. `memory.ll` guarda el
  foco de la sesión, pero `main.c` lo fuerza al buffer al arrancar para que
  las flechas no queden capturadas por un panel abierto antes.
- `Esc` en un panel vuelve al buffer; en COMMAND cancela.
- Un panel con foco propio es un **overlay**: no tocás `state.ll` y la edición
  sigue intacta. Es preferible a un modo nuevo.

---

## 9. Depuración

```bash
# 1) verificar un módulo IR aislado antes de linkear
opt-21 -passes=verify -disable-output -mtriple=x86_64-linux-musl tui/outline.ll

# 2) test del módulo
make test && ./build/test_outline

# 3) selftest de integración (consola, Fexl, edición)
./build/swi --selftest

# 4) todos los perfiles
make test && make test-opt && make MODE=opt-full test && make test-selfh
```

Si el driver Fexl no responde, mirá el log de la consola y
`fexlswi/bin/fexlswi0`. Si el módulo IR falla en `opt-full` pero no en `fast`,
buscá símbolos sin `declare` (LTO con `globaldce` los delata).

Para probar cambios de `ui.fxl` sin recompilar: editá el archivo y el hot
reload de `main.c` reinicia el driver en el próximo evento. Ver
`scripting.md`, §3.

---

## 10. Modo nuevo vs. foco

- Si el panel **reemplaza la edición** (como COMMAND), agregá un modo en
  `state.ll`: cambia el `switch i32 %mode`, el enum en C, la barra de estado y
  los tests de `test_state`. Es más invasivo.
- Si el panel **es un overlay con foco propio**, usá `g_focus` en C: no tocás
  `state.ll` y la edición queda intacta. Es lo que hicimos para consola y file
  manager.

---

## 11. Qué se puede hacer "en caliente"

| Cambio | ¿En caliente? |
|---|---|
| Alto de consola, ancho de file manager, STATUS, LOG, BIND, patrones de color | Sí: editar `ui.fxl` (reload de `scripting.md`, §3) |
| Definiciones en la consola | Sí: persisten en el script de sesión por PID |
| Panel nuevo (C/IR), modo, builtin de consola o tecla | No: requiere recompilar |
| Valor numérico nuevo en el protocolo (5° byte, etc.) | No: requiere recompilar C y Fexl |

La regla: **si el cambio es solo un valor que el motor ya entiende**, es en
caliente; **si agregás una palabra nueva al protocolo o código nuevo**, hay
que recompilar.

---

## 12. Checklist antes de commit

- [ ] `declare` en el módulo IR y espejo en `abi/tui_abi.h`.
- [ ] Nombre agregado a `TUI_LL` o `ENGINE_LL` en el `Makefile`.
- [ ] `opt-21 -passes=verify` limpio para cada `.ll` tocado.
- [ ] Test separado en `test/` y target en `make test`.
- [ ] `SELF_CHECK` en `selftest()` si cambia el comportamiento integrado.
- [ ] `BIND` en `ui.fxl` si la acción se activa con tecla.
- [ ] Documentación: `cheatsheet.md` (teclas) y/o `scripting.md` (BIND).
- [ ] `make test test-opt test-selfh` y `make MODE=opt-full test` en verde.
- [ ] `make install` deja `build/swi` + `build/fexlswi/`.

Ver también: `scripting.md` (Fexl, protocolo y regex) y `addformat.md`
(formateadores de sintaxis).
