/*
 * test_state.c — tests del motor de modos (state.ll).
 *
 * eventos sinteticos -> %Action. No necesita termbox ni el motor del editor.
 */

#include <stdio.h>
#include "tui/in.h"

/* espejo de %Action = { i32, i64, i64, i64 } */
typedef struct { int32_t kind; int64_t a, b, c; } Action;

extern void   *state_new(void);
extern void    state_free(void *);
extern int32_t state_mode(void *);
extern int32_t state_prefix(void *);
extern int64_t state_count(void *);
extern int32_t state_pending_op(void *);
extern void    state_step(void *st, InEvent *ev, int32_t editable, Action *out);

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)

#define ACT_IS(a, k, a1, b1, c1) \
    ((a).kind == (k) && (a).a == (a1) && (a).b == (b1) && (a).c == (c1))

enum { A_NONE=0, A_MODE=1, A_CHAR=2, A_MOTION=3, A_OP=4, A_EDIT=5,
       A_CMDLINE=6, A_EXEC=7, A_CANCEL=8, A_QUIT=9, A_REJECT=10 };
enum { M_LEFT=1, M_RIGHT=2, M_UP=3, M_DOWN=4, M_LSTART=5, M_LEND=6,
       M_DSTART=7, M_DEND=8 };

static InEvent ev_char(uint32_t ch, int32_t mods)
{
    InEvent e = {0};
    e.type = IN_EV_CHAR; e.ch = ch; e.mods = mods;
    return e;
}

static InEvent ev_key(int32_t key)
{
    InEvent e = {0};
    e.type = IN_EV_KEY; e.key = key;
    return e;
}

static void step(void *st, InEvent *ev, int32_t editable, Action *out)
{
    out->kind = -1; out->a = out->b = out->c = -1;
    state_step(st, ev, editable, out);
}

