/*
 * out.c — dibuja con escalares sobre termbox.
 *
 * Unico lugar de la TUI que conoce termbox junto con main.c (que tiene
 * TB_IMPL). El IR entrega numeros de la paleta de out.h; aca se mapean a
 * constantes TB_*. El colorscheme se puede cambiar en compilacion con
 * -DJOTTER_COL_RED=0x01 etc. (valor ya mapeado a TB_OUTPUT_256).
 */

#include "out.h"
#include "termbox2.h"

/* --- colorscheme default (TB_OUTPUT_256) ---
 * 0x00 = default, TB_HI_BLACK = negro, 0x01..0x07 = normales,
 * 0x08..0x0f = brillantes. Ver doc de tb_set_cell en termbox2.h.
 */
#ifndef JOTTER_COL_DEFAULT
#define JOTTER_COL_DEFAULT TB_DEFAULT
#endif
#ifndef JOTTER_COL_BLACK
#define JOTTER_COL_BLACK   TB_HI_BLACK
#endif
#ifndef JOTTER_COL_RED
#define JOTTER_COL_RED     0x01
#endif
#ifndef JOTTER_COL_GREEN
#define JOTTER_COL_GREEN   0x02
#endif
#ifndef JOTTER_COL_YELLOW
#define JOTTER_COL_YELLOW  0x03
#endif
#ifndef JOTTER_COL_BLUE
#define JOTTER_COL_BLUE    0x04
#endif
#ifndef JOTTER_COL_MAGENTA
#define JOTTER_COL_MAGENTA 0x05
#endif
#ifndef JOTTER_COL_CYAN
#define JOTTER_COL_CYAN    0x06
#endif
#ifndef JOTTER_COL_WHITE
#define JOTTER_COL_WHITE   0x07
#endif
#ifndef JOTTER_COL_BRIGHT_BLACK
#define JOTTER_COL_BRIGHT_BLACK  0x08
#endif
#ifndef JOTTER_COL_BRIGHT_RED
#define JOTTER_COL_BRIGHT_RED    0x09
#endif
#ifndef JOTTER_COL_BRIGHT_GREEN
#define JOTTER_COL_BRIGHT_GREEN  0x0a
#endif
#ifndef JOTTER_COL_BRIGHT_YELLOW
#define JOTTER_COL_BRIGHT_YELLOW 0x0b
#endif
#ifndef JOTTER_COL_BRIGHT_BLUE
#define JOTTER_COL_BRIGHT_BLUE   0x0c
#endif
#ifndef JOTTER_COL_BRIGHT_MAGENTA
#define JOTTER_COL_BRIGHT_MAGENTA 0x0d
#endif
#ifndef JOTTER_COL_BRIGHT_CYAN
#define JOTTER_COL_BRIGHT_CYAN   0x0e
#endif
#ifndef JOTTER_COL_BRIGHT_WHITE
#define JOTTER_COL_BRIGHT_WHITE  0x0f
#endif

static uintattr_t map_color(int32_t c)
{
    switch (c) {
    case OUT_DEFAULT:       return JOTTER_COL_DEFAULT;
    case OUT_BLACK:         return JOTTER_COL_BLACK;
    case OUT_RED:           return JOTTER_COL_RED;
    case OUT_GREEN:         return JOTTER_COL_GREEN;
    case OUT_YELLOW:        return JOTTER_COL_YELLOW;
    case OUT_BLUE:          return JOTTER_COL_BLUE;
    case OUT_MAGENTA:       return JOTTER_COL_MAGENTA;
    case OUT_CYAN:          return JOTTER_COL_CYAN;
    case OUT_WHITE:         return JOTTER_COL_WHITE;
    case OUT_BRIGHT_BLACK:  return JOTTER_COL_BRIGHT_BLACK;
    case OUT_BRIGHT_RED:    return JOTTER_COL_BRIGHT_RED;
    case OUT_BRIGHT_GREEN:  return JOTTER_COL_BRIGHT_GREEN;
    case OUT_BRIGHT_YELLOW: return JOTTER_COL_BRIGHT_YELLOW;
    case OUT_BRIGHT_BLUE:   return JOTTER_COL_BRIGHT_BLUE;
    case OUT_BRIGHT_MAGENTA:return JOTTER_COL_BRIGHT_MAGENTA;
    case OUT_BRIGHT_CYAN:   return JOTTER_COL_BRIGHT_CYAN;
    case OUT_BRIGHT_WHITE:  return JOTTER_COL_BRIGHT_WHITE;
    default:                return JOTTER_COL_DEFAULT;
    }
}

static uintattr_t map_attr(int32_t a)
{
    uintattr_t r = 0;
    if (a & OUT_ATTR_BOLD)      r |= TB_BOLD;
    if (a & OUT_ATTR_UNDERLINE) r |= TB_UNDERLINE;
    if (a & OUT_ATTR_REVERSE)   r |= TB_REVERSE;
    if (a & OUT_ATTR_ITALIC)    r |= TB_ITALIC;
    if (a & OUT_ATTR_BLINK)     r |= TB_BLINK;
    if (a & OUT_ATTR_DIM)       r |= TB_DIM;
    return r;
}

int out_init(void)
{
    return tb_set_output_mode(TB_OUTPUT_256);
}

int out_cell(int32_t x, int32_t y, uint32_t ch,
             int32_t fg, int32_t bg, int32_t attr)
{
    return tb_set_cell(x, y, ch,
                       map_color(fg) | map_attr(attr),
                       map_color(bg));
}

int out_fill(int32_t x, int32_t y, int32_t w, int32_t h,
             uint32_t ch, int32_t fg, int32_t bg, int32_t attr)
{
    uintattr_t f = map_color(fg) | map_attr(attr);
    uintattr_t b = map_color(bg);
    int rc = TB_OK;

    for (int32_t row = 0; row < h; row++) {
        for (int32_t col = 0; col < w; col++) {
            int r = tb_set_cell(x + col, y + row, ch, f, b);
            if (r != TB_OK) rc = r;
        }
    }
    return rc;
}

int out_text(int32_t x, int32_t y, const char *s,
             int32_t fg, int32_t bg, int32_t attr)
{
    uintattr_t f = map_color(fg) | map_attr(attr);
    uintattr_t b = map_color(bg);
    int32_t col = 0;
    int rc = TB_OK;

    if (s == NULL) return TB_OK;
    while (*s != '\0') {
        int r = tb_set_cell(x + col, y, (uint32_t)(unsigned char)*s, f, b);
        if (r != TB_OK) rc = r;
        s++;
        col++;
    }
    return rc;
}

int out_clear(void)    { return tb_clear(); }
int out_present(void)  { return tb_present(); }
int out_width(void)    { return tb_width(); }
int out_height(void)   { return tb_height(); }

int out_cursor(int32_t x, int32_t y)
{
    if (x < 0 || y < 0) return tb_hide_cursor();
    return tb_set_cursor(x, y);
}
