/*
 * test_canvas.c — tests del layout (canvas_layout) y del motor de ventanas.
 */

#include <stdio.h>
#include <stdint.h>

typedef struct { int32_t x, y, w, h; } Rect;

extern void    canvas_layout(int32_t w, int32_t h,
                             Rect *top, Rect *body, Rect *bottom);
extern void    canvas_layout_panels(int32_t w, int32_t h,
                                    int32_t con_h, int32_t fm_w,
                                    Rect *tabs, Rect *buf, Rect *con, Rect *fm);
extern void   *canvas_new(void);
extern void    canvas_destroy(void *c);
extern void    canvas_set_size(void *c, int32_t w, int32_t h);
extern int32_t canvas_count(void *c);
extern void   *canvas_active(void *c);
extern void    canvas_set_active(void *c, void *win);
extern void   *canvas_at(void *c, int32_t idx);
extern void   *canvas_open(void *c, int32_t kind, void *data);
extern int32_t canvas_close(void *c, void *win);
extern void    canvas_minimize(void *c, void *win);
extern void    canvas_maximize(void *c, void *win);
extern void    canvas_body_rect(void *c, Rect *out);
extern int32_t window_is_minimized(void *win);
extern int32_t window_is_maximized(void *win);
extern void    window_rect(void *win, Rect *out);
extern void   *window_data(void *win);

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
    printf("=== canvas.ll: layout ===\n");
    {
        Rect t, b, bot;
        canvas_layout(80, 24, &t, &b, &bot);
        CHECK(RECT_IS(t, 0, 0, 80, 1) && RECT_IS(b, 0, 1, 80, 22) &&
              RECT_IS(bot, 0, 23, 80, 1), "layout 80x24");
        canvas_layout(80, 3, &t, &b, &bot);
        CHECK(RECT_IS(b, 0, 1, 80, 1), "canvas de 1 fila (80x3)");
        canvas_layout(80, 2, &t, &b, &bot);
        CHECK(RECT_IS(t, 0, 0, 80, 1) && RECT_IS(b, 0, 0, 0, 0) &&
              RECT_IS(bot, 0, 1, 80, 1), "dos barras sin canvas (80x2)");
        canvas_layout(80, 1, &t, &b, &bot);
        CHECK(RECT_IS(t, 0, 0, 80, 1) && RECT_IS(bot, 0, 0, 0, 0),
              "solo barra arriba (80x1)");
        canvas_layout(0, 24, &t, &b, &bot);
        CHECK(RECT_IS(t, 0, 0, 0, 0), "ancho 0 -> todo cero");
    }

    printf("=== canvas.ll: composicion de paneles ===\n");
    {
        Rect tabs, buf, con, fm;
        canvas_layout_panels(100, 30, 3, 0, &tabs, &buf, &con, &fm);
        CHECK(RECT_IS(tabs, 0, 1, 100, 1) &&
              RECT_IS(buf, 0, 2, 100, 24) &&
              RECT_IS(con, 0, 26, 100, 3) && RECT_IS(fm, 0, 2, 0, 24),
              "paneles 100x30 con consola brief");
        canvas_layout_panels(100, 30, 8, 40, &tabs, &buf, &con, &fm);
        CHECK(RECT_IS(con, 0, 21, 100, 8) &&
              RECT_IS(fm, 0, 2, 40, 19) && RECT_IS(buf, 40, 2, 60, 19),
              "consola extendida + file manager");
        canvas_layout_panels(100, 30, 99, 999, &tabs, &buf, &con, &fm);
        CHECK(con.h == 27 && fm.w == 90 && buf.w == 10,
              "clamp de pesos fuera de rango");
        canvas_layout_panels(0, 2, 3, 40, &tabs, &buf, &con, &fm);
        CHECK(RECT_IS(buf, 0, 0, 0, 0), "pantalla invalida -> todo cero");
    }

    printf("=== canvas.ll: motor de ventanas ===\n");
    {
        void *c = canvas_new();
        int a = 1, b = 2;
        void *w1, *w2;
        Rect r;

        CHECK(c != NULL, "canvas_new");
        if (c == NULL) return 1;
        canvas_set_size(c, 80, 24);
        canvas_body_rect(c, &r);
        CHECK(RECT_IS(r, 0, 1, 80, 22), "body rect desde el canvas");

        w1 = canvas_open(c, 0, &a);
        CHECK(w1 != NULL && canvas_count(c) == 1, "abrir ventana 1");
        CHECK(canvas_active(c) == w1, "la nueva queda activa");
        CHECK(window_is_maximized(w1) != 0, "abre maximizada");
        CHECK(window_data(w1) == &a, "data de la clase se conserva");
        window_rect(w1, &r);
        CHECK(RECT_IS(r, 0, 1, 80, 22), "rect de la ventana = body");

        w2 = canvas_open(c, 1, &b);
        CHECK(w2 != NULL && canvas_count(c) == 2 && canvas_active(c) == w2,
              "abrir ventana 2 la vuelve activa");
        CHECK(canvas_at(c, 0) == w1 && canvas_at(c, 1) == w2, "canvas_at");
        CHECK(canvas_at(c, 5) == NULL, "canvas_at fuera de rango -> NULL");

        canvas_minimize(c, w2);
        CHECK(window_is_minimized(w2) != 0, "minimizar");
        CHECK(canvas_active(c) == NULL, "minimizar la activa la desactiva");
        canvas_maximize(c, w1);
        CHECK(canvas_active(c) == w1 && window_is_minimized(w1) == 0,
              "maximizar vuelve a activar y desminimiza");

        canvas_set_active(c, w2);
        CHECK(canvas_active(c) == w2, "canvas_set_active");
        CHECK(canvas_close(c, w1) == 1 && canvas_count(c) == 1,
              "cerrar ventana 1");
        CHECK(canvas_at(c, 0) == w2, "la ventana 2 corrio a la posicion 0");
        CHECK(canvas_close(c, w1) == 0, "cerrar dos veces -> 0");

        canvas_destroy(c);
        CHECK(1, "canvas_destroy sin crash");
    }

    printf("=== resumen ===\n");
    printf("  %d ok, %d fail\n", g_pass, g_fail);
    return g_fail > 0 ? 1 : 0;
}
