/*
 * test_window.c — tests de la abstraccion de ventana (window.ll).
 */

#include <stdio.h>
#include <stdint.h>

typedef struct { int32_t x, y, w, h; } Rect;

extern void   *window_new(int32_t kind, int32_t x, int32_t y,
                          int32_t w, int32_t h, void *data);
extern void    window_destroy(void *win);
extern int32_t window_kind(void *win);
extern int32_t window_flags(void *win);
extern void   *window_data(void *win);
extern void    window_rect(void *win, Rect *out);
extern void    window_set_rect(void *win, int32_t x, int32_t y,
                               int32_t w, int32_t h);
extern void    window_set_flag(void *win, int32_t flag, int32_t on);
extern int32_t window_is_open(void *win);
extern int32_t window_is_minimized(void *win);
extern int32_t window_is_maximized(void *win);

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)

#define RECT_IS(r, x_, y_, w_, h_) \
    ((r).x == (x_) && (r).y == (y_) && (r).w == (w_) && (r).h == (h_))

int main(void)
{
    int marker = 42;
    Rect r;
    void *win = window_new(0, 3, 4, 70, 20, &marker);

    CHECK(win != NULL, "window_new");
    if (win == NULL) return 1;

    CHECK(window_kind(win) == 0, "kind EDITOR");
    CHECK(window_is_open(win) != 0, "nace abierta (flag OPEN)");
    CHECK(window_is_minimized(win) == 0 && window_is_maximized(win) == 0,
          "no nace minimizada ni maximizada");
    CHECK(window_data(win) == &marker, "data se conserva");
    window_rect(win, &r);
    CHECK(RECT_IS(r, 3, 4, 70, 20), "rect inicial");

    window_set_rect(win, 0, 1, 80, 22);
    window_rect(win, &r);
    CHECK(RECT_IS(r, 0, 1, 80, 22), "window_set_rect");

    window_set_flag(win, 2, 1);
    CHECK(window_is_minimized(win) != 0, "prender MINIMIZED");
    window_set_flag(win, 4, 1);
    CHECK(window_is_maximized(win) != 0, "prender MAXIMIZED");
    CHECK((window_flags(win) & 1) != 0, "OPEN sigue prendido");
    window_set_flag(win, 2, 0);
    CHECK(window_is_minimized(win) == 0, "apagar MINIMIZED");
    CHECK(window_is_maximized(win) != 0, "MAXIMIZED no se apago");

    window_set_flag(win, 1, 0);
    CHECK(window_is_open(win) == 0, "apagar OPEN (cerrar)");

    window_destroy(win);
    printf("=== resumen ===\n");
    printf("  %d ok, %d fail\n", g_pass, g_fail);
    return g_fail > 0 ? 1 : 0;
}
