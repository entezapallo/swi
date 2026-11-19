# fexlswi

Fexl + extensión regex + motor jotter. Repo anidado dentro de `~/swi`.

## Binarios finales

Solo dos, en cada perfil:

```
build/opt/bin/fexlswi     build/opt/bin/fexlswi0
build/selfh/bin/fexlswi   build/selfh/bin/fexlswi0
```

- `fexlswi`: carga `main.fxl` al arrancar.
- `fexlswi0`: el mismo ELF con otro nombre; el sufijo `0` evita cargar
  `main.fxl`. Es el que `swi` invoca en runtime (`fork/exec`).

Ambos son **estáticos**: `swi` usa el binario dinámicamente como proceso, no
como librería compartida. `bin/` queda con el último perfil compilado.

## Compilación

```bash
make opt       # estático, -Oz + LTO con globaldce
make selfh     # estático, -Oz + LTO sin pases extra
make clean
make all
```

Todo se compila con `-Oz`, se fusiona en `lib/fexlswi.bc` y se linkea con
`-static`, `--gc-sections` y strip.

## Estructura

```
src/        código C de Fexl + lib_build + build + build_regex
regex/      7 .ll de regex (copias reales)
regex/build .bc generados con -mtriple=x86_64-linux-musl
lib/, obj/  generados
build/      binarios de ambos perfiles
test/       suite Fexl
```

## Verificar

```bash
file build/opt/bin/fexlswi0       # statically linked
ldd build/opt/bin/fexlswi0        # no es un ejecutable dinámico
printf 'load_basic\nload_output\nevaluate \\;\nsay "OK"\n' > /tmp/t.fxl
build/opt/bin/fexlswi0 /tmp/t.fxl
```
