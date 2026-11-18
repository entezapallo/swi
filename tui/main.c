/*
 * main.c — swi, la TUI. Tiene TB_IMPL: aca vive la implementacion de termbox.
 *
 * Arquitectura event-driven (Fase 2):
 *   - el driver Fexl persistente (ui.fxl) decide layout y atajos;
 *   - el motor IR guarda los Document y ejecuta cada tecla de edicion;
 *   - main.c es el pegamento: eventos -> Fexl -> comandos -> draw.
 *
 * Layout: [búfer] / [barra de tabs] / [consola] / [barra de estado].
 */

#define TB_IMPL
#include "termbox2.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>

#include "in.h"
#include "out.h"
#include "eval.h"
#include "fexl_ui.h"
#include "../abi/tui_abi.h"

#ifndef SWI_FEXL_BIN
#define SWI_FEXL_BIN "fexlswi/bin/fexlswi0"
#endif
#ifndef SWI_UI_SCRIPT
#define SWI_UI_SCRIPT "ui.fxl"
#endif

#define SWI_SESSION_DIR  "/tmp/swi"
#define SWI_SESSION_PATH "/tmp/swi/session"
#define SWI_KIND_EDITOR  69
#define SWI_KIND_ACTIVE  65   /* 'A': indice del tab activo */
#define SWI_KIND_LAYOUT  76   /* 'L': console_h,tabs_col,fileman_w */

#define MAX_TABS 16
#define MAX_NAMES 160
#define MAX_LOG 24
#define MAX_CWD 512

extern int32_t fsio_ensure_dir(const char *path);
extern int32_t fsio_list_dir(const char *path, char ***out_names, int64_t *out_count);
extern void fsio_free_dir_list(char **names, int64_t count);
extern char *fsio_path_join(const char *dir, const char *name);

static int g_pass = 0, g_fail = 0;
static char g_eval_msg[512];
static char g_last_pattern[256];

/* estado de la UI (Fexl decide los tres primeros campos) */
static UiFrame g_ui;
static void *g_tabs[MAX_TABS];
static int g_tab_focus[MAX_TABS];
static int g_ntabs = 0, g_active = 0;
static time_t g_script_mtime = 0;
static long g_script_mtime_ns = 0;
static char g_fm_cwd[MAX_CWD] = ".";
static char g_fm_names[MAX_NAMES][160];
static int g_fm_n = 0, g_fm_sel = 0;
static char g_clog[MAX_LOG][200];
static int g_clog_n = 0;
static char g_cmd[256];
static int g_cmd_len = 0;
static int g_focus = 0;   /* 0=buffer, 1=consola, 2=file manager */

#define SELF_CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)

static void tab_new(const char *path);
static void fileman_load(void);

static void usage(const char *prog)
{
    fprintf(stderr, "uso: %s [--selftest] [archivo]\n", prog);
    fprintf(stderr, "  F2 consola  F3 archivos  F4 tabs\n");
    fprintf(stderr, "  Ctrl+T tab nueva  Ctrl+W cerrar  Ctrl+Q salir\n");
}

static void log_add(const char *s)
{
    int i;
    if (s == NULL || s[0] == '\0') return;
    if (g_clog_n == MAX_LOG) {
        for (i = 1; i < MAX_LOG; i++)
            memcpy(g_clog[i - 1], g_clog[i], sizeof(g_clog[0]));
        g_clog_n--;
    }
    strncpy(g_clog[g_clog_n], s, sizeof(g_clog[0]) - 1);
    g_clog[g_clog_n][sizeof(g_clog[0]) - 1] = '\0';
    g_clog_n++;
}

/* Envia un evento al driver y aplica el frame. Fexl puede agregar una linea
 * de LOG; el motor agrega la salida real de los comandos. */
static void ui_sync(int ev, int a, int b, int c)
{
    fexl_ui_event(ev, a, b, c, &g_ui);
    if (g_ui.err[0]) {
        log_add(g_ui.err);
        g_ui.err[0] = '\0';
    }
    if (g_ui.log[0] && strcmp(g_ui.log, "CMD") != 0)
        log_add(g_ui.log);
}

