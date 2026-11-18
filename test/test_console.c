/*
 * test_console.c — tests de la linea de comandos (console.ll).
 * Usa stubs C para las funciones de win_editor: no linkea el motor.
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "../abi/tui_abi.h"

static int n_save, n_saveas, n_quit, n_search;
static char last_path[128];
static char last_pat[128];
static int last_forward;
static int n_eval;
static char last_eval[128];

/* stub del intérprete externo (callback registrado con console_set_eval) */
static int eval_stub(const char *line, int64_t len)
{
    n_eval++;
    memcpy(last_eval, line, (size_t)len);
    last_eval[len] = '\0';
    return 1;
}

/* stubs de las funciones que console.ll declara */
int win_editor_save(void *ed)        { (void)ed; n_save++; return 1; }
int win_editor_save_as(void *ed, const char *p)
{
    (void)ed;
    n_saveas++;
    strncpy(last_path, p, sizeof(last_path) - 1);
    last_path[sizeof(last_path) - 1] = '\0';
    return 1;
}
void win_editor_request_quit(void *ed) { (void)ed; n_quit++; }
int win_editor_open(void *ed, const char *path)
{
    (void)ed; (void)path; return 1;
}
const char *win_editor_path(void *ed) { (void)ed; return "/tmp/stub.txt"; }
int win_editor_search(void *ed, const char *pat, int64_t len, int32_t fwd)
{
    (void)ed;
    n_search++;
    last_forward = fwd;
    memcpy(last_pat, pat, (size_t)len);
    last_pat[len] = '\0';
    return 1;
}

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)

static void type_str(void *c, const char *s)
{
    while (*s != '\0') {
        console_push(c, (unsigned char)*s);
        s++;
    }
}

int main(void)
{
    void *c = console_new();
    void *fake_ed = (void *)0x1234;

    CHECK(c != NULL, "console_new");
    if (c == NULL) return 1;
    CHECK(console_prefix(c) == 0 && console_len(c) == 0, "estado inicial");

    printf("=== console.ll: comandos ':' ===\n");
    console_reset(c, ':');
    type_str(c, "w");
    CHECK(console_len(c) == 1 && strcmp(console_text(c), "w") == 0,
          "push 'w' arma el buffer");
    CHECK(console_execute(c, fake_ed) == 1 && n_save == 1, ":w llama save");

    console_reset(c, ':');
    type_str(c, "q");
    CHECK(console_execute(c, fake_ed) == 1 && n_quit == 1, ":q pide quit");

    console_reset(c, ':');
    type_str(c, "wq");
    console_execute(c, fake_ed);
    CHECK(n_save == 2 && n_quit == 2, ":wq guarda y sale");

    console_reset(c, ':');
    type_str(c, "w /tmp/x");
    console_execute(c, fake_ed);
    CHECK(n_saveas == 1 && strcmp(last_path, "/tmp/x") == 0,
          ":w /tmp/x usa save_as con la ruta");

    console_reset(c, ':');
    type_str(c, "basura");
    CHECK(console_execute(c, fake_ed) == 0,
          "comando desconocido sin eval -> 0");

    printf("=== console.ll: delegacion al interprete ===\n");
    console_set_eval(c, eval_stub);
    console_reset(c, ':');
    type_str(c, "(regex.count ... )");
    CHECK(console_execute(c, fake_ed) == 1 && n_eval == 1 &&
          strcmp(last_eval, "(regex.count ... )") == 0,
          "comando desconocido con eval -> delega la linea al interprete");

    printf("=== console.ll: busqueda y backspace ===\n");
    console_reset(c, '/');
    type_str(c, "foo");
    CHECK(console_execute(c, fake_ed) == 1 && n_search == 1 &&
          strcmp(last_pat, "foo") == 0 && last_forward == 1,
          "/foo busca hacia adelante y guarda el patron");
    CHECK(console_repeat(c, fake_ed, 0) == 1 && n_search == 2 &&
          last_forward == 0, "N repite hacia atras");
    CHECK(console_repeat(c, fake_ed, 1) == 1 && n_search == 3 &&
          last_forward == 1, "n repite hacia adelante");

    console_reset(c, ':');
    type_str(c, "wxyz");
    console_push(c, 8);
    CHECK(console_len(c) == 3 && strcmp(console_text(c), "wxy") == 0,
          "backspace (8) borra el ultimo caracter");

    printf("=== console.ll: abrir archivo (:e) ===\n");
    console_reset(c, ':');
    type_str(c, "e /tmp/otro.txt");
    CHECK(console_execute(c, fake_ed) == 1,
          ":e /tmp/otro.txt se ejecuta");
    console_reset(c, ':');
    type_str(c, "e");
    CHECK(console_execute(c, fake_ed) == 1,
          ":e sin ruta recarga el archivo actual");
    console_reset(c, ':');
    type_str(c, "q!");
    CHECK(console_execute(c, fake_ed) == 1 && n_quit == 3,
          ":q! sale sin guardar");

    console_destroy(c);
    printf("=== resumen ===\n");
    printf("  %d ok, %d fail\n", g_pass, g_fail);
    return g_fail > 0 ? 1 : 0;
}
