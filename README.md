# swi <img src=".media/logo.png" align="right" height="250" />

Editor TUI vi-like, **lazy** y **scriptable** sobre el motor jotter. Binarios
**musl dinámicos**, motor escrito en módulos **LLVM IR** y un driver Fexl
persistente que decide el layout, los atajos y los formateadores.

Pensado para leer y editar archivos grandes de texto: importa no repintar todo
el buffer y poder scriptar el análisis desde Fexl.
Logo robado del split lp de Druadan Forest/Old Sorcery (escuchen dungeon synth)
```
swi/
├── tui/          código C/H/IR del editor (termbox2, state, win_editor, …)
├── test/         arneses por módulo
├── abi/          tui_abi.h (frontera C ↔ IR)
├── core/ regex/ fsio/   módulos IR del motor
├── fexlswi/      repo anidado: intérprete Fexl + regex + motor
├── ui.fxl        driver Fexl (layout, bindings, STATUS/LOG)
├── build*/       binarios generados
└── docs: BUILD.md · about.md · cheatsheet.md · extend.md · addformat.md · spec.md
```

## Arrancar

```bash
make opt          # fexlswi opt + swi opt
make opt-full     # fexlswi opt-full + swi opt-full, de una pura volada
make selfh        # fexlswi selfh + swi selfh
make fast         # fexlswi fast + swi fast (iterar/debug)
make clean all    # limpia fexlswi y swi, sin compilar
make install      # empaqueta build/ con un binario y una carpeta
./build/swi archivo.txt
```

`make install` funciona después de `opt` u `opt-full`. `build/` queda con
un solo binario (`swi`) y una sola carpeta (`fexlswi/`).

Primero hace falta el intérprete anidado:

```bash
make -C fexlswi clean all
```

## Diseño

- **Vi-like**: NORMAL / INSERT / VISUAL / COMMAND, `h/j/k/l`, `dd/yy/p/u`,
  búsqueda `/pat` y `n/N`, selección visual.
- **Lazy**: el viewport calcula y pinta solo las filas visibles, con wrap al
  120% y truncate. Hoy el lazy es de **render**: `doc_load` todavía carga el
  archivo completo en el `TextBuffer`; el I/O lazy queda para la Etapa D de
  `document.ll`.
- **LLVM + musl**: motor en módulos `.ll`, perfiles `fast`, `opt`, `opt-full` y
  `selfh`, link dinámico contra musl (`-L/usr/lib/x86_64-linux-musl`,
  `--dynamic-linker`, `-rpath`). Ver `BUILD.md`.
- **Scriptable**: `ui.fxl` controla `CONSOLE_H`, `TABS_COL`, `FILEMAN_W`,
  `STATUS`, `LOG`, `BIND` y los spans `SPANS`; las definiciones de la consola
  persisten en un script de sesión por PID.
- **Colores**: el driver calcula spans con `regex.spans` y el editor mapea
  `style_id` a la paleta: 1 búsqueda/amarillo, 2 keyword/cian, 3 string/verde,
  4 comment/gris, 5 number/magenta. Ver `addformat.md`.
- **Bioinformática**: el editor maneja texto plano; los visores de formatos
  de registros están fuera del alcance actual.

## Qué hay dentro

- **NORMAL / INSERT / VISUAL / COMMAND**, `h/j/k/l`, mots de palabra,
  `dd/yy/p/u`, búsqueda `/pat` y `n/N`, selección visual.
- **Consola** `Ctrl+E`: evalúa Fexl y guarda las definiciones de la sesión.
- **File manager** `Ctrl+F`: `j/k`, `Enter`, `h`/`Backspace`, `t` para abrir
  en tab nueva; la entrada `..` sube de directorio.
- **Tabs** `Ctrl+T` nueva, `Ctrl+W` cerrar, `Ctrl+N` siguiente, `Ctrl+B`
  colapsar.
- **Barra de estado** con modo, posición, dirty flag y estado de Fexl.
- Sesión persistente (tabs, cursor, foco, layout, directorio).

## Documentos

| Archivo | Contenido |
|---|---|
| `BUILD.md` | compilación, toolchain, perfiles y rutas |
| `about.md` | arquitectura y decisiones de diseño |
| `cheatsheet.md` | teclas, comandos y resolución de problemas |
| `extend.md` | cómo scriptar y cómo extender la UI |
| `addformat.md` | cómo agregar formateadores de sintaxis desde Fexl |
| `spec.md` | especificación original del proyecto |

## Tests

```bash
make test         # 162 checks, perfil fast
make test-opt
make test-selfh
```