/* El foco vive por tab: al cambiar de tab se recupera el del otro buffer. */
static void set_focus(int f)
{
    g_focus = f;
    if (g_active >= 0 && g_active < MAX_TABS) g_tab_focus[g_active] = f;
}

/* Un BIND solo existe si Fexl lo emitio en el ultimo frame. Si el driver
 * no esta disponible (nbind==0) se usa el mapping historico por robustez. */
static int has_bind(const char *act)
{
    int i;
    if (g_ui.nbind == 0) return 1;
    for (i = 0; i < g_ui.nbind; i++)
        if (strcmp(g_ui.bind[i].act, act) == 0) return 1;
    return 0;
}

/* Sesion: un solo dueno (C). Fexl solo transforma el estado que le pasamos;
 * el estado persistente (tabs, cursor, foco, layout, cwd) se guarda aca. */
static void session_save_all(void)
{
    void *m = memory_new();
    char buf[128];
    int i;

    if (m == NULL) return;
    fsio_ensure_dir(SWI_SESSION_DIR);
    for (i = 0; i < g_ntabs; i++) {
        const char *p = win_editor_path(g_tabs[i]);
        memory_add(m, SWI_KIND_EDITOR, p ? p : "",
                   p ? (int64_t)strlen(p) : 0,
                   win_editor_cursor(g_tabs[i]), g_tab_focus[i]);
    }
    snprintf(buf, sizeof(buf), "%d", g_active);
    memory_add(m, SWI_KIND_ACTIVE, buf, (int64_t)strlen(buf), 0, 0);
    snprintf(buf, sizeof(buf), "%d,%d,%d",
             g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
    memory_add(m, SWI_KIND_LAYOUT, buf, (int64_t)strlen(buf), 0, 0);
    memory_set_last_dir(m, g_fm_cwd, (int64_t)strlen(g_fm_cwd));
    memory_save(m, SWI_SESSION_PATH);
    memory_destroy(m);
}

static void session_load_all(void)
{
    void *m = memory_new();
    char *dir;
    int64_t dlen = 0;
    int i;

    if (m == NULL) return;
    memory_load(m, SWI_SESSION_PATH);

    for (i = 0; i < 256; i++) {
        char *p = NULL;
        int64_t cur = 0, top = 0;
        int32_t kind = 0;
        if (memory_get(m, i, &p, &cur, &top, &kind) != 1) break;
        if (p == NULL) continue;
        if (kind == SWI_KIND_EDITOR && g_ntabs < MAX_TABS) {
            tab_new(p[0] ? p : NULL);
            if (g_ntabs > 0) {
                win_editor_set_cursor(g_tabs[g_ntabs - 1], cur, 0);
                g_tab_focus[g_ntabs - 1] = (int)top;
            }
        } else if (kind == SWI_KIND_ACTIVE) {
            int a = atoi(p);
            if (a >= 0 && a < g_ntabs) g_active = a;
        } else if (kind == SWI_KIND_LAYOUT) {
            int ch = 3, tc = 0, fw = 0;
            if (sscanf(p, "%d,%d,%d", &ch, &tc, &fw) == 3) {
                g_ui.console_h = ch;
                g_ui.tabs_col = tc;
                g_ui.fileman_w = fw;
            }
        }
    }
    dir = memory_last_dir(m, &dlen);
    if (dir != NULL && dlen > 0) {
        strncpy(g_fm_cwd, dir, sizeof(g_fm_cwd) - 1);
        g_fm_cwd[sizeof(g_fm_cwd) - 1] = '\0';
    }
    /* Siempre arrancar en el buffer: si la sesion anterior terminó con
     * consola o file manager abiertos, las flechas irian a ese panel y
     * pareceria que el editor no responde. */
    g_focus = 0;
    for (int i = 0; i < MAX_TABS; i++) g_tab_focus[i] = 0;
    fileman_load();
    memory_destroy(m);
}

static void toggle_console(void)
{
    if (g_ui.console_h > 0) set_focus(0);
    ui_sync(FUI_CONSOLE, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
    if (g_ui.console_h > 0) set_focus(1);
}

static void toggle_fileman(void)
{
    if (g_ui.fileman_w > 0) set_focus(0);
    ui_sync(FUI_FILEMAN, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
    if (g_ui.fileman_w > 0) { fileman_load(); set_focus(2); }
}

static void toggle_tabs(void)
{
    ui_sync(FUI_TABS, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
}

static void fileman_load(void)
{
    char **names = NULL;
    int64_t n = 0, i;
    int count = 0;

    /* fsio_list_dir excluye '.' y '..': agregamos '..' como primera
     * entrada para poder subir de directorio con Enter. */
    strcpy(g_fm_names[0], "..");
    count = 1;

    if (fsio_list_dir(g_fm_cwd, &names, &n) != 1 || names == NULL) {
        g_fm_n = count;
        return;
    }
    for (i = 0; i < n && count < MAX_NAMES; i++) {
        strncpy(g_fm_names[count], names[i], sizeof(g_fm_names[0]) - 1);
        g_fm_names[count][sizeof(g_fm_names[0]) - 1] = '\0';
        count++;
    }
    fsio_free_dir_list(names, n);
    g_fm_n = count;
    if (g_fm_sel >= g_fm_n) g_fm_sel = g_fm_n > 0 ? g_fm_n - 1 : 0;
    if (g_fm_sel < 0) g_fm_sel = 0;
}

static void tab_new(const char *path)
{
    void *ed;
    char untitled[128];
    static int counter = 0;

    if (g_ntabs >= MAX_TABS) return;
    if (path == NULL) {
        /* ruta unica por proceso/tab: nunca truncamos el /tmp compartido
         * al crear un buffer nuevo (antes dos swi se pisaban el archivo). */
        snprintf(untitled, sizeof(untitled), "/tmp/swi_untitled_%d_%d.txt",
                 (int)getpid(), counter++);
        ed = win_editor_new_empty(untitled);
    } else {
        ed = win_editor_new(path);
    }
    if (ed == NULL) return;
    g_tabs[g_ntabs] = ed;
    g_tab_focus[g_ntabs] = 0;
    g_ntabs++;
    g_active = g_ntabs - 1;
    g_focus = 0;
    ui_sync(FUI_TABCHG, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
}

static void tab_close(void)
{
    int i;
    if (g_ntabs <= 1) return;
    win_editor_destroy(g_tabs[g_active]);
    for (i = g_active; i < g_ntabs - 1; i++) {
        g_tabs[i] = g_tabs[i + 1];
        g_tab_focus[i] = g_tab_focus[i + 1];
    }
    g_ntabs--;
    if (g_active >= g_ntabs) g_active = g_ntabs - 1;
    g_focus = g_tab_focus[g_active];
    ui_sync(FUI_TABCHG, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
}

static void fileman_parent(void);   /* adelanto: lo usa fileman_open */

static void fileman_open(int new_tab)
{
    char *full;
    struct stat st;
    char buf[512];

    if (g_fm_n <= 0) return;
    if (strcmp(g_fm_names[g_fm_sel], "..") == 0) {
        fileman_parent();
        return;
    }
    full = fsio_path_join(g_fm_cwd, g_fm_names[g_fm_sel]);
    if (full == NULL) return;
    if (stat(full, &st) == 0 && S_ISDIR(st.st_mode)) {
        strncpy(g_fm_cwd, full, sizeof(g_fm_cwd) - 1);
        g_fm_cwd[sizeof(g_fm_cwd) - 1] = '\0';
        g_fm_sel = 0;
        fileman_load();
    } else {
        snprintf(buf, sizeof(buf), "open %s", full);
        log_add(buf);
        if (new_tab) tab_new(full);
        else {
            if (win_editor_open(g_tabs[g_active], full) == 0) {
                snprintf(buf, sizeof(buf), "no puedo abrir %s", full);
                log_add(buf);
            }
        }
        set_focus(0);
    }
    free(full);
}

static void fileman_parent(void)
{
    char *p;

    /* si el cwd es relativo (p.ej. "."), lo resolvemos antes de quitar
     * el ultimo componente; si no, ".." nos llevaria a "/" directo. */
    if (g_fm_cwd[0] != '/') {
        char abs[MAX_CWD];
        if (getcwd(abs, sizeof(abs)) != NULL) {
            if (strcmp(g_fm_cwd, ".") == 0 || g_fm_cwd[0] == '\0')
                strncpy(g_fm_cwd, abs, sizeof(g_fm_cwd) - 1);
            else
                snprintf(g_fm_cwd, sizeof(g_fm_cwd), "%s/%s", abs, g_fm_cwd);
            g_fm_cwd[sizeof(g_fm_cwd) - 1] = '\0';
        }
    }
    p = strrchr(g_fm_cwd, '/');
    if (p == NULL || p == g_fm_cwd) {
        strcpy(g_fm_cwd, "/");
    } else {
        *p = '\0';
    }
    g_fm_sel = 0;
    fileman_load();
}

/* --- dibujo de los paneles --- */

static void draw_tabs(SwiRect r)
{
    int i;
    int x = r.x + 1;
    char buf[160];

    if (r.h <= 0) return;
    out_fill(r.x, r.y, r.w, r.h, ' ', OUT_WHITE, OUT_BLUE, OUT_ATTR_NONE);

    if (g_ui.tabs_col) {
        const char *p = win_editor_path(g_tabs[g_active]);
        snprintf(buf, sizeof(buf), "[%d/%d] %s", g_active + 1, g_ntabs,
                 p ? p : "untitled");
        out_text(x, r.y, buf, OUT_BRIGHT_WHITE, OUT_BLUE, OUT_ATTR_BOLD);
        return;
    }

    for (i = 0; i < g_ntabs && x < r.x + r.w - 4; i++) {
        const char *p = win_editor_path(g_tabs[i]);
        const char *name = p ? strrchr(p, '/') : NULL;
        name = name ? name + 1 : (p ? p : "untitled");
        snprintf(buf, sizeof(buf), "[%d]%s%s ", i + 1, name,
                 win_editor_dirty(g_tabs[i]) ? "+" : "");
        if ((int)strlen(buf) > r.x + r.w - x) break;
        out_text(x, r.y, buf,
                 i == g_active ? OUT_BRIGHT_YELLOW : OUT_WHITE,
                 i == g_active ? OUT_BLUE : OUT_BLUE,
                 i == g_active ? OUT_ATTR_BOLD : OUT_ATTR_NONE);
        x += (int)strlen(buf);
    }
}

static void draw_console(SwiRect r)
{
    int i, first, y, x;
    char hdr[200];

    if (r.h <= 0) return;
    out_fill(r.x, r.y, r.w, r.h, ' ', OUT_WHITE, OUT_BLACK, OUT_ATTR_NONE);

    /* borde visible: sin el, la consola parece parte del buffer */
    snprintf(hdr, sizeof(hdr), "[consola] %s",
             g_focus == 1 ? "F2/F3/F4  Ctrl+T tab" : "F2 extiende  F3 archivos");
    hdr[r.w > 1 ? r.w - 1 : 0] = '\0';
    out_text(r.x + 1, r.y, hdr, OUT_BRIGHT_BLUE, OUT_BLACK, OUT_ATTR_BOLD);

    if (g_clog_n > 0) {
        first = g_clog_n - (r.h - 1);
        if (first < 0) first = 0;
        y = r.y + 1;
        for (i = first; i < g_clog_n && y < r.y + r.h; i++, y++)
            out_text(r.x + 1, y, g_clog[i],
                     OUT_BRIGHT_CYAN, OUT_BLACK, OUT_ATTR_NONE);
    } else if (r.h > 1) {
        out_text(r.x + 1, r.y + 1, "(sin salida)  escribe una expresion Fexl con F2",
                 OUT_WHITE, OUT_BLACK, OUT_ATTR_NONE);
    }
    /* borde inferior */
    for (x = r.x; x < r.x + r.w - 1; x++)
        out_cell(x, r.y + r.h - 1, '-', OUT_BLUE, OUT_BLACK, OUT_ATTR_NONE);
    if (g_focus == 1) {
        char prompt[300];
        snprintf(prompt, sizeof(prompt), "> %s", g_cmd);
        out_text(r.x + 1, r.y + r.h - 1, prompt,
                 OUT_BRIGHT_WHITE, OUT_BLACK, OUT_ATTR_BOLD);
    }
}

static void draw_fileman(SwiRect r)
{
    int i, y;
    char buf[200];

    if (r.h <= 0 || r.w <= 0) return;
    out_fill(r.x, r.y, r.w, r.h, ' ', OUT_WHITE, OUT_BLACK, OUT_ATTR_NONE);
    snprintf(buf, sizeof(buf), "[files] %s", g_fm_cwd);
    buf[r.w - 1] = '\0';
    out_text(r.x, r.y, buf, OUT_BRIGHT_CYAN, OUT_BLACK, OUT_ATTR_BOLD);
    for (i = 0; i < g_fm_n && i + 1 < r.h; i++) {
        y = r.y + 1 + i;
        snprintf(buf, sizeof(buf), " %s", g_fm_names[i]);
        buf[r.w - 1] = '\0';
        out_text(r.x, y, buf,
                 i == g_fm_sel ? OUT_BRIGHT_YELLOW : OUT_WHITE,
                 i == g_fm_sel ? OUT_BLUE : OUT_BLACK,
                 i == g_fm_sel ? OUT_ATTR_BOLD : OUT_ATTR_NONE);
    }
}

/* Despacha una accion al editor activo. Devuelve 1 si pidio quit. */
static int dispatch(void *st, void *console, void *ed, SwiAction *a)
{
    int flags;

    switch (a->kind) {
    case SWI_A_MODE:
        if (a->a == 3) console_reset(console, (int32_t)a->b);
        ui_sync(FUI_MODE, state_mode(st), 0, 0);
        break;
    case SWI_A_CMDLINE:
        console_push(console, a->a);
        break;
    case SWI_A_EXEC: {
        int32_t prefix = console_prefix(console);
        const char *txt = console_text(console);
        if (prefix == 47) {
            win_editor_set_highlight(ed, txt, (int64_t)strlen(txt));
            strncpy(g_last_pattern, txt, sizeof(g_last_pattern) - 1);
            g_last_pattern[sizeof(g_last_pattern) - 1] = '\0';
        }
        console_execute(console, ed);
        if (prefix != 47) {
            const char *o = swi_eval_output();
            strncpy(g_eval_msg, o ? o : "", sizeof(g_eval_msg) - 1);
            g_eval_msg[sizeof(g_eval_msg) - 1] = '\0';
            if (o && o[0]) log_add(o);
        }
        ui_sync(FUI_COMMAND, 0, 0, 0);
        console_reset(console, 0);
        break;
    }
    case SWI_A_SEARCH_NEXT:
        console_repeat(console, ed, a->a != 0 ? 1 : 0);
        win_editor_set_highlight(ed, console_text(console),
                                 (int64_t)strlen(console_text(console)));
        break;
    default:
        break;
    }
    flags = win_editor_step(ed, a);
    if (flags & 4) state_set_mode(st, 1);
    if ((flags & 1) && g_last_pattern[0] != '\0')
        win_editor_set_highlight(ed, g_last_pattern,
                                 (int64_t)strlen(g_last_pattern));
    return flags & 2;
}

static void draw(void *canvas, void *ed, void *console, void *st,
                 const char *filename)
{
    SwiRect top, body, bottom, tabs_r, buf_r, con_r, fm_r;
    int32_t w = out_width(), h = out_height();
    char buf[160];
    int n;

    (void)filename;
    canvas_set_size(canvas, w, h);
    canvas_layout(w, h, &top, &body, &bottom);
    out_clear();

    if (top.h > 0) {
        out_fill(top.x, top.y, top.w, top.h,
                 ' ', OUT_WHITE, OUT_BLUE, OUT_ATTR_BOLD);
        out_text(top.x + 1, top.y, "swi",
                 OUT_BRIGHT_WHITE, OUT_BLUE, OUT_ATTR_BOLD);
    }

    /* Toda la geometria de paneles vive en canvas.ll; main.c solo dibuja. */
    (void)body;
    canvas_layout_panels(w, h, g_ui.console_h, g_ui.fileman_w,
                         &tabs_r, &buf_r, &con_r, &fm_r);
    draw_tabs(tabs_r);
    if (fm_r.w > 0) draw_fileman(fm_r);

    {
        void *win = canvas_active(canvas);
        if (win != NULL) {
            SwiRect r;
            window_rect(win, &r);
            win_editor_draw(ed, buf_r.x, buf_r.y, buf_r.w, buf_r.h);
        }
    }
    draw_console(con_r);

    if (bottom.h > 0) {
        const char *ct = console_text(console);
        int32_t prefix = console_prefix(console);
        if (prefix != 0) {
            n = snprintf(buf, sizeof(buf), "%c%s", (char)prefix, ct);
        } else {
            static const char *modes[] = { "NORMAL", "INSERT", "VISUAL", "COMMAND" };
            int32_t m = state_mode(st);
            const char *hint = (m == 0) ? "  i=insert  :w=save  :q=quit"
                             : (m == 1) ? "  ESC=normal" : "";
            n = snprintf(buf, sizeof(buf), "-- %s --%s  %dx%d%s  fexl:%s",
                         (m >= 0 && m < 4) ? modes[m] : "?",
                         win_editor_dirty(ed) ? " [+]" : "",
                         (int)w, (int)h, (w >= 70 ? hint : ""), g_ui.status);
        }
        if (n > 0) {
            if ((size_t)n >= sizeof(buf)) n = (int)sizeof(buf) - 1;
            out_text(bottom.x, bottom.y, buf,
                     OUT_BRIGHT_WHITE, OUT_BLACK, OUT_ATTR_NONE);
        }
    }

    out_cursor(-1, -1);
    out_present();
}

/* --- selftest (mismo flujo, sin termbox) --- */

static void send_event(void *st, void *console, void *ed,
                       int32_t type, int32_t key, uint32_t ch, int32_t mods)
{
    InEvent ev = {0};
    SwiAction a = {0};
    ev.type = type; ev.key = key; ev.ch = ch; ev.mods = mods;
    state_step(st, &ev, 1, &a);
    (void)dispatch(st, console, ed, &a);
}

static int selftest(void)
{
    const char *path = "/tmp/swi_selftest.txt";
    FILE *f = fopen(path, "wb");
    void *st, *canvas, *ed, *console;
    char *data;
    int64_t len;

    if (f == NULL) return 1;
    fwrite("hola\nmundo\n", 1, 11, f);
    fclose(f);
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
        ui_sync(FUI_INIT, 3, 0, 0);
        SELF_CHECK(g_ui.nbind > 0 && strcmp(g_ui.bind[0].act, "console.toggle") == 0,
                   "driver Fexl responde con BIND desde ui.fxl");
        ui_sync(FUI_CONSOLE, 3, 0, 0);
        SELF_CHECK(g_ui.console_h == 10, "driver aplica toggle de consola");
        fexl_ui_stop();
    } else {
        SELF_CHECK(0, "driver Fexl no disponible");
    }
    SELF_CHECK(win_editor_cursor(ed) == 0, "cursor inicial 0");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'i', 0);
    SELF_CHECK(state_mode(st) == 1, "i entra a INSERT");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'X', 0);
    data = tb_data(doc_textbuffer(win_editor_doc(ed)));
    len = tb_length(doc_textbuffer(win_editor_doc(ed)));
    SELF_CHECK(len == 12 && data[0] == 'X', "INSERT 'X' al principio");
    send_event(st, console, ed, IN_EV_KEY, IN_KEY_ESC, 0, 0);
    SELF_CHECK(state_mode(st) == 0, "Esc vuelve a NORMAL");
    send_event(st, console, ed, IN_EV_CHAR, 0, '0', 0);
    SELF_CHECK(win_editor_cursor(ed) == 0, "0 -> inicio de linea");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'x', 0);
    data = tb_data(doc_textbuffer(win_editor_doc(ed)));
    SELF_CHECK(data[0] == 'h', "x borra el caracter bajo el cursor");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'u', 0);
    data = tb_data(doc_textbuffer(win_editor_doc(ed)));
    SELF_CHECK(data[0] == 'X', "u deshace la borradura");
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
    len = tb_length(doc_textbuffer(win_editor_doc(ed)));
    SELF_CHECK(len == 6, "dd borra la linea 'mundo' (quedan 6 bytes)");
    send_event(st, console, ed, IN_EV_CHAR, 0, 'p', 0);
    len = tb_length(doc_textbuffer(win_editor_doc(ed)));
    SELF_CHECK(len == 12, "p restaura la linea desde el registro");
    printf("  %d ok, %d fail\n", g_pass, g_fail);
    console_destroy(console); canvas_destroy(canvas);
    win_editor_destroy(ed); state_free(st); remove(path);
    return g_fail > 0 ? 1 : 0;
}

int main(int argc, char **argv)
{
    const char *filename = NULL;
    int do_selftest = 0;
    int quit = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "--selftest") == 0) do_selftest = 1;
        else if (filename == NULL) filename = argv[i];
    }
    if (do_selftest) return selftest();
    if (tb_init() != TB_OK) { fprintf(stderr, "tb_init fallo\n"); return 1; }
    out_init();

    /* driver Fexl persistente: dueño del layout y de los atajos */
    memset(&g_ui, 0, sizeof(g_ui));
    g_ui.console_h = 3;
    if (!fexl_ui_start(SWI_FEXL_BIN, SWI_UI_SCRIPT))
        fprintf(stderr, "swi: driver Fexl no disponible; layout por defecto\n");
    else
        ui_sync(FUI_INIT, 3, 0, 0);
    {
        struct stat sb;
        if (stat(SWI_UI_SCRIPT, &sb) == 0) {
            g_script_mtime = sb.st_mtime;
            g_script_mtime_ns = sb.st_mtim.tv_nsec;
        }
    }
    swi_eval_reset();     /* session Fexl de consola nueva por proceso */

    void *st = state_new();
    void *canvas = canvas_new();
    void *console = console_new();
    if (!st || !canvas || !console) return 1;
    if (filename == NULL) {
        session_load_all();          /* restaura tabs, cursor, foco, layout, cwd */
        if (g_ntabs == 0) tab_new(NULL);
    } else {
        tab_new(filename);
    }
    void *ed = g_tabs[g_active];
    canvas_set_size(canvas, tb_width(), tb_height());
    void *win = canvas_open(canvas, 0, ed);
    console_set_eval(console, swi_eval);
    if (win == NULL) return 1;

    while (!quit && win_editor_quit(ed) == 0) {
        InEvent ev;
        int rc;

        /* hot reload del script Fexl: el estado lo tiene C, asi que
         * reiniciar el driver no pierde nada del editor. */
        {
            struct stat sb;
            int changed = 0;
            if (stat(SWI_UI_SCRIPT, &sb) == 0) {
                changed = (sb.st_mtime != g_script_mtime ||
                           sb.st_mtim.tv_nsec != g_script_mtime_ns);
                g_script_mtime = sb.st_mtime;
                g_script_mtime_ns = sb.st_mtim.tv_nsec;
            }
            if (changed) {
                fexl_ui_stop();
                if (fexl_ui_start(SWI_FEXL_BIN, SWI_UI_SCRIPT)) {
                    ui_sync(FUI_INIT, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
                    log_add("ui.fxl recargado");
                }
            }
        }

        draw(canvas, ed, console, st, filename);
        rc = in_poll(&ev, 100);
        if (rc == IN_ERROR) break;
        if (rc == IN_TIMEOUT) continue;
        if (ev.type == IN_EV_RESIZE) {
            canvas_set_size(canvas, ev.w, ev.h);
            canvas_maximize(canvas, win);
            ui_sync(FUI_MODE, state_mode(st), 0, 0);
            continue;
        }
        if (ev.type != IN_EV_KEY && ev.type != IN_EV_CHAR) continue;

        /* --- teclas estructurales --- */
        /* El nombre de la accion viene de los BIND de ui.fxl: si Fexl no
         * emitio ese BIND, la tecla no hace nada. F2/F3/F4 chocan con el
         * escritorio; Ctrl+E/F/B son las alternativas que siempre llegan. */
        {
            int ctrl = (ev.type == IN_EV_CHAR && (ev.mods & IN_MOD_CTRL)) ? 1 : 0;
            int ch = ctrl ? (int)ev.ch : -1;
            int console_key = (ch == 'e') || (ev.type == IN_EV_KEY && ev.key == IN_KEY_F2);
            int fileman_key = (ch == 'f') || (ev.type == IN_EV_KEY && ev.key == IN_KEY_F3);
            int tabs_key    = (ch == 'b') || (ev.type == IN_EV_KEY && ev.key == IN_KEY_F4);

            /* Ctrl+Q / F10 salen desde cualquier foco (antes se ignoraban
             * cuando la consola o el file manager tenian el control). */
            if ((ctrl && ch == 'q') ||
                (ev.type == IN_EV_KEY && ev.key == IN_KEY_F10)) {
                quit = 1;
                continue;
            }
            if (console_key && has_bind("console.toggle")) { toggle_console(); continue; }
            if (fileman_key && has_bind("fileman.toggle")) { toggle_fileman(); continue; }
            if (tabs_key && has_bind("tabs.collapse")) { toggle_tabs(); continue; }
            if (ctrl && ch == 't' && has_bind("tab.new")) { tab_new(NULL); continue; }
            if (ctrl && ch == 'w' && has_bind("tab.close")) {
                tab_close(); ed = g_tabs[g_active]; continue;
            }
            if (ctrl && ch == 'n' && has_bind("tab.next")) {
                g_active = (g_active + 1) % g_ntabs;
                set_focus(g_tab_focus[g_active]);
                ed = g_tabs[g_active];
                ui_sync(FUI_TABCHG, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
                continue;
            }
        }

        /* --- consola: entrada local, evaluacion Fexl en Enter --- */
        if (g_focus == 1) {
            if (ev.type == IN_EV_CHAR && ev.ch >= 32 && g_cmd_len < 250)
                g_cmd[g_cmd_len++] = (char)ev.ch;
            else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_BACKSPACE && g_cmd_len > 0)
                g_cmd_len--;
            else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_ENTER) {
                g_cmd[g_cmd_len] = '\0';
                log_add(g_cmd);
                /* el evento pasa por el driver: Fexl decide STATUS/LOG */
                ui_sync(FUI_EVAL, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
                if (swi_eval(g_cmd, g_cmd_len) && swi_eval_output()[0])
                    log_add(swi_eval_output());
                g_cmd_len = 0; g_cmd[0] = '\0';
            } else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_ESC) {
                set_focus(0); g_cmd_len = 0; g_cmd[0] = '\0';
            }
            continue;
        }

        /* --- file manager --- */
        if (g_focus == 2) {
            if ((ev.type == IN_EV_KEY && ev.key == IN_KEY_DOWN) ||
                (ev.type == IN_EV_CHAR && ev.ch == 'j')) {
                if (g_fm_sel + 1 < g_fm_n) g_fm_sel++;
            } else if ((ev.type == IN_EV_KEY && ev.key == IN_KEY_UP) ||
                       (ev.type == IN_EV_CHAR && ev.ch == 'k')) {
                if (g_fm_sel > 0) g_fm_sel--;
            } else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_ENTER) {
                fileman_open(0);
                ed = g_tabs[g_active];
            } else if (ev.type == IN_EV_CHAR && ev.ch == 't') {
                fileman_open(1);
                ed = g_tabs[g_active];
            } else if ((ev.type == IN_EV_KEY && ev.key == IN_KEY_BACKSPACE) ||
                       (ev.type == IN_EV_CHAR && ev.ch == 'h')) {
                fileman_parent();
            } else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_ESC) {
                set_focus(0);
            }
            continue;
        }

        /* --- edicion normal: state.ll -> win_editor --- */
        {
            SwiAction a = {0};
            state_step(st, &ev, 1, &a);
            if (dispatch(st, console, ed, &a)) quit = 1;
        }
    }

    /* sesion: C es el unico dueno; se graba antes de destruir los editors */
    session_save_all();
    ui_sync(FUI_QUIT, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
    fexl_ui_stop();
    console_destroy(console);
    canvas_destroy(canvas);
    for (int i = 0; i < g_ntabs; i++) win_editor_destroy(g_tabs[i]);
    state_free(st);
    tb_shutdown();
    return 0;
}
