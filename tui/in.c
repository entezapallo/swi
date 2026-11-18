/*
 * in.c - lee de termbox2 y entrega un InEvent al IR.
 * Sin estado, sin logica de decision: solo traduce tipos.
 * TB_IMPL lo define otro archivo (main.c); aca solo se incluye el header.
 */

#include <errno.h>
#include "in.h"
#include "termbox2.h"

static int32_t map_mods(uint8_t m)
{
    int32_t r = 0;
    if (m & TB_MOD_ALT)   r |= IN_MOD_ALT;
    if (m & TB_MOD_CTRL)  r |= IN_MOD_CTRL;
    if (m & TB_MOD_SHIFT) r |= IN_MOD_SHIFT;
    return r;
}

/* Teclas especiales. Los ctrl+letra (0x01..0x1a) NO pasan por aca:
 * TAB, ENTER, ESC y BACKSPACE comparten codigo con ctrl+i, ctrl+m,
 * ctrl+[ y ctrl+h, asi que se resuelven aca primero. */
static int32_t map_key(uint16_t k)
{
    switch (k) {
    case TB_KEY_ENTER:       return IN_KEY_ENTER;
    case TB_KEY_TAB:         return IN_KEY_TAB;
    case TB_KEY_BACKSPACE:   return IN_KEY_BACKSPACE;
    case TB_KEY_BACKSPACE2:  return IN_KEY_BACKSPACE;
    case TB_KEY_DELETE:      return IN_KEY_DELETE;
    case TB_KEY_INSERT:      return IN_KEY_INSERT;
    case TB_KEY_ESC:         return IN_KEY_ESC;

    case TB_KEY_ARROW_UP:    return IN_KEY_UP;
    case TB_KEY_ARROW_DOWN:  return IN_KEY_DOWN;
    case TB_KEY_ARROW_LEFT:  return IN_KEY_LEFT;
    case TB_KEY_ARROW_RIGHT: return IN_KEY_RIGHT;
    case TB_KEY_HOME:        return IN_KEY_HOME;
    case TB_KEY_END:         return IN_KEY_END;
    case TB_KEY_PGUP:        return IN_KEY_PGUP;
    case TB_KEY_PGDN:        return IN_KEY_PGDN;

    case TB_KEY_F1:          return IN_KEY_F1;
    case TB_KEY_F2:          return IN_KEY_F2;
    case TB_KEY_F3:          return IN_KEY_F3;
    case TB_KEY_F4:          return IN_KEY_F4;
    case TB_KEY_F5:          return IN_KEY_F5;
    case TB_KEY_F6:          return IN_KEY_F6;
    case TB_KEY_F7:          return IN_KEY_F7;
    case TB_KEY_F8:          return IN_KEY_F8;
    case TB_KEY_F9:          return IN_KEY_F9;
    case TB_KEY_F10:         return IN_KEY_F10;
    case TB_KEY_F11:         return IN_KEY_F11;
    case TB_KEY_F12:         return IN_KEY_F12;
    default:                 return IN_KEY_NONE;
    }
}

int in_poll(InEvent *out, int timeout_ms)
{
    struct tb_event ev;
    int rc;

    out->type = IN_EV_NONE;
    out->key  = IN_KEY_NONE;
    out->mods = 0;
    out->ch   = 0;
    out->w    = 0;
    out->h    = 0;

    rc = (timeout_ms < 0) ? tb_poll_event(&ev) : tb_peek_event(&ev, timeout_ms);

    if (rc == TB_ERR_NO_EVENT)
        return IN_TIMEOUT;
    if (rc == TB_ERR_POLL && tb_last_errno() == EINTR)
        return IN_TIMEOUT;
    if (rc != TB_OK)
        return IN_ERROR;

    if (ev.type == TB_EVENT_RESIZE) {
        out->type = IN_EV_RESIZE;
        out->w    = ev.w;
        out->h    = ev.h;
        return IN_EVENT;
    }

    if (ev.type != TB_EVENT_KEY)
        return IN_EVENT;                 /* mouse u otro: IN_EV_NONE */

    out->mods = map_mods(ev.mod);

    /* Caracter normal: termbox deja key == 0 y el codepoint en ch. */
    if (ev.key == 0) {
        if (ev.ch != 0) {
            out->type = IN_EV_CHAR;
            out->ch   = ev.ch;
        }
        return IN_EVENT;                 /* ch == 0 (ej. ctrl+espacio): NONE */
    }

    /* El espacio llega como tecla; para el IR es un caracter mas. */
    if (ev.key == TB_KEY_SPACE) {
        out->type = IN_EV_CHAR;
        out->ch   = ' ';
        return IN_EVENT;
    }

    {
        int32_t k = map_key(ev.key);
        if (k != IN_KEY_NONE) {
            out->type = IN_EV_KEY;
            out->key  = k;
            return IN_EVENT;
        }
    }

    /* ctrl+letra: 0x01..0x1a -> 'a'..'z' con mod CTRL */
    if (ev.key >= 0x01 && ev.key <= 0x1a) {
        out->type  = IN_EV_CHAR;
        out->ch    = (uint32_t)('a' + (ev.key - 1));
        out->mods |= IN_MOD_CTRL;
        return IN_EVENT;
    }

    /* ctrl+\ ctrl+] ctrl+^ ctrl+_ : 0x1c..0x1f */
    if (ev.key >= 0x1c && ev.key <= 0x1f) {
        static const char tbl[4] = { '\\', ']', '^', '_' };
        out->type  = IN_EV_CHAR;
        out->ch    = (uint32_t)tbl[ev.key - 0x1c];
        out->mods |= IN_MOD_CTRL;
        return IN_EVENT;
    }

    return IN_EVENT;                     /* tecla sin mapeo: IN_EV_NONE */
}