int main(void)
{
    void *st = state_new();
    InEvent ev;
    Action a;

    CHECK(st != NULL, "state_new");
    if (st == NULL) return 1;

    printf("=== state.ll: modos ===\n");
    CHECK(state_mode(st) == 0 && state_prefix(st) == 0 &&
          state_count(st) == 0 && state_pending_op(st) == 0, "estado inicial");

    ev = ev_char('i', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MODE, 1, 0, 0) && state_mode(st) == 1,
          "NORMAL + i -> MODE INSERT");

    ev = ev_char('a', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_CHAR, 'a', 0, 0), "INSERT + 'a' -> INSERT_CHAR");

    /* regresion: en INSERT h/j/k/l son TEXTO, no movimientos vi */
    {
        const char *vimkeys = "hjkl";
        int i, ok = 1;
        for (i = 0; vimkeys[i]; i++) {
            ev = ev_char((uint32_t)vimkeys[i], 0); step(st, &ev, 1, &a);
            if (!ACT_IS(a, A_CHAR, vimkeys[i], 0, 0)) ok = 0;
        }
        CHECK(ok, "INSERT + h/j/k/l -> INSERT_CHAR (no motion)");
    }
    ev = ev_key(IN_KEY_DOWN); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MOTION, M_DOWN, 1, 0),
          "INSERT + flecha abajo -> MOTION (sigue siendo tecla)");

    ev = ev_key(IN_KEY_ESC); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MODE, 0, 0, 0) && state_mode(st) == 0,
          "INSERT + Esc -> MODE NORMAL");

    ev = ev_char('i', IN_MOD_CTRL); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_NONE, 0, 0, 0) && state_mode(st) == 0,
          "Ctrl+i no es comando");

    ev = ev_char('i', 0); step(st, &ev, 0, &a);
    CHECK(ACT_IS(a, A_REJECT, 0, 0, 0), "i en solo-lectura -> REJECTED");

    ev = ev_char('v', 0); step(st, &ev, 1, &a);
    CHECK(state_mode(st) == 2, "NORMAL + v -> VISUAL");
    ev = ev_char(':', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MODE, 3, ':', 0) && state_prefix(st) == ':',
          "VISUAL + : -> COMMAND con prefijo");
    ev = ev_key(IN_KEY_ESC); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_CANCEL, 0, 0, 0) && state_prefix(st) == 0,
          "COMMAND + Esc cancela y limpia prefijo");

    ev = ev_char('/', 0); step(st, &ev, 1, &a);
    CHECK(state_mode(st) == 3 && state_prefix(st) == '/',
          "NORMAL + / -> COMMAND prefijo '/'");
    ev = ev_char('f', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_CMDLINE, 'f', '/', 0), "COMMAND + char -> CMDLINE");
    ev = ev_key(IN_KEY_BACKSPACE); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_CMDLINE, 8, '/', 0), "COMMAND + Backspace -> CMDLINE(8)");
    ev = ev_key(IN_KEY_ENTER); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_EXEC, 0, 0, 0) && state_mode(st) == 0,
          "COMMAND + Enter -> EXECUTE, vuelve a NORMAL");

    printf("=== state.ll: movimientos y count ===\n");
    ev = ev_char('h', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MOTION, M_LEFT, 1, 0), "h -> MOTION left (count 1)");

    ev = ev_char('3', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_NONE, 0, 0, 0) && state_count(st) == 3, "'3' acumula count");
    ev = ev_char('j', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MOTION, M_DOWN, 3, 0) && state_count(st) == 0,
          "3j -> MOTION down count=3, count se resetea");

    ev = ev_char('0', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MOTION, M_LSTART, 1, 0), "'0' sin count -> inicio de linea");
    ev = ev_char('3', 0); step(st, &ev, 1, &a);
    ev = ev_char('0', 0); step(st, &ev, 1, &a);
    CHECK(state_count(st) == 30, "'3' + '0' -> count 30");
    ev = ev_char('l', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MOTION, M_RIGHT, 30, 0), "30l -> MOTION right count=30");

    ev = ev_char('G', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MOTION, M_DEND, 1, 0), "G -> fin de documento");
    ev = ev_char('g', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_NONE, 0, 0, 0), "primer 'g' -> espera el segundo");
    ev = ev_char('g', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MOTION, M_DSTART, 1, 0), "gg -> inicio de documento");

    ev = ev_key(IN_KEY_UP); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_MOTION, M_UP, 1, 0), "tecla flecha arriba -> MOTION up");

    printf("=== state.ll: operadores y ediciones ===\n");
    ev = ev_char('x', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_EDIT, 1, 1, 0), "x -> EDIT x");

    ev = ev_char('d', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_NONE, 0, 0, 0) && state_pending_op(st) == 1,
          "'d' queda pendiente");
    ev = ev_char('d', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_EDIT, 2, 1, 0) && state_pending_op(st) == 0,
          "dd -> EDIT dd, pendiente se limpia");

    ev = ev_char('y', 0); step(st, &ev, 1, &a);
    ev = ev_char('l', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_OP, 2, M_RIGHT, 1), "yl -> OPERATOR y + motion right");

    ev = ev_char('u', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_EDIT, 6, 1, 0), "u -> EDIT undo");
    ev = ev_char('r', IN_MOD_CTRL); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_EDIT, 7, 1, 0), "Ctrl+r -> EDIT redo");
    ev = ev_char('p', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_EDIT, 5, 1, 0), "p -> EDIT paste");

    ev = ev_char('n', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, 11, 1, 0, 0), "n -> SEARCH_NEXT forward");
    ev = ev_char('N', 0); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, 11, 0, 0, 0), "N -> SEARCH_NEXT backward");

    ev = ev_char('q', IN_MOD_CTRL); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_QUIT, 0, 0, 0), "Ctrl+q -> QUIT");
    ev = ev_key(IN_KEY_F10); step(st, &ev, 1, &a);
    CHECK(ACT_IS(a, A_QUIT, 0, 0, 0), "F10 -> QUIT");

    state_free(st);
    printf("=== resumen ===\n");
    printf("  %d ok, %d fail\n", g_pass, g_fail);
    return g_fail > 0 ? 1 : 0;
}
