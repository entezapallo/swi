#ifndef REGEX_ABI_H
#define REGEX_ABI_H

/*
 * regex_abi.h — puente C <-> IR (el "shim") entre Fexl y el motor de regex.
 *
 * Es la unica declaration de las funciones del motor que ve Fexl. El motor
 * es LLVM IR puro (archivos .ll de regex-test/regex) y no sabe que Fexl existe; aca solo
 * se declaran las firmas. Se linkean via bitcode:
 *
 *   fexl.bc + type_regex.bc + regex.bc -> fexl_regex.bc -> fexl-regex
 *
 * Tipos opacos del motor:
 *   void*  RxProgram*   (programa compilado, dueño: rx_program_destroy)
 *   void*  sesion abregex (symtab persistente, dueño: abregex_session_destroy)
 */

/* regex_compiler.ll */
extern void *regex_compile(const char *pattern, long len);
extern void  rx_program_destroy(void *prog);

/* regex_runner.ll */
extern long  regex_match_end(const char *pattern, long plen,
                             const char *text, long tlen);

/* rx_query.ll */
extern long  rx_search_any(void *prog, const char *text, long tlen,
                           long from, int forward);
extern long  rx_count(void *prog, const char *text, long tlen);
extern long  rx_spans(void *prog, const char *text, long tlen,
                      long *out_starts, long *out_ends, long max);

/* rx_runtime.ll (sesion abregex persistente) */
extern void *abregex_session_new(void);
extern void  abregex_session_destroy(void *s);
extern int   abregex_define_runtime(void *s, const char *src, long len);
extern void *abregex_compile_runtime(void *s, const char *name, long nlen);

#endif
