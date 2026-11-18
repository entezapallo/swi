/*
 * test_win_editor.c — tests de la ventana del editor (win_editor.ll).
 * Linkea el motor del editor completo; usa acciones directas (sin state).
 */

#include <stdio.h>
#include <string.h>
#include "../abi/tui_abi.h"

/* out_cell no se usa en estos tests, pero win_editor.ll lo declara */
int out_cell(int32_t x, int32_t y, int32_t ch,
             int32_t fg, int32_t bg, int32_t attr)
{
    (void)x; (void)y; (void)ch; (void)fg; (void)bg; (void)attr;
    return 0;
}

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)

static void write_file(const char *path, const char *data, int n)
{
    FILE *f = fopen(path, "wb");
    fwrite(data, 1, (size_t)n, f);
    fclose(f);
}

static int step(void *ed, int kind, int64_t a, int64_t b, int64_t c)
{
    SwiAction act = { kind, a, b, c };
    return win_editor_step(ed, &act);
}

static const char *text(void *ed, int64_t *len)
{
    void *tb = doc_textbuffer(win_editor_doc(ed));
    *len = tb_length(tb);
    return tb_data(tb);
}

int main(void)
{
    const char *p1 = "/tmp/twe_words.txt";
    const char *p2 = "/tmp/twe_scroll.txt";
    const char *p3 = "/tmp/twe_long.txt";
    void *ed;
    int64_t len;
    const char *s;
    int64_t i;

    write_file(p1, "alpha beta\ngamma delta\n", 23);
    ed = win_editor_new(p1);
    CHECK(ed != NULL, "win_editor_new");
    if (ed == NULL) return 1;

    printf("=== win_editor.ll: movimientos de palabra ===\n");
    win_editor_set_view(ed, 24, 80);
    step(ed, 3, 9, 1, 0);   /* w */
    CHECK(win_editor_cursor(ed) == 6, "w -> inicio de 'beta' (6)");
    step(ed, 3, 9, 1, 0);   /* w */
    CHECK(win_editor_cursor(ed) == 11, "w -> inicio de 'gamma' (11)");
    step(ed, 3, 10, 1, 0);  /* b */
    CHECK(win_editor_cursor(ed) == 6, "b -> vuelve a 'beta' (6)");
    step(ed, 3, 11, 1, 0);  /* e */
    CHECK(win_editor_cursor(ed) == 9, "e -> final de 'beta' (9)");
    win_editor_destroy(ed);

    printf("=== win_editor.ll: scroll vertical ===\n");
    {
        char buf[300];
        int n = 0;
        for (i = 0; i < 60; i++)
            n += sprintf(buf + n, "L%02d\n", (int)i);
        (void)n;
        write_file(p2, buf, n);
    }
    ed = win_editor_new(p2);
    win_editor_set_view(ed, 5, 80);
    step(ed, 3, 8, 1, 0);   /* G -> doc_end */
    CHECK(win_editor_cursor(ed) > 0, "G mueve al final del documento");
    /* 60 '\n' => 61 lineas (la ultima vacia); top = 60 - 5 + 1 = 56 */
    CHECK(win_editor_top_line(ed) == 56, "top_line sigue al cursor (56)");
    win_editor_destroy(ed);

    printf("=== win_editor.ll: scroll horizontal y c ===\n");
    {
        char big[201];
        memset(big, 'a', 200);
        write_file(p3, big, 200);
    }
    ed = win_editor_new(p3);
    win_editor_set_view(ed, 5, 10);
    step(ed, 3, 2, 30, 0);  /* 30l */
    CHECK(win_editor_cursor(ed) == 30, "cursor en columna 30");
    CHECK(win_editor_hscroll(ed) == 21, "hscroll automatico = 21");
    step(ed, 12, -1, 5, 0); /* 5< */
    CHECK(win_editor_hscroll(ed) == 16, "< baja hscroll a 16");
    step(ed, 12, 1, 100, 0);
    CHECK(win_editor_hscroll(ed) >= 0, "> con clamp no va negativo");

    CHECK((step(ed, 5, 4, 1, 0) & 4) != 0, "cc pide want_insert (bit 4)");
    win_editor_destroy(ed);

    printf("=== win_editor.ll: y + movimiento ===\n");
    ed = win_editor_new(p1);
    win_editor_set_view(ed, 24, 80);
    s = text(ed, &len);
    CHECK(len == 23, "buffer inicial de 23 bytes");
    step(ed, 4, 2, 2, 1);   /* yl sobre 'a' */
    step(ed, 5, 5, 1, 0);   /* p */
    s = text(ed, &len);
    CHECK(len == 24 && s[0] == 'a' && s[1] == 'a',
          "yl + p duplica el caracter yanked");
    win_editor_destroy(ed);

    printf("=== win_editor.ll: resaltado (format.ll) ===\n");
    {
        const char *p4 = "/tmp/twe_hl.txt";
        void *e2;
        write_file(p4, "foo bar foo baz foo", 19);
        e2 = win_editor_new(p4);
        CHECK(e2 != NULL && win_editor_hl_count(e2) == 0,
              "sin patron -> 0 spans");
        win_editor_set_highlight(e2, "foo", 3);
        CHECK(win_editor_hl_count(e2) == 3, "resaltado 'foo' -> 3 spans");
        win_editor_set_highlight(e2, "bar", 3);
        CHECK(win_editor_hl_count(e2) == 1, "cambio de patron -> 1 span");
        win_editor_set_highlight(e2, "", 0);
        CHECK(win_editor_hl_count(e2) == 0, "patron vacio limpia resaltado");
        win_editor_destroy(e2);
        remove(p4);
    }

    printf("=== win_editor.ll: seleccion VISUAL ===\n");
    {
        const char *p5 = "/tmp/twe_visual.txt";
        void *e3;
        write_file(p5, "hello world test", 16);
        e3 = win_editor_new(p5);
        step(e3, 1, 2, 0, 0);        /* MODE VISUAL -> anchor = cursor(0) */
        CHECK(win_editor_visual(e3) == 1 && win_editor_anchor(e3) == 0,
              "v activa VISUAL con anchor en 0");
        step(e3, 3, 2, 5, 0);        /* 5l -> cursor 5 */
        CHECK(win_editor_cursor(e3) == 5 && win_editor_anchor(e3) == 0,
              "motion mueve cursor, anchor fijo");
        step(e3, 14, 2, 0, 0);       /* VISUAL_OP y -> yank [0,5) */
        CHECK(win_editor_visual(e3) == 0, "y sale de VISUAL");
        step(e3, 5, 5, 1, 0);        /* p -> pega "hello" */
        {
            const char *t = text(e3, &len);
            CHECK(len == 21 && strncmp(t, "hellohello world", 16) == 0,
                  "yank+p duplica seleccion");
        }
        /* d sobre seleccion */
        step(e3, 1, 2, 0, 0);        /* VISUAL de nuevo, anchor=cursor(5) */
        step(e3, 3, 1, 3, 0);        /* 3h -> cursor 2 */
        step(e3, 14, 1, 0, 0);       /* VISUAL_OP d -> borra [2,5) */
        {
            const char *t = text(e3, &len);
            CHECK(len == 18 && strncmp(t, "hellohe world test", 18) == 0,
                  "d borra el rango seleccionado");
        }
        win_editor_destroy(e3);
        remove(p5);
    }

    (void)s;
    printf("=== resumen ===\n");
    printf("  %d ok, %d fail\n", g_pass, g_fail);
    return g_fail > 0 ? 1 : 0;
}
