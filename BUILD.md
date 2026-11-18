# swi

TUI modal sobre el motor jotter. Proyecto autocontenido con `fexlswi/`
como repo anidado.

## Compilación

```bash
make opt       # dinámico musl, -Oz + LTO + globaldce
make selfh     # dinámico musl, -Oz + LTO, desde fuentes sin pases extra
make fast      # iteración rápida (-O0, sin LTO), también musl
make clean
make install   # solo empaqueta make opt: build/swi + build/fexlswi/
make test      # suite completa (perfil fast)
make test-opt
make test-selfh
```

Los binarios finales quedan en `build/opt/` y `build/selfh/`. `build/swi`
queda con el último perfil compilado. Hay un solo binario por perfil (`swi`),
que arranca con el driver Fexl `ui.fxl`.

## Estructura (sin `vendor/`)

```
tui/      C/H/LL del editor + termbox2.h
test/     arneses por módulo
abi/      tui_abi.h
core/     módulos IR del motor
regex/    módulos IR de regex
fsio/     módulos IR de fsio (incluye fsio_getdents.ll para musl)
ui.fxl    driver Fexl persistente (layout y atajos)
```

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
Ver `extend.md`.
