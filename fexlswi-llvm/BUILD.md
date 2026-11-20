# fexlswi-llvm — build

El lenguaje Fexl es un proyecto aparte dentro de `~/swi`. El intérprete está en
IR (`*.ll`) salvo 5 módulos C de soporte. Los módulos regex viven en `../regex/`
y se comparten con `swi`. Ver `../scripting.md` y el `README.md` de acá.

## Productos por perfil

Dos ELF standalone, más un bitcode que consume `swi`:

```
bin/fexlswi      bin/fexlswi0
lib/fexlswi.bc   lib/fexlswi_lib.bc
```

- `fexlswi`: carga `main.fxl` al arrancar (del runtime en `src/lib/`).
- `fexlswi0`: el mismo ELF con otro nombre; el sufijo `0` evita cargar
  `main.fxl`. Lo usa `swi` en `fast` y en pruebas.
- `fexlswi_lib.bc`: sin `internalize`/`globaldce` y con `main -> fexl_main`;
  `swi` lo linkea en los perfiles LTO para formar un solo ELF.
- `fexlswi.bc`: fusionado del standalone, con los pases `FUSE` del perfil.

Todo es **musl dinámico**. `bin/` y `lib/` quedan con el último perfil compilado.

## Perfiles

```bash
make fast       # -O0 -g, sin strip
make opt        # -Oz + LTO + internalize/globaldce
make opt-full   # opt + adce + flags de link agresivos (default)
make selfh      # -Oz + LTO sin pases extra
make clean
```

`--icf=safe` es obligatorio: Fexl usa `value.T` (puntero a función) como tag de
tipo y `--icf=all` pliega funciones con dirección tomada, rompiendo el driver.

## Pipeline

1. 5 módulos C (`bn`, `nacl`, `type_run`, `type_regex`, `type_script`) →
   `obj/*.bc` con `clang --target=x86_64-linux-musl -emit-llvm`.
2. Los ~47 módulos IR de `./*.ll` → `obj/fexl_*.bc`, con `value_types.ll`
   inyectado por concatenación (IR no tiene `include`).
3. Los 7 módulos IR de `../regex/` → `../regex/build/*.bc`, con `rx_types.ll`
   inyectado de la misma forma.
4. `llvm-link-21` fusiona todo en `lib/fexlswi.bc` y, sin pases FUSE y con
   `main -> fexl_main`, en `lib/fexlswi_lib.bc` (para `swi`).
5. Si el perfil lo pide, `opt-21 -passes=...` optimiza el fusionado.
6. `clang-21` linkea contra musl → `bin/fexlswi` y copia a `bin/fexlswi0`.

## Estructura

```
*.ll          núcleo IR del intérprete + standalone_main.ll
src/*.c|h     C residual (bn, nacl, type_run, type_regex, type_script)
src/lib/      runtime Fexl (.fxl)
test/         smoke test regex.fxl
obj/          .bc generados por módulo
lib/          bitcodes fusionados
bin/          fexlswi / fexlswi0
build/        copias por perfil
../regex/     motor regex IR compartido con swi
```

## Verificar

```bash
bin/fexlswi0 test/regex.fxl
printf 'load_basic\nload_output\nevaluate \\;\nsay "OK"\n' > /tmp/t.fxl
bin/fexlswi0 /tmp/t.fxl
```

La verificación completa está en la raíz de `~/swi`: `make test` (fast) y
`make test-opt-full` (206 checks), además de `make install`.
