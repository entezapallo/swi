# swi <img src=".media/logo.png" align="right" height="250" />

Editor TUI modal sobre el motor jotter, con un driver Fexl persistente que
decide el layout y los atajos.

```
swi/
├── tui/          código C/H/IR del editor (termbox2, state, win_editor, …)
├── test/         arneses por módulo
├── abi/          tui_abi.h (frontera C ↔ IR)
├── core/ regex/ fsio/   módulos IR del motor
├── fexlswi/      repo anidado: intérprete Fexl + regex + motor
├── ui.fxl        driver Fexl (layout, bindings, STATUS/LOG)
├── build*/       binarios generados
└── docs: BUILD.md · about.md · cheatsheet.md · extend.md · spec.md
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
