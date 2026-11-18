#ifndef TUI_OUT_H
#define TUI_OUT_H

#include <stdint.h>

/*
 * out.h — contrato de salida de la TUI.
 *
 * El IR entrega ESCALARES (x, y, codepoint, color, atributos); out.c los
 * traduce a termbox. Termbox no cruza esta frontera: el IR no conoce sus
 * constantes. La paleta es estable y tiene espejo en IR.
 *
 * El colorscheme se fija en compilación: out.c define valores por defecto
 * en terminos de TB_* y se pueden override con -DJOTTER_COL_<NOMBRE>=...
 */

/* Paleta neutra de 16 colores. No reordenar: es espejo en IR. */
enum OutColor {
    OUT_DEFAULT      = 0,
    OUT_BLACK        = 1,
    OUT_RED          = 2,
    OUT_GREEN        = 3,
    OUT_YELLOW       = 4,
    OUT_BLUE         = 5,
    OUT_MAGENTA      = 6,
    OUT_CYAN         = 7,
    OUT_WHITE        = 8,
    OUT_BRIGHT_BLACK = 9,
    OUT_BRIGHT_RED   = 10,
    OUT_BRIGHT_GREEN = 11,
    OUT_BRIGHT_YELLOW= 12,
    OUT_BRIGHT_BLUE  = 13,
    OUT_BRIGHT_MAGENTA=14,
    OUT_BRIGHT_CYAN  = 15,
    OUT_BRIGHT_WHITE = 16
};

/* Atributos de texto: bitmask, espejo en IR. */
enum OutAttr {
    OUT_ATTR_NONE      = 0,
    OUT_ATTR_BOLD      = 1 << 0,
    OUT_ATTR_UNDERLINE = 1 << 1,
    OUT_ATTR_REVERSE   = 1 << 2,
    OUT_ATTR_ITALIC    = 1 << 3,
    OUT_ATTR_BLINK     = 1 << 4,
    OUT_ATTR_DIM       = 1 << 5
};

/* Configura el modo de salida (256 colores). Llamar despues de tb_init. */
int out_init(void);

/* Escalares puros sobre la pantalla. Devuelven TB_OK / TB_ERR. */
int out_cell(int32_t x, int32_t y, uint32_t ch,
             int32_t fg, int32_t bg, int32_t attr);
int out_fill(int32_t x, int32_t y, int32_t w, int32_t h,
             uint32_t ch, int32_t fg, int32_t bg, int32_t attr);
/* Texto ASCII (1 byte = 1 celda); CJK/emoji quedan fuera del POC. */
int out_text(int32_t x, int32_t y, const char *s,
             int32_t fg, int32_t bg, int32_t attr);

int out_clear(void);
int out_present(void);
/* (x,y) = posicion del cursor; cualquier coord. negativa lo oculta. */
int out_cursor(int32_t x, int32_t y);
int out_width(void);
int out_height(void);

#endif
