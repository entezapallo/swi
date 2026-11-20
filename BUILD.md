# swi

TUI modal sobre el motor jotter. Proyecto **autocontenido en un solo repo**:
`fexlswi/` es código normal (intérprete Fexl y binarios), y los módulos regex
están unificados en `regex/`. No hay submodules.

## Compilación

```bash
make opt              # UN binario: -Oz + LTO + globaldce, musl dinámico
make opt-full         # opt + segunda ronda de Oz + flags de link agresivos
make selfh            # como opt pero sin globaldce en el fusionado
make fast             # dos ELF: swi -O0 -g + fexlswi0 (proceso hijo)
make clean all        # limpia ambos proyectos, no compila
make install          # solo empaqueta opt/opt-full: build/swi + build/fexlswi/
make test             # suite completa (perfil fast)
make test-opt
make MODE=opt-full test
make test-selfh
```

Cada target compila primero `fexlswi` y después `swi`. En los perfiles LTO
(`opt`, `opt-full`, `selfh`) `fexlswi` entrega `lib/fexlswi_lib.bc` y `swi`
lo linkea consigo: hay **un solo ELF** por perfil en `build/<perfil>/swi`, y
`build/swi` es el último perfil compilado. Un `dispatch.c` generado por el
Makefile decide por `basename(argv[0])` si entra a `fexl_main` o `swi_main`;
`fexlswi0` es un symlink a `swi`, así que el driver Fexl sigue corriendo como
proceso hijo con el mismo ELF. En `fast` hay dos binarios separados como antes.

`make install` deja `build/swi`, el symlink `build/fexlswi/bin/fexlswi0` y
`build/fexlswi/src/lib` con las librerías Fexl. `ui.fxl` queda en
`build/fexlswi/ui.fxl`.

## Estructura (sin `vendor/`)

```
tui/      C/H/LL del editor + termbox2.h
test/     arneses por módulo
abi/      tui_abi.h y fexl_abi.h (fronteras C ↔ IR)
core/     módulos IR del motor (document, chunk, lineindex, …)
regex/    11 módulos IR de regex + rx_types.ll (tipos compartidos)
fsio/     módulos IR de fsio (incluye fsio_getdents.ll para musl)
fexl/     núcleo Fexl en IR: value_types, memory, value, str, parse,
          type_num, type_cmp, basic, type_str, type_sym, type_output,
          type_record, buf, buf_str, file, file_str, convert, type_rand,
          type_limit, type_math, type_hex, type_tuple, type_var, type_istr,
          type_input, type_buf, type_parse, type_argv, type_stream, type_file,
          die, format, report, limit, type_fexl, type_signal, type_crypto,
          test, stream, base64, type_time, show, type_bn, fexl, aot,
          sha256, sha512, crypto
fexlswi/  intérprete Fexl (C restante) + binarios fexlswi / fexlswi0
ui.fxl    driver Fexl persistente (layout y atajos)
```

Frontera de la migración a IR: todo el **intérprete** (reducer, parser,
builtins y driver) vive en `fexl/*.ll`. Quedan en C solo los módulos de
algoritmos puros y sistemas que el intérprete llama como biblioteca de
soporte: `bn` (enteros arbitrarios), `nacl` (criptografía) y `type_run`
(procesos, sockets, termios). No tienen semántica de valores Fexl y su
porte a IR escrito a mano no fue confiable (se intentó `bn` y se revirtió).

Los 11 módulos de `regex/` son compartidos: `fexlswi` compila los 7 módulos del
motor en `lib/fexlswi.bc` y en `lib/fexlswi_lib.bc` (el que consume `swi`), y
`swi` compila aparte solo `replace` y `format` para su `fused.bc` — el resto
viene dentro de `fexlswi_lib.bc`, así no hay símbolos duplicados. `rx_types.ll`
se concatena al comienzo de cada módulo en el build porque LLVM IR no tiene
`include`.

Todo se compila con target `x86_64-linux-musl` y se linkea dinámicamente con
rpath a `/usr/lib/x86_64-linux-musl`.

## Dependencias

- Toolchain LLVM: `clang-21`, `opt-21`, `llc-21`, `llvm-link-21`, `lld-21`.
- Fexl: en `fast`, `fexlswi/bin/fexlswi0` (ELF aparte); en los perfiles LTO,
  `build/fexlswi/bin/fexlswi0` (symlink al mismo `swi`). Override:
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
