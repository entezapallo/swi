/*
 * test_memory.c — tests del modulo memory.ll (motor de la TUI).
 *
 * Sesion: ventanas con ruta/cursor, macros, ultimo directorio, y
 * persistencia save/load. Sin termbox, sin core/.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* stubs de fsio (memory usa fsio para save/load) */
int fsio_write_file(const char *path, const void *data, long len) {
    FILE *f = fopen(path, "wb");
    if (!f) return 0;
    size_t w = fwrite(data, 1, (size_t)len, f);
    fclose(f);
    return w == (size_t)len ? 1 : 0;
}
int fsio_read_file(const char *path, char **out, long *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *b = malloc(n > 0 ? (size_t)n : 1);
    size_t r = fread(b, 1, (size_t)n, f);
    fclose(f);
    if ((long)r != n) { free(b); return 0; }
    *out = b; *out_len = n;
    return 1;
}
void fsio_free_buffer(void *d) { free(d); }

extern void   *memory_new(void);
extern void    memory_destroy(void *m);
extern void    memory_clear(void *m);
extern int     memory_add(void *m, int32_t kind, const char *path, int64_t len,
                          int64_t cursor, int64_t top);
extern int64_t memory_find(void *m, int32_t kind, const char *path, int64_t len);
extern int64_t memory_count(void *m, int32_t kind);
extern int     memory_get(void *m, int64_t idx, char **out_path,
                          int64_t *out_cursor, int64_t *out_top, int32_t *out_kind);
extern void    memory_set_last_dir(void *m, const char *dir, int64_t len);
extern char   *memory_last_dir(void *m, int64_t *out_len);
extern int     memory_save(void *m, const char *path);
extern int     memory_load(void *m, const char *path);

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)

int main(void)
{
    void *m = memory_new();
    char *path;
    int64_t cursor, top, len;
    int32_t kind;

    CHECK(m != NULL, "memory_new");
    if (m == NULL) return 1;

    printf("=== memory.ll: entradas ===\n");
    CHECK(memory_add(m, 'E', "/tmp/foo.txt", 12, 5, 2) == 1, "add ventana 1");
    CHECK(memory_add(m, 'E', "/tmp/bar.txt", 12, 9, 4) == 1, "add ventana 2");
    CHECK(memory_add(m, 'M', "@digit::[0-9];", 14, 0, 0) == 1, "add macro");
    CHECK(memory_count(m, 'E') == 2, "count ventanas = 2");
    CHECK(memory_count(m, 'M') == 1, "count macros = 1");

    CHECK(memory_find(m, 'E', "/tmp/bar.txt", 12) == 1, "find ventana 2");
    CHECK(memory_find(m, 'M', "@digit::[0-9];", 14) == 2, "find macro");
    CHECK(memory_find(m, 'E', "/no/existe", 10) == -1, "find inexistente -> -1");

    CHECK(memory_get(m, 0, &path, &cursor, &top, &kind) == 1 &&
          strcmp(path, "/tmp/foo.txt") == 0 && cursor == 5 && top == 2 && kind == 'E',
          "get ventana 1 con cursor/top/kind");
    CHECK(memory_get(m, 99, &path, &cursor, &top, &kind) == 0,
          "get fuera de rango -> 0");

    printf("=== memory.ll: last_dir ===\n");
    memory_set_last_dir(m, "/home/user", 10);
    {
        char *d = memory_last_dir(m, &len);
        CHECK(d != NULL && len == 10 && strncmp(d, "/home/user", 10) == 0,
              "set/get last_dir");
    }

    printf("=== memory.ll: save / load (round-trip) ===\n");
    {
        const char *sp = "test_session.mem";
        void *m2 = memory_new();
        CHECK(memory_save(m, sp) == 1, "memory_save");
        CHECK(memory_load(m2, sp) == 1, "memory_load");
        CHECK(memory_count(m2, 'E') == 2 && memory_count(m2, 'M') == 1,
              "load restaura entradas");
        CHECK(memory_find(m2, 'E', "/tmp/bar.txt", 12) == 1,
              "load restaura ruta");
        CHECK(memory_get(m2, 0, &path, &cursor, &top, &kind) == 1 &&
              cursor == 5 && top == 2,
              "load restaura cursor/top");
        {
            char *d = memory_last_dir(m2, &len);
            CHECK(d != NULL && len == 10, "load restaura last_dir");
        }
        memory_destroy(m2);
        remove(sp);
    }

    printf("=== memory.ll: clear ===\n");
    memory_clear(m);
    CHECK(memory_count(m, 'E') == 0 && memory_count(m, 'M') == 0,
          "clear deja count=0");

    memory_destroy(m);
    printf("=== resumen ===\n");
    printf("  %d ok, %d fail\n", g_pass, g_fail);
    return g_fail > 0 ? 1 : 0;
}
