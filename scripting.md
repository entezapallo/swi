# Scripting en `swi`: Fexl + regex

`swi` tiene **dos intérpretes con trabajos distintos**:

- `fexlswi0` corre como **proceso hijo persistente**. Decide el layout, los
  atajos y los formateadores, y evalúa lo que escribís en la consola.
- El motor IR/C corre **dentro de `swi`**. Es dueño del texto y ejecuta cada
  tecla de edición. Nunca le pasa el buffer entero a Fexl.

Este documento explica el scripting (lo que podés cambiar **sin recompilar**).
Para agregar paneles, modos o comandos nuevos, ver `extend.md`. Para patrones
de color, ver `addformat.md`.

---

## 1. Por qué hay un binario Fexl aparte

El intérprete original `fexl-regex0` no puede evaluar strings dinámicos con
`evaluate` (solo formas quoted). Por eso la consola no podía correr dentro del
driver: la expresión que escribís llega como texto en runtime.

La solución son **dos productos** generados desde las mismas fuentes:

| Producto | Diferencia | Quién lo usa |
|---|---|---|
| `bin/fexlswi` / `bin/fexlswi0` | ELF standalone; el sufijo `0` evita cargar `main.fxl` | `fast`, pruebas y `swi fast` |
| `lib/fexlswi_lib.bc` | el mismo intérprete sin `internalize`/`globaldce`, con `main -> fexl_main` | `swi` en los perfiles LTO, linkeado dentro del ELF |

En los perfiles LTO hay **un solo ELF**: `main.c` se compila como `swi_main` y un
`dispatch.c` generado elige `fexl_main` o `swi_main` por `basename(argv[0])`.
`fexlswi0` es un symlink a `swi`, así que el driver sigue siendo un proceso
hijo con el mismo binario. En `fast` sigue habiendo dos ELF separados.

`fexlswi.bc` / `fexlswi_lib.bc` = intérprete Fexl + tipo `regex` + tipo
`rxsession` + los 7 módulos IR del motor. Todo es **musl dinámico**, igual que
`swi` (no se usa como librería compartida: se invoca como proceso, o se linkea
como bitcode en el fusionado). Ver `fexlswi-llvm/BUILD.md`.

El path se inyecta en compilación (`EVAL_DEF` en el Makefile raíz) con valor
absoluto: `fexlswi-llvm/bin/fexlswi0` en `fast` y `build/fexlswi/bin/fexlswi0`
(symlink) en los perfiles LTO. Se puede sobrescribir con
`make FEXL=/otro/fexlswi0`.

---

## 2. Cómo se comunican

Dos canales, ninguno con JSON ni parseo de strings en el camino caliente:

### Motor → Fexl

**4 bytes por evento**, sin `newline`:

```
[codigo_evento, console_h, tabs_col, fileman_w]
```

| Byte | Código | Evento (`tui/fexl_ui.h`) |
|---|---|---|
| `i` | 105 | `FUI_INIT` — al arrancar |
| `2` | 50 | `FUI_CONSOLE` — toggle de consola |
| `3` | 51 | `FUI_FILEMAN` — toggle de file manager |
| `4` | 52 | `FUI_TABS` — colapsar tabs |
| `m` | 109 | `FUI_MODE` — cambio de modo (`console_h` = 0..3) |
| `c` | 99 | `FUI_COMMAND` — comando ejecutado |
| `t` | 116 | `FUI_TABCHG` — cambio de tabs |
| `x` | 120 | `FUI_EVAL` — línea de consola enviada |
| `F` | 70 | `FUI_FMT` — pedir spans de formato |
| `q` | 113 | `FUI_QUIT` — salir |

Los tres bytes de estado son **los que tiene el motor**; Fexl los recibe, los
transforma y los devuelve. El driver es stateless respecto del layout: cada
evento viaja completo.

### Fexl → motor

Un frame de líneas terminado con `.` y `fflush stdout`:

```
CONSOLE_H 03        ; 0 = off, 3 = brief, 10 = extended
TABS_COL 00         ; 0 = expandido, 1 = colapsado
FILEMAN_W 00        ; 0 = off, 40 = ancho del panel
STATUS NORMAL       ; texto libre de una palabra
LOG CMD             ; mensaje para el log
BIND C-E console.toggle
BIND C-F fileman.toggle
...
.
```

`fexl_ui.ll` parsea esas líneas en `UiFrame` (`abi/tui_abi.h`): `console_h`,
`tabs_col`, `fileman_w`, `status`, `log`, `err`, `span[]` y `bind[]`.

