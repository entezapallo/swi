#ifndef TUI_IN_H
#define TUI_IN_H

#include <stdint.h>

/*
 * in.h - contrato de entrada entre in.c (C, termbox2) y el IR.
 *
 * Los valores numericos son fijos: el IR los espeja como constantes.
 * No reordenar ni reutilizar; solo agregar al final de cada grupo.
 */

enum InEvType {
    IN_EV_NONE   = 0,  /* nada que hacer (mouse, tecla sin representacion) */
    IN_EV_KEY    = 1,  /* tecla especial: ver enum InKey */
    IN_EV_CHAR   = 2,  /* caracter: codepoint en .ch (incluye ctrl+letra) */
    IN_EV_RESIZE = 3   /* cambio de tamano: .w y .h */
};

enum InMod {
    IN_MOD_ALT   = 1,
    IN_MOD_CTRL  = 2,
    IN_MOD_SHIFT = 4
};

enum InKey {
    IN_KEY_NONE      = 0,
    IN_KEY_ENTER     = 1,
    IN_KEY_TAB       = 2,
    IN_KEY_BACKSPACE = 3,
    IN_KEY_DELETE    = 4,
    IN_KEY_INSERT    = 5,
    IN_KEY_ESC       = 6,

    IN_KEY_UP        = 10,
    IN_KEY_DOWN      = 11,
    IN_KEY_LEFT      = 12,
    IN_KEY_RIGHT     = 13,
    IN_KEY_HOME      = 14,
    IN_KEY_END       = 15,
    IN_KEY_PGUP      = 16,
    IN_KEY_PGDN      = 17,

    IN_KEY_F1        = 20,
    IN_KEY_F2        = 21,
    IN_KEY_F3        = 22,
    IN_KEY_F4        = 23,
    IN_KEY_F5        = 24,
    IN_KEY_F6        = 25,
    IN_KEY_F7        = 26,
    IN_KEY_F8        = 27,
    IN_KEY_F9        = 28,
    IN_KEY_F10       = 29,
    IN_KEY_F11       = 30,
    IN_KEY_F12       = 31
};

/* Todos los campos son de 4 bytes: sin padding, 24 bytes en total.
 * Espejo en IR:  %InEvent = type { i32, i32, i32, i32, i32, i32 } */
typedef struct InEvent {
    int32_t  type;   /* enum InEvType */
    int32_t  key;    /* enum InKey, valido si type == IN_EV_KEY */
    int32_t  mods;   /* bits de enum InMod */
    uint32_t ch;     /* codepoint, valido si type == IN_EV_CHAR */
    int32_t  w;      /* valido si type == IN_EV_RESIZE */
    int32_t  h;
} InEvent;

_Static_assert(sizeof(InEvent) == 24, "InEvent debe medir 24 bytes (espejo en IR)");

/* Retorno de in_poll */
#define IN_EVENT    1   /* *out lleno (puede ser IN_EV_NONE: ignorar) */
#define IN_TIMEOUT  0   /* paso el timeout sin evento, o fue interrumpido */
#define IN_ERROR   (-1)

/*
 * Espera un evento.
 *   timeout_ms < 0  : bloquea hasta que haya evento
 *   timeout_ms >= 0 : espera como maximo ese tiempo
 * No guarda estado. tb_init/tb_shutdown son de main.c.
 */
int in_poll(InEvent *out, int timeout_ms);

#endif
