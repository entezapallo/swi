# fexlswi

Fexl + extensión regex + motor jotter. Parte del repo `~/swi` (código normal,
sin submodule). Los módulos regex están en `../regex/`, compartidos con `swi`.
Ver `../scripting.md`.

## Binarios finales

Dos ELF standalone por perfil, más un bitcode para `swi`:

```
build/opt/bin/fexlswi     build/opt/bin/fexlswi0
build/selfh/bin/fexlswi   build/selfh/bin/fexlswi0
build/opt/lib/fexlswi.bc  build/opt/lib/fexlswi_lib.bc
```

- `fexlswi`: carga `main.fxl` al arrancar.
- `fexlswi0`: el mismo ELF con otro nombre; el sufijo `0` evita cargar
  `main.fxl`. Lo usa `swi` en `fast` y en pruebas.
- `fexlswi_lib.bc`: el intérprete sin `internalize`/`globaldce` y con
  `main -> fexl_main`; `swi` lo linkea en los perfiles LTO para formar un
  solo ELF donde `fexlswi0` es un symlink a `swi`.

Todo es **musl dinámico**. `bin/` queda con el último perfil compilado.

## Compilación

```bash
make fast       # musl dinámico, -O0 -g (iterar)
make opt        # musl dinámico, -Oz + LTO con globaldce
make opt-full   # musl dinámico, -Oz + LTO + internalize
make selfh      # musl dinámico, -Oz + LTO sin pases extra
make clean
make all        # opt + selfh
```

El build es **100% Make**: no quedan scripts shell (`build`, `build_lib`,
`build_regex`, `lib_build`, `build.sh` se eliminaron). El `Makefile` de `~/swi`
solo delega con `make -C fexlswi <perfil>`; no duplica reglas ni flags.

Pipeline:

1. 49 módulos C del intérprete → `obj/*.bc` (`clang --target=x86_64-linux-musl`).
2. `fexl.c` se recompila con `-DJOTTER_REGEX` → `obj/fexl_regex.bc`; además
   `type_regex.c` y `type_script.c`.
3. Los 7 módulos IR de `../regex/` se compilan a `../regex/build/*.bc` con
   `-mtriple=x86_64-linux-musl` y los tipos compartidos de `rx_types.ll`
   inyectados por concatenación (IR no tiene `include`).
4. `llvm-link-21` fusiona todo en `lib/fexlswi.bc` y, sin pases FUSE y con
   `main -> fexl_main`, en `lib/fexlswi_lib.bc` (para el ELF fusionado de `swi`).
5. Si el perfil lo pide, `opt-21 -passes=...` optimiza el bitcode.
6. `clang-21` linkea contra musl → `bin/fexlswi` y copia a `bin/fexlswi0`.

## Estructura

```
src/        código C de Fexl + type_regex.c + type_script.c
../regex/   11 módulos regex compartidos con swi (incluye rx_types.ll)
../regex/build .bc generados con -mtriple=x86_64-linux-musl
obj/        .bc generados por módulo
lib/        fexlswi.bc (standalone) y fexlswi_lib.bc (para swi) fusionados
bin/        fexlswi / fexlswi0
build/      copias por perfil
test/       suite Fexl
```

## Verificar

```bash
file build/opt/bin/fexlswi0    # dynamically linked, intérprete /lib/ld-musl-x86_64.so.1
printf 'load_basic\nload_output\nevaluate \\;\nsay "OK"\n' > /tmp/t.fxl
build/opt/bin/fexlswi0 /tmp/t.fxl
```

Para verificar el pipeline completo desde la raíz de `~/swi`: `make opt` y
`./build/swi --selftest`.
