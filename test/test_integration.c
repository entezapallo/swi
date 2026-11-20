/*
 * test_integration.c — selftest de integracion (mismo flujo, sin termbox).
 * Migrado de tui/main.c: usa los globals compartidos de shell_globals.c.
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "../tui/in.h"
#include "../tui/out.h"
#include "../tui/eval.h"
#include "../tui/fexl_ui.h"
#include "../abi/tui_abi.h"

#ifndef SWI_FEXL_BIN
#define SWI_FEXL_BIN "fexlswi-llvm/bin/fexlswi0"
#endif
#ifndef SWI_UI_SCRIPT
#define SWI_UI_SCRIPT "ui.fxl"
#endif

extern int g_pass, g_fail;
extern UiFrame g_ui;
extern void *g_fileman;

#define SELF_CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)

static void send_event(void *st, void *console, void *ed,
                       int32_t type, int32_t key, uint32_t ch, int32_t mods)
{
    InEvent ev = {0};
    SwiAction a = {0};
    ev.type = type; ev.key = key; ev.ch = ch; ev.mods = mods;
    state_step(st, &ev, 1, &a);
    (void)shell_dispatch(st, console, ed, &a);
}

int main(void)
{
    const char *path = "/tmp/swi_selftest.txt";
    FILE *f = fopen(path, "wb");
    void *st, *canvas, *ed, *console;
    char buf[32];
    int64_t len;

    if (f == NULL) return 1;
    swi_eval_set_bin(SWI_FEXL_BIN);
    fwrite("hola\nmundo\n", 1, 11, f);
    fclose(f);
    g_fileman = fileman_new();
    if (g_fileman == NULL) return 1;
    st = state_new(); canvas = canvas_new(); ed = win_editor_new(path);
    console = console_new();
    if (!st || !canvas || !ed || !console) return 1;
    canvas_set_size(canvas, 80, 24);
    (void)canvas_open(canvas, 0, ed);
    console_set_eval(console, swi_eval);

    printf("=== swi --selftest (integracion) ===\n");
    memset(&g_ui, 0, sizeof(g_ui));
    g_ui.console_h = 3;
    if (fexl_ui_start(SWI_FEXL_BIN, SWI_UI_SCRIPT)) {
        shell_ui_sync(FUI_INIT, 3, 0, 0);
        SELF_CHECK(g_ui.nbind > 0 && strcmp(g_ui.bind[0].act, "console.toggle") == 0,
                   "driver Fexl responde con BIND desde ui.fxl");
        shell_ui_sync(FUI_CONSOLE, 3, 0, 0);
        SELF_CHECK(g_ui.console_h == 10, "driver aplica toggle de consola");
        fexl_ui_stop();
    } else {
        SELF_CHECK(0, "driver Fexl no disponible");
    }
    SELF_CHECK(win_editor_cursor(ed) == 0, "cursor inicial 0");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'i', 0);
    SELF_CHECK(state_mode(st) == 1, "i entra a INSERT");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'X', 0);
    len = doc_length(win_editor_doc(ed));
    doc_read(win_editor_doc(ed), 0, 1, buf);
    SELF_CHECK(len == 12 && buf[0] == 'X', "INSERT 'X' al principio");
    send_event(st, console, ed, IN_EV_KEY, IN_KEY_ESC, 0, 0);
    SELF_CHECK(state_mode(st) == 0, "Esc vuelve a NORMAL");
    send_event(st, console, ed, IN_EV_CHAR, 0, '0', 0);
    SELF_CHECK(win_editor_cursor(ed) == 0, "0 -> inicio de linea");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'x', 0);
    doc_read(win_editor_doc(ed), 0, 1, buf);
    SELF_CHECK(buf[0] == 'h', "x borra el caracter bajo el cursor");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'u', 0);
    doc_read(win_editor_doc(ed), 0, 1, buf);
    SELF_CHECK(buf[0] == 'X', "u deshace la borradura");
    send_event(st, console, ed, IN_EV_CHAR, 0, '/', 0);
    send_event(st, console, ed, IN_EV_CHAR, 0, 'm', 0);
    send_event(st, console, ed, IN_EV_CHAR, 0, 'u', 0);
    send_event(st, console, ed, IN_EV_CHAR, 0, 'n', 0);
    send_event(st, console, ed, IN_EV_CHAR, 0, 'd', 0);
    send_event(st, console, ed, IN_EV_CHAR, 0, 'o', 0);
    send_event(st, console, ed, IN_EV_KEY, IN_KEY_ENTER, 0, 0);
    SELF_CHECK(win_editor_cursor(ed) == 6, "/mundo lleva el cursor al offset 6");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'n', 0);
    SELF_CHECK(win_editor_cursor(ed) == 6, "n con un solo match hace wrap al mismo offset");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'd', 0);
    send_event(st, console, ed, IN_EV_CHAR, 0, 'd', 0);
    len = doc_length(win_editor_doc(ed));
    SELF_CHECK(len == 6, "dd borra la linea 'mundo' (quedan 6 bytes)");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'p', 0);
    len = doc_length(win_editor_doc(ed));
    SELF_CHECK(len == 12, "p restaura la linea desde el registro");

    printf("  %d ok, %d fail\n", g_pass, g_fail);
    console_destroy(console); canvas_destroy(canvas);
    win_editor_destroy(ed); state_free(st);
    fileman_destroy(g_fileman); g_fileman = NULL;
    remove(path);
    return g_fail > 0 ? 1 : 0;
}

/* stubs de C/IR que no se linkean en este arnes */
int out_cell(int32_t x, int32_t y, uint32_t ch,
             int32_t fg, int32_t bg, int32_t attr)
{ (void)x;(void)y;(void)ch;(void)fg;(void)bg;(void)attr; return 0; }
int out_fill(int32_t x, int32_t y, int32_t w, int32_t h,
             uint32_t ch, int32_t fg, int32_t bg, int32_t attr)
{ (void)x;(void)y;(void)w;(void)h;(void)ch;(void)fg;(void)bg;(void)attr; return 0; }
int out_text(int32_t x, int32_t y, const char *s,
             int32_t fg, int32_t bg, int32_t attr)
{ (void)x;(void)y;(void)s;(void)fg;(void)bg;(void)attr; return 0; }
int swi_set_wd(const char *path) { (void)path; return 1; }
int swi_print_wd(void) { return 1; }
