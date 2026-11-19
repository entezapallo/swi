# fexlswi

Fexl + extensión regex + motor jotter. Parte del repo `~/swi` (código normal,
sin submodule). Los módulos regex están en `../regex/`, compartidos con
`swi`. Ver `../scripting.md`.

## Binarios finales

Solo dos, en cada perfil:

```
build/opt/bin/fexlswi     build/opt/bin/fexlswi0
build/selfh/bin/fexlswi   build/selfh/bin/fexlswi0
```

- `fexlswi`: carga `main.fxl` al arrancar.
- `fexlswi0`: el mismo ELF con otro nombre; el sufijo `0` evita cargar
  `main.fxl`. Es el que `swi` invoca en runtime (`fork/exec`).

Ambos son **musl dinámicos**, como `swi`; `swi` los usa como proceso aparte
(`fork/exec`), no como librería compartida. `bin/` queda con el último perfil
compilado.

## Compilación

```bash
make opt       # dinámico musl, -Oz + LTO con globaldce
make selfh     # dinámico musl, -Oz + LTO sin pases extra
make clean
make all
```

Los 7 módulos del motor se compilan desde `../regex/*.ll` a
`../regex/build/*.bc`, con los tipos compartidos de `../regex/rx_types.ll`
inyectados por concatenación. Todo se fusiona en `lib/fexlswi.bc` y se linkea
con `--gc-sections`, `--icf=all` y strip. `swi/Makefile` hace lo mismo para sus
cuatro perfiles.

## Estructura

```
src/        código C de Fexl + lib_build + build + build_regex
../regex/   11 módulos regex compartidos con swi (incluye rx_types.ll)
../regex/build .bc generados con -mtriple=x86_64-linux-musl
lib/, obj/  generados
build/      binarios de ambos perfiles
test/       suite Fexl
```

## Verificar

```bash
file build/opt/bin/fexlswi0       # dynamically linked, intérprete /lib/ld-musl-x86_64.so.1
printf 'load_basic\nload_output\nevaluate \\;\nsay "OK"\n' > /tmp/t.fxl
build/opt/bin/fexlswi0 /tmp/t.fxl
```

Para verificar el pipeline completo desde la raíz de `~/swi`: `make opt` y
`./build/swi --selftest`.