Los `BIND` **son autoridad**: `main.c` pregunta `has_bind("console.toggle")`
antes de actuar. Si quitás un `BIND` de `ui.fxl`, ese atajo deja de funcionar
aunque la tecla siga en el código. Si el driver no está vivo (`nbind == 0`), se
usa el mapping histórico por robustez.

---

## 3. La consola Fexl

`Ctrl+E` (o `F2`) fija la consola y le da el foco. Escribí una expresión y
`Enter` la evalúa con `swi_eval`:

```
> say "hola desde fexl"
> \x=41
> say x
> regex.count "a" "banana"
```

Cada línea se agrega a un **script de sesión por PID**
(`/tmp/swi_fexl_session_<pid>.fxl`) y se re-evalúa el script **completo**, así
que las definiciones (`\x=...`) sobreviven entre comandos. La salida se captura
en `/tmp/swi_eval_<pid>.out` y se muestra en el log. El intérprete se lanza con
`fork/exec` directo (sin shell). Como el hijo hereda el cwd, el comando
`:swd` (builtin de la consola) cambia el wd del proceso y, con él, el de todos
los scripts Fexl que corren después. `:swd` sin ruta toma el directorio que
muestra el file manager; `:pwd` lo muestra sin cambiarlo. El wd se restaura de
la sesión al arrancar.

`Esc` devuelve el foco al buffer. `Backspace` borra.

### Preloads

`fexlswi0` **no** trae los builtins precargados. Todo script —incluida la
consola— arranca con:

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
aparece `Undefined symbol say on line N`.

### Hot reload

`main.c` guarda `st_mtime` **y** `st_mtim.tv_nsec` de `ui.fxl`, así que detecta
ediciones dentro del mismo segundo. Al cambiar:

```c
fexl_ui_stop();
fexl_ui_start(SWI_FEXL_BIN, SWI_UI_SCRIPT);
ui_sync(FUI_INIT, ...);
log_add("ui.fxl recargado");
```

El editor sigue donde estaba (texto, cursor, tabs, foco, layout y cwd viven en
C). Si el script tiene error, se conserva el último frame bueno y el error se
reporta en el log; el reintento es un loop acotado a dos intentos.

Sobreviven al reload las definiciones hechas **en la consola** (por el script
de sesión). No sobreviven las definiciones puestas directamente en `ui.fxl`
(`\mi_fn=...`), porque el intérprete se reinicia.

---

## 4. API regex desde Fexl

Definida en `fexlswi-llvm/src/type_regex.c` (`regex.compile`… `abregex.compile`):

| Función | Resultado |
|---|---|
| `(regex.compile pattern)` | `regex` \| `void` |
| `(regex.match prog text)` | bool |
| `(regex.search prog text from forward)` | offset o `-1` |
| `(regex.count prog text)` | número |
| `(regex.spans prog text max)` | string `"start,end;start,end;…"` |
| `(abregex.session)` | sesión nueva |
| `(abregex.define session defs)` | `1` ok / `0` error de sintaxis |
| `(abregex.compile session name)` | `regex` \| `void` |

Ejemplos:

```fexl
\pat=(regex.compile "[0-9]+")
say (regex.count pat "a1 b22 c333")       ; 3
say (regex.spans pat "a1 b22" 512)        ; "1,2;4,6"

\ses=(abregex.session)
say (abregex.define ses "@key::if|then|else;")
\kw=(abregex.compile ses "key")
```

`abregex.define` recibe un **string** con definiciones `@nombre::patron;`
(no una lista), y `abregex.compile` busca ese nombre en la sesión. El formato
está probado en `fexlswi-llvm/test/regex.fxl`.

`regex.spans` es la base del resaltado: `ui.fxl` emite `SPANS <style_id>
<start,end;...>` y `main.c` los aplica con `fmt_add_span()`. Ver `addformat.md`.

### Booleanos y switches

Además de regex, el intérprete expone estado de scripting:

```fexl
true                       ; booleano
false
(set_switch "demo" 1)      ; prende el switch "demo"
(get_switch "demo")        ; 1 / 0
(switch "demo" 0)          ; apaga el switch y devuelve su valor
```

Los switches se persisten en `/tmp/swi_switches.txt` (`nombre=0|1` por
línea, implementado en `fexlswi-llvm/src/type_script.c`), no en la sesión: por eso
sobreviven al hot reload y a procesos. Son útiles para opciones de UI que se
prenden/apagan desde la consola. Ejecutable en `fexlswi-llvm/test/regex.fxl`.

