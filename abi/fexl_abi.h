#ifndef SWI_FEXL_ABI_H
#define SWI_FEXL_ABI_H

/*
 * Frontera C <-> IR del intérprete Fexl (Paso 1 de la migración a LLVM).
 *
 * Los módulos fexlswi/src/type_*.c que todavía están en C siguen incluyendo
 * sus headers originales (value.h, memory.h, str.h) y linkan contra los
 * símbolos que ahora definen fexl/value.ll, fexl/memory.ll y fexl/str.ll.
 * Este header es el espejo canónico de esa frontera: lo usan los arneses de
 * test en C y documenta el contrato de layout que el IR debe respetar.
 *
 * Contrato de layout (%value en fexl/value_types.ll):
 *   i64  offset  0  N / next
 *   ptr  offset  8  T / clear
 *   ptr  offset 16  L
 *   ptr  offset 24  R / v_ptr / v_double
 *   sizeof == 32
 */

#include <stdint.h>

typedef struct value *value;
typedef value (*type)(value);

struct value {
    union { uint64_t N; value next; };
    union { type T; void (*clear)(value); };
    value L;
    union { value R; void *v_ptr; double v_double; };
};

_Static_assert(sizeof(struct value) == 32, "%value debe medir 32 bytes");

/* value.ll */
extern value  new_value(void);
extern void   recycle(value f);
extern value  hold(value f);
extern void   drop(value f);
extern value  V(type T, value L, value R);
extern value  Q(type T);
extern value  A(value x, value y);
extern value  keep(value f);
extern value  tail(value f);
extern value  eval(value f);
extern value  arg(value f);
extern void   clear_free_list(void);
extern void   end_value(void);
extern uint64_t cur_steps;

/* memory.ll */
extern uint64_t cur_blocks;
extern uint64_t cur_bytes;
extern void  *new_memory(uint64_t num_bytes);
extern void  *resize_memory(void *data, uint64_t o_size, uint64_t n_size);
extern void   free_memory(void *data, uint64_t num_bytes);
extern void   end_memory(void);

/* parse.ll */
extern value cur_label;
extern value parse_top(void);

/* str.ll */
typedef struct string *string;
struct string { uint64_t len; char data[]; };

extern string str_new(uint64_t len);
extern string str_new_data(const char *data, uint64_t len);
extern string str_new_data0(const char *data);
extern string str_copy(string x);
extern void   str_free(string x);
extern string str_concat(string x, string y);
extern int    str_cmp(string x, string y);
extern int    str_eq(string x, string y);
extern string str_slice(string x, uint64_t pos, uint64_t len);
extern uint64_t str_search(string x, string y, uint64_t offset);
extern string dirname(string path);
extern string basename(string path);
extern uint64_t length_common(string x, string y);
extern unsigned char char_width(unsigned char ch);

/* dependencias C que el arnés debe proveer (no forman parte del IR) */
extern void die(const char *msg);
extern void fput(void *fh, const char *data);
extern void fput_ulong(void *fh, uint64_t x);

#endif
