# Cheatsheet de `swi`

## Modos

| Tecla | Acción |
|---|---|
| `i` | NORMAL → INSERT |
| `a` | INSERT al final del carácter |
| `v` | VISUAL (selección) |
| `:` | COMMAND (prefijo `:`) |
| `/` | COMMAND (prefijo `/`, buscar) |
| `Esc` | volver a NORMAL |

En INSERT, `h/j/k/l` son **texto**; las flechas son movimientos.

## Movimientos (NORMAL / VISUAL)

`h j k l`, `w b e`, `0 ^ $`, `gg G`, `Ctrl+U`/`Ctrl+D`, `f<char>`,
`n` / `N` (repetir búsqueda).

## Edición

| Tecla | Acción |
|---|---|
| `x` | borrar carácter |
| `dd` / `yy` / `cc` | borrar / copiar / cambiar línea |
| `p` | pegar |
| `u` / `Ctrl+R` | undo / redo |
| `d`/`y`/`c` + movimiento | operador sobre movimiento |
| `:w` | guardar |
| `:w <ruta>` | guardar como |
| `:e` / `:e <ruta>` | recargar / abrir |
| `:q` / `:q!` / `:wq` | salir / salir sin guardar / guardar y salir |

## Paneles

| Tecla | Acción |
|---|---|
| `Ctrl+E` | consola Fexl (brief ⇄ extendida) |
| `Ctrl+F` | file manager |
| `Ctrl+B` | colapsar/expandir tabs |
| `Ctrl+T` | tab nueva |
| `Ctrl+W` | cerrar tab |
| `Ctrl+N` | tab siguiente |
| `Ctrl+Q` / `F10` | salir (desde cualquier foco) |

En el file manager: `j/k` o flechas, `Enter` abre, `h`/`Backspace` sube,
`t` abre en tab nueva, `..` es la primera entrada.

`F2`/`F3`/`F4` son equivalentes a `Ctrl+E/F/B`, pero puede capturarlos el
gestor de escritorio (F3 abre el launcher en XFCE).

## Consola Fexl

```
Ctrl+E
> say "hola"
> \x=41
> say x
> regex.count "a" "banana"
Esc
```

Cada línea se agrega al script de sesión y se re-evalúa completo, así que las
definiciones (`\x=...`) persisten entre comandos. `Enter` evalúa, `Backspace`
borra, `Esc` devuelve el foco al buffer.

## Build

```bash
make clean all               # limpia, no compila
make fast                    # build/swi (debug)
make opt                     # build/opt/swi
make opt-full                # build/opt-full/swi (mínimo)
make selfh                   # build/selfh/swi
make install                 # build/swi + build/fexlswi/
make test test-opt test-selfh
make MODE=opt-full test
make FEXL=/otro/fexlswi0 opt # override del intérprete
```

`make opt` (y los otros perfiles) compila `fexlswi` primero: no hace falta un
paso previo. Ver `BUILD.md`, `scripting.md` y `extend.md`.

## Problemas comunes

- **"Las flechas no responden"**: el foco quedó en consola o file manager.
  `Esc` vuelve al buffer; al reiniciar, el foco siempre vuelve al buffer.
- **F2/F3/F4 no hacen nada**: los capturó el escritorio. Usá `Ctrl+E/F/B`.
- **No se ve el archivo**: el buffer se abre vacío si se creó con `Ctrl+T`;
  abrilo con `./swi archivo` o `:e <ruta>`.
- **Sin salida Fexl**: el driver no arrancó; revisá
  `fexlswi/bin/fexlswi0` y el log de la consola.
- **Se perdió el resaltado**: escaped y volvé a buscar; los spans se
  recalculan al editar con el último patrón.
