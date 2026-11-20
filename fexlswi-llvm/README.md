# fexlswi-llvm

Intérprete del lenguaje [Fexl](http://fexl.com) compilado a **LLVM IR**. Antes
el núcleo vivía en `fexl/` y el C residual en `fexlswi/src/`; ahora todo el
lenguaje es **un solo proyecto** que se compila aparte del editor `swi`.

## Contenido

- `./*.ll` — núcleo del intérprete en IR: reducer, parser, builtins, driver y AOT.
  `value_types.ll` se inyecta por concatenación al compilar cada módulo.
- `src/` — el C que todavía no se portó a IR (`bn`, `nacl`, `type_run`,
  `type_regex`, `type_script` y sus headers). Son algoritmos puros y de sistemas,
  sin semántica de valores Fexl.
- `src/lib/*.fxl` — runtime Fexl (bibliotecas `load_basic`, `list`, `math`, …).
- `test/regex.fxl` — smoke test del tipo regex (batch, sin TUI).
- `../regex/` — motor regex en IR (se compila desde acá).
- `BUILD.md`, `LICENSE` — notas de build y licencia upstream.

## Compilación

```bash
make fast       # -O0 -g, sin strip
make opt        # -Oz + LTO + internalize/globaldce
make opt-full   # opt + adce + flags de link agresivos (por default)
make selfh      # sin internalize/globaldce
make clean
```

Cada perfil produce:

- `lib/fexlswi_lib.bc`: bitcode que **consume `swi`**. No está internalizado ni
  podado (el Makefile raíz lo hace al fusionar) y tiene `main` renombrado a
  `fexl_main`, porque `swi` aporta el `main` del dispatch.
- `lib/fexlswi.bc` y `bin/fexlswi`, `bin/fexlswi0`: standalone, con el `main`
  propio y los pases `FUSE` del perfil. El sufijo `0` evita cargar `main.fxl`.

Para correr el smoke test:

```bash
bin/fexlswi0 test/regex.fxl
```

## Relación con `swi`

El Makefile raíz llama directamente a este Makefile y linkea
`lib/fexlswi_lib.bc` junto con el editor en un solo ELF. Por `basename(argv[0])`
ese ELF entra a `fexl_main` (cuando se llama `fexl*`) o a `swi_main`.

En los perfiles de tamaño hay un solo binario; `fexlswi0` es un symlink a `swi`
dentro de `build/fexlswi/` (carpeta de instalación) y el runtime se resuelve en
`build/fexlswi/src/lib`. En `fast` hay dos ELF separados. La verificación real es
`make test` / `make test-opt-full` desde `~/swi` (206 checks).

`--icf=safe` es obligatorio: Fexl usa `value.T` (puntero a función) como tag de
tipo y `--icf=all` pliega funciones con dirección tomada, rompiendo el driver.

## Instalación

No hay instalación como tal: se compila y se corre desde el directorio. Si se
quiere un `fexl` en el PATH que resuelva los archivos bundléados, se puede crear
un wrapper que fije `argv[0]` a la ruta completa:

```
exec ~/project/fexlswi-llvm/bin/fexlswi0 "$@"
```

## Cómo funciona

El intérprete construye un valor que representa el programa completo y lo
reduce paso a paso hasta un valor final. Un *value* es un átomo (función
builtin o dato: número, string, archivo, …) o un par (aplicación de la función
de la izquierda sobre la derecha). El valor inicial está totalmente resuelto:
no hay búsqueda de símbolos durante la evaluación.

## Créditos y licencia

Basado en Fexl de Patrick Chkoreff (pc@fexl.com), 2023. Referencias:
Schönfinkel (1924), Church (1941), Steensgaard-Madsen (1989). Ver `LICENSE`.
