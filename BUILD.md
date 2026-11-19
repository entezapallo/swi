# swi

TUI modal sobre el motor jotter. Proyecto **autocontenido en un solo repo**:
`fexlswi/` es código normal (intérprete Fexl y binarios), y los módulos regex
están unificados en `regex/`. No hay submodules.

## Compilación

```bash
make opt              # dinámico musl, -Oz + LTO + globaldce
make opt-full         # -Oz + LTO + internalize (binario mínimo)
make selfh            # dinámico musl, -Oz + LTO, sin pases extra
make fast             # iteración rápida (-O0, sin LTO), también musl
make clean all        # limpia ambos proyectos, no compila
make install          # solo empaqueta opt/opt-full: build/swi + build/fexlswi/
make test             # suite completa (perfil fast)
make test-opt
make MODE=opt-full test
make test-selfh
```

Cada target compila primero `fexlswi` y después `swi`. Los binarios quedan en
`build/<perfil>/swi`; `build/swi` es el último perfil compilado. Hay un solo
binario por perfil (`swi`), que arranca con el driver Fexl `ui.fxl`.
`make install` deja exactamente `build/swi` y `build/fexlswi/`.

## Estructura (sin `vendor/`)

```
tui/      C/H/LL del editor + termbox2.h
test/     arneses por módulo
abi/      tui_abi.h
core/     módulos IR del motor (document, chunk, lineindex, …)
regex/    11 módulos IR de regex + rx_types.ll (tipos compartidos)
fsio/     módulos IR de fsio (incluye fsio_getdents.ll para musl)
fexlswi/  intérprete Fexl + binarios fexlswi / fexlswi0
ui.fxl    driver Fexl persistente (layout y atajos)
```

Los 11 módulos de `regex/` son compartidos: `swi` los compila en su `fused.bc`
y `fexlswi` los compila en `lib/fexlswi.bc`. `rx_types.ll` se concatena al
comienzo de cada módulo en el build porque LLVM IR no tiene `include`.

Todo se compila con target `x86_64-linux-musl` y se linkea dinámicamente con
rpath a `/usr/lib/x86_64-linux-musl`.

## Dependencias

- Toolchain LLVM: `clang-21`, `opt-21`, `llc-21`, `llvm-link-21`, `lld-21`.
- Fexl: `fexlswi/bin/fexlswi0` por defecto. Override:
  ```bash
  make FEXL=/otro/fexlswi0 swi-fast
  ```

## Uso

```bash
./build/swi archivo.txt
```

`i` insertar, `Esc` normal, `:w` guardar, `:q` salir, `Ctrl+E` consola,
`Ctrl+F` archivos, `Ctrl+B` tabs, `Ctrl+T` tab nueva, `Ctrl+W` cerrar tab.
Ver `cheatsheet.md`, `extend.md` y `scripting.md`.
