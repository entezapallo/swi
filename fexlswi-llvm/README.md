# fexlswi-llvm

Intérprete del lenguaje Fexl compilado a **LLVM IR**. Antes vivía en `fexl/`
(núcleo en IR) y en `fexlswi/src/` (C residual); ahora los dos están juntos y el
lenguaje se compila aparte del editor `swi`.

## Contenido

- `./*.ll` — núcleo del intérprete en IR: reducer, parser, builtins, driver y AOT.
  `value_types.ll` se inyecta por concatenación al compilar cada módulo.
- `src/` — el C que todavía no se portó a IR: `bn`, `nacl`, `type_run`,
  `type_regex`, `type_script`, más los headers que incluyen. Son algoritmos
  puros y de sistemas, sin semántica de valores Fexl.
- `../regex/` — motor regex en IR (se compila desde acá).

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
  propio y los pases `FUSE` del perfil.

## Relación con `swi`

El Makefile raíz llama a `../fexlswi/Makefile`, que delega acá, y linkea
`lib/fexlswi_lib.bc` junto con el editor en un solo ELF. Por `basename(argv[0])`
ese ELF entra a `fexl_main` (cuando se llama `fexl*`) o a `swi_main`.

`--icf=safe` es obligatorio: Fexl usa `value.T` (puntero a función) como tag de
tipo y `--icf=all` pliega funciones con dirección tomada, rompiendo el driver.
