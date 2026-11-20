/*
 * test_fexl_value.c — arnés del núcleo Fexl migrado a IR.
 *
 * Linkea fexl/value.ll, fexl/memory.ll y fexl/str.ll (compilados con
 * value_types.ll inyectado) contra stubs mínimos de die/fput. Verifica el
 * layout de %value, el conteo de referencias, el trampolín eval() y la API
 * de strings.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "abi/fexl_abi.h"

void die(const char *msg) {
    fprintf(stderr, "die: %s\n", msg ? msg : "");
    abort();
}
void fput(void *fh, const char *data) { (void)fh; (void)data; }
void fput_ulong(void *fh, uint64_t x) { (void)fh; (void)x; }

static int g_pass = 0, g_fail = 0;
#define CHECK(c, m) do { \
    if (c) { printf("  OK   - %s\n", m); g_pass++; } \
    else   { printf("  FAIL - %s\n", m); g_fail++; } \
} while (0)

/* Reductores de prueba. step() hace drop(f) después de llamar al tipo, así
 * que el reductor NO debe soltar f: solo tomar prestado lo que devuelve. */
static value type_done(value f) { (void)f; return 0; }
static value type_retR(value f) { return hold(f->R); }
static value type_retL(value f) { return hold(f->L); }

static int seq(string s, const char *lit) {
    return (int)s->len == (int)strlen(lit) && memcmp(s->data, lit, s->len) == 0;
}

int main(void) {
    printf("=== fexl value.ll: layout y constructores ===\n");
    value q = Q(type_done);
    CHECK(q != 0 && q->N == 1 && q->T == type_done && q->L == 0 && q->R == 0,
          "Q(T): atomo con T, L=R=0, refcount 1");
    value r = Q(type_retR);
    value app = A(q, r);
    CHECK(app->T == 0 && app->L == q && app->R == r,
          "A(x,y): aplicacion con T=0");
    CHECK(sizeof(struct value) == 32, "sizeof(struct value) == 32");

    printf("=== fexl value.ll: refcount ===\n");
    hold(q);
    CHECK(q->N == 2, "hold incrementa");
    drop(q);
    CHECK(q->N == 1, "drop decrementa");
    value k = keep(app);
    CHECK(k == app && app->T == type_done && app->N == 2,
          "keep copia el T de f->L y hace hold");
    drop(k);
    CHECK(app->N == 1, "drop tras keep restaura refcount");

    printf("=== fexl value.ll: trampolin eval ===\n");
    uint64_t before = cur_steps;
    value out = eval(A(Q(type_retR), Q(type_done)));
    CHECK(out != 0 && out->T == type_done, "eval aplica un reductor simple");
    CHECK(cur_steps == before + 1, "un paso incrementa cur_steps");
    drop(out);

    before = cur_steps;
    value nested = A(A(Q(type_retR), Q(type_retR)), Q(type_done));
    out = eval(nested);
    CHECK(out != 0 && out->T == type_done,
          "eval resuelve la aplicacion interna antes de aplicar");
    CHECK(cur_steps > before + 1, "el caso anidado hace mas de un paso");
    drop(out);

    value l = eval(A(Q(type_retL), A(Q(type_done), Q(type_done))));
    CHECK(l != 0 && l->T == type_retL, "retL devuelve el lado izquierdo");
    drop(l);

    drop(app);   /* suelta q y r */
    CHECK(cur_blocks > 0, "el allocator mantiene el free list");

    printf("=== fexl str.ll ===\n");
    string s = str_new_data0("banana");
    string p1 = str_new_data0("ba"), p2 = str_new_data0("nana");
    string t = str_concat(p1, p2);
    CHECK(seq(s, "banana") && seq(t, "banana"), "str_new_data0 / str_concat");
    CHECK(str_eq(s, t) == 1 && str_cmp(s, t) == 0, "str_eq / str_cmp");
    string other = str_new_data0("banano");
    CHECK(str_cmp(s, other) < 0, "str_cmp ordena");
    string slice = str_slice(s, 2, 3);
    CHECK(seq(slice, "nan"), "str_slice");
    string needle = str_new_data0("nan"), absent = str_new_data0("xyz");
    CHECK(str_search(s, needle, 0) == 2, "str_search");
    CHECK(str_search(s, absent, 0) == 6, "str_search sin match");
    string path = str_new_data0("/a/b/c");
    string d = dirname(path), b = basename(path);
    CHECK(seq(d, "/a/b"), "dirname");
    CHECK(seq(b, "c"), "basename");
    CHECK(length_common(s, t) == 6, "length_common");
    CHECK(char_width(0xE2) == 3 && char_width('a') == 1, "char_width UTF-8");

    /* liberar todo para que end_value() no reporte fuga */
    str_free(s); str_free(t); str_free(p1); str_free(p2);
    str_free(other); str_free(slice); str_free(needle);
    str_free(absent); str_free(path); str_free(d); str_free(b);

    printf("=== resumen ===\n  %d ok, %d fail\n", g_pass, g_fail);
    end_value();   /* falla con die("LEAK") si queda algo */
    return g_fail > 0 ? 1 : 0;
}