`load_script()` también expone `true`/`false` como alias de los booleanos de
Fexl. Los *init tools* son simplemente el archivo que se pasa al intérprete al
arrancar (`argv`), sin código adicional.

---

## 5. Regex: dos usos, un solo directorio

Esta es la distinción que más confunde:

| Uso | Dónde corre | Para qué | Cómo se compila |
|---|---|---|---|
| **Regex en Fexl** | proceso `fexlswi0` | scripting: `ui.fxl`, consola, patrones de color | `fexlswi-llvm/src/build_regex` → `lib/fexlswi.bc` |
| **Regex en IR** | dentro de `swi` | `format.ll` (resaltado), `replace.ll` (`:s`), `document.ll` | `swi/Makefile` → `build/<perfil>/fused.bc` |

Ambos consumen **los mismos 11 módulos fuente** en `regex/`:

```
regex/
├── rx_types.ll        tipos compartidos (inyectado en el build)
├── regex_parser.ll    regex_compiler.ll   regex_abregex.ll
├── regex_thread.ll    regex_runner.ll     rx_query.ll
├── rx_runtime.ll      format.ll           replace.ll
├── macros.ll          rxprog_cache.ll     (orquestación / cache .rxc)
└── build/             .bc generados (ignorado por git)
```

Los siete módulos del motor más los cuatro de swi conviven en un único
directorio desde que `fexlswi` dejó de ser un repo anidado. Antes había siete
copias de `%RxInst`/`%RxProgram` con el comentario «DEBEN COINCIDIR»; ahora
están en `rx_types.ll` y se inyectan por concatenación:

```make
cat regex/rx_types.ll regex/format.ll | opt-21 ... -o build/opt/format.bc
```

LLVM IR no tiene `include`, por eso se concatena en vez de importar. Lo hace
tanto `fexlswi-llvm/Makefile` como `swi/Makefile` (reglas `REGLAS_REGEX` y
`REGEX_LL`).

`swi` linkea `fexlswi_lib.bc` dentro de su binario en los perfiles LTO (es el
mismo intérprete del hijo, compilado sin internalizar y con `main -> fexl_main`);
por eso solo compila aparte los módulos IR que necesita para resaltar y
reemplazar (`format`, `replace`). En `fast` no hay fusión: el intérprete corre
en un ELF separado.

---

## 6. Cambiar la UI desde Fexl (sin recompilar)

### Layout

Editar `swi/ui.fxl`:

```fexl
\ch2=10                      ; consola siempre extendida
\fw2=((eq ce 51) 60 0)       ; F3 -> 60 columnas
```

`num` (en `ui.fxl`) solo mapea `0,1,2,3,10,40` porque este build no tiene
`as_str`. Para otro valor (p. ej. 60), agregalo a la tabla `num`.

### Texto de estado

`STATUS` acepta una palabra (sin espacios: el C lo lee con `%63s`):

```fexl
\st2="LISTO"
```

### Atajos

Agregar un `BIND` en `emit`:

```fexl
say "BIND C-X mi.accion"
```

Importante: hoy los BIND son **informativos** para acciones nuevas. Para que
`C-X` ejecute algo hay que cablear C/IR; ver §6 de `extend.md`.

### Cambiar el script sin recompilar

La ruta va embebida con `UI_SCRIPT_DEF`. Recompilás si querés apuntar a otro
archivo fijo. Para no recompilar, `main.c` podría usar `getenv("SWI_UI")` con
default a `SWI_UI_SCRIPT` (no implementado todavía).

---

## 7. Trampas

- `as_str` no existe en este build: usá `num` o literales de dos dígitos.
- `fflush stdout` es obligatorio al final de cada frame; sin él el motor espera
  para siempre.
- El protocolo son bytes: un código nuevo no puede ser `10` (LF), porque se
  confunde con el fin de línea del frame.
- El texto para `FUI_FMT` viaja por `/tmp/swi_fmt_input.txt`, no por los 4 bytes.
- El driver se reinicia automáticamente si el hijo murió e ignora `SIGPIPE`,
  así que un script roto no tumba el editor.
- `ui.fxl` no es dependencia de `main.o`: solo se embebe su ruta. Editarlo no
  recompila; se aplica con el hot reload de §3.
- Si `main.o` se compiló con una ruta relativa de fallback, el driver muere con
  `exit 127` al arrancar desde fuera de `swi/`. Forzá el rebuild si tocás el
  Makefile.

Ver también: `extend.md` (extender la UI) y `addformat.md` (formateadores).
