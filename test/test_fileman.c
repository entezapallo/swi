/*
 * test_fileman.c — arnés del file manager (tui/fileman.ll).
 * Stubs de fsio y out: no linkea el motor ni termbox.
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "../abi/tui_abi.h"

static char g_entries[40][16];
static char *g_list[40];
static int n_out_text;
static int n_out_fill;

int fsio_list_dir(const char *path, char ***out, int64_t *count)
{
    int i;
    (void)path;
    for (i = 0; i < 40; i++) {
        snprintf(g_entries[i], sizeof(g_entries[i]), "f%02d", i);
        g_list[i] = g_entries[i];
    }
    *out = g_list;
    *count = 40;
    return 1;
}
void fsio_free_dir_list(char **names, int64_t count) { (void)names; (void)count; }
int fsio_chdir(const char *path) { (void)path; return 1; }
char *fsio_path_join(const char *dir, const char *name)
{
    static char buf[512];
    snprintf(buf, sizeof(buf), "%s/%s", dir, name);
    return buf;
}
int out_fill(int32_t x, int32_t y, int32_t w, int32_t h,
             uint32_t ch, int32_t fg, int32_t bg, int32_t attr)
{
    (void)x;(void)y;(void)w;(void)h;(void)ch;(void)fg;(void)bg;(void)attr;
    n_out_fill++;
    return 0;
}
int out_text(int32_t x, int32_t y, const char *s,
             int32_t fg, int32_t bg, int32_t attr)
{
    (void)x;(void)y;(void)s;(void)fg;(void)bg;(void)attr;
    n_out_text++;
    return 0;
}

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)

int main(void)
{
    void *fm = fileman_new();

    printf("=== fileman.ll: ciclo de vida ===\n");
    CHECK(fm != NULL, "fileman_new");
    if (fm == NULL) return 1;
    CHECK(strcmp(fileman_cwd(fm), ".") == 0, "cwd inicial '.'");
    CHECK(fileman_count(fm) == 0, "listado inicial vacio");

    printf("=== fileman.ll: listado ===\n");
    fileman_set_cwd(fm, "/tmp/stubdir");
    CHECK(strcmp(fileman_cwd(fm), "/tmp/stubdir") == 0, "set_cwd");
    fileman_load(fm);
    CHECK(fileman_count(fm) == 41, "41 entradas (.. + 40)");
    CHECK(strcmp(fileman_name(fm, 0), "..") == 0, "primera entrada '..'");
    CHECK(strcmp(fileman_name(fm, 1), "f00") == 0, "segunda entrada 'f00'");
    CHECK(strcmp(fileman_name(fm, 40), "f39") == 0, "ultima entrada 'f39'");

    printf("=== fileman.ll: scroll ===\n");
    fileman_set_sel(fm, 35);
    fileman_scroll(fm, 10);
    CHECK(fileman_top(fm) == 26, "seleccion 35 con 10 filas -> top 26");
    fileman_set_sel(fm, 2);
    fileman_scroll(fm, 10);
    CHECK(fileman_top(fm) == 2, "volver arriba -> seleccion en la primera fila");
    fileman_set_sel(fm, 0);
    fileman_scroll(fm, 10);
    CHECK(fileman_top(fm) == 0, "seleccion 0 -> top 0");
    fileman_set_sel(fm, 100);
    CHECK(fileman_sel(fm) == 40, "seleccion se clampa al ultimo");
    fileman_scroll(fm, 10);
    CHECK(fileman_top(fm) == 31, "top se clampa a n - rows");
    fileman_scroll(fm, 0);
    CHECK(fileman_top(fm) == 0, "rows=0 -> top 0");

    printf("=== fileman.ll: directorios y dibujo ===\n");
    fileman_set_cwd(fm, "/tmp");
    fileman_load(fm);
    CHECK(fileman_is_dir(fm, ".") == 1,
          "is_dir usa fsio_list_dir (stub devuelve exito)");
    fileman_set_sel(fm, 0);
    fileman_draw(fm, 0, 0, 40, 12);
    CHECK(n_out_fill == 1 && n_out_text > 1,
          "draw pinta fondo, cabecera y entradas");

    fileman_destroy(fm);
    printf("=== resumen ===\n");
    printf("  %d ok, %d fail\n", g_pass, g_fail);
    return g_fail > 0 ? 1 : 0;
}
