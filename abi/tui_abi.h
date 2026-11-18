#ifndef TUI_ABI_H
#define TUI_ABI_H

#include <stdint.h>

/*
 * tui_abi.h — contrato C <-> IR de swi (la TUI).
 *
 * Los IR se hablan entre si con `declare`, sin header. Este header existe
 * solo en la frontera de lenguaje: lo incluye tui/main.c. Los tipos opacos
 * son punteros a structs que solo el IR conoce.
 *
 * InEvent NO se redefine aca: su layout (6 x i32, 24 bytes) vive en
 * swi/tui/in.h y se espeja en state.ll. Por eso state_step recibe
 * `void *` en esta declaracion.
 */

/* espejo de %Rect en canvas.ll */
typedef struct { int32_t x, y, w, h; } SwiRect;

/* espejo de %Action en state.ll / win_editor.ll */
typedef struct { int32_t kind; int64_t a, b, c; } SwiAction;

/* Action.kind */
enum {
    SWI_A_NONE = 0, SWI_A_MODE = 1, SWI_A_CHAR = 2, SWI_A_MOTION = 3,
    SWI_A_OP = 4, SWI_A_EDIT = 5, SWI_A_CMDLINE = 6, SWI_A_EXEC = 7,
    SWI_A_CANCEL = 8, SWI_A_QUIT = 9, SWI_A_REJECT = 10,
    SWI_A_SEARCH_NEXT = 11
};

/* --- state.ll --- */
extern void    *state_new(void);
extern void     state_free(void *st);
extern void     state_step(void *st, void *ev, int32_t editable, SwiAction *out);
extern int32_t  state_mode(void *st);
extern int32_t  state_prefix(void *st);
extern void     state_set_mode(void *st, int32_t mode);

/* --- canvas.ll / window.ll --- */
extern void    *canvas_new(void);
extern void     canvas_destroy(void *c);
extern void     canvas_set_size(void *c, int32_t w, int32_t h);
extern void     canvas_layout_panels(int32_t w, int32_t h,
                                     int32_t con_h, int32_t fm_w,
                                     SwiRect *out_tabs, SwiRect *out_buf,
                                     SwiRect *out_con, SwiRect *out_fm);
extern void     canvas_layout(int32_t w, int32_t h,
                              SwiRect *top, SwiRect *body, SwiRect *bottom);
extern void     canvas_body_rect(void *c, SwiRect *out);
extern void    *canvas_open(void *c, int32_t kind, void *data);
extern int32_t  canvas_close(void *c, void *win);
extern void     canvas_minimize(void *c, void *win);
extern void     canvas_maximize(void *c, void *win);
extern void    *canvas_active(void *c);
extern void     window_rect(void *win, SwiRect *out);

/* --- win_editor.ll --- */
extern void    *win_editor_new(const char *path);
extern void    *win_editor_new_empty(const char *path);   /* doc_new, sin archivo */
extern int32_t  win_editor_open(void *ed, const char *path);
extern void     win_editor_destroy(void *ed);
extern int32_t  win_editor_step(void *ed, SwiAction *action);
extern void     win_editor_draw(void *ed, int32_t x, int32_t y,
                                int32_t w, int32_t h);
extern int32_t  win_editor_search(void *ed, const char *pat, int64_t len,
                                  int32_t forward);
extern int32_t  win_editor_save(void *ed);
extern int32_t  win_editor_save_as(void *ed, const char *path);
extern void     win_editor_set_view(void *ed, int32_t rows, int32_t cols);
extern int64_t  win_editor_top_line(void *ed);
extern int64_t  win_editor_hscroll(void *ed);
extern void     win_editor_request_quit(void *ed);
extern void    *win_editor_doc(void *ed);
extern int64_t  win_editor_cursor(void *ed);
extern void     win_editor_set_cursor(void *ed, int64_t cursor, int64_t top);
extern void     win_editor_set_highlight(void *ed, const char *pat, int64_t len);
extern int64_t  win_editor_hl_count(void *ed);
extern int64_t  win_editor_anchor(void *ed);
extern int32_t  win_editor_visual(void *ed);
extern int32_t  win_editor_dirty(void *ed);
extern int32_t  win_editor_quit(void *ed);
extern const char *win_editor_path(void *ed);

/* --- console.ll --- */
extern void    *console_new(void);
extern void     console_destroy(void *c);
extern void     console_reset(void *c, int32_t prefix);
extern void     console_set_eval(void *c, void *eval_fn);
extern void     console_push(void *c, int64_t ch);
extern const char *console_text(void *c);
extern int64_t  console_len(void *c);
extern int32_t  console_prefix(void *c);
extern int32_t  console_execute(void *c, void *ed);
extern int32_t  console_repeat(void *c, void *ed, int32_t forward);

/* --- memory.ll (sesion: ventanas, macros, last_dir) --- */
extern void    *memory_new(void);
extern void     memory_destroy(void *m);
extern void     memory_clear(void *m);
extern int32_t  memory_add(void *m, int32_t kind, const char *path,
                           int64_t len, int64_t cursor, int64_t top);
extern int64_t  memory_find(void *m, int32_t kind, const char *path, int64_t len);
extern int64_t  memory_count(void *m, int32_t kind);
extern int32_t  memory_get(void *m, int64_t idx, char **out_path,
                           int64_t *out_cursor, int64_t *out_top, int32_t *out_kind);
extern void     memory_set_last_dir(void *m, const char *dir, int64_t len);
extern char    *memory_last_dir(void *m, int64_t *out_len);
extern int32_t  memory_save(void *m, const char *path);
extern int32_t  memory_load(void *m, const char *path);

/* --- motor del editor (para el selftest) --- */
extern void    *doc_textbuffer(void *doc);
extern char    *tb_data(void *tb);
extern int64_t  tb_length(void *tb);

#endif
