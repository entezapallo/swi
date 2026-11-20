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
#define SWI_FEXL_BIN "fexlswi-llvm/bin/fexlswi0"
#endif
#ifndef SWI_UI_SCRIPT
#define SWI_UI_SCRIPT "ui.fxl"
#endif

/* Ruta del script de UI: SWI_UI la puede overridear sin recompilar. Se
 * resuelve una sola vez para que el hot reload vigile siempre el mismo
 * archivo. */
static const char *ui_script_path(void) {
    static const char *path;
    if (path == NULL) {
        const char *env = getenv("SWI_UI");
        path = (env != NULL && *env != '\0') ? env : SWI_UI_SCRIPT;
    }
    return path;
}

#define SWI_SESSION_DIR  "/tmp/swi"
#define SWI_SESSION_PATH "/tmp/swi/session"
#define SWI_KIND_EDITOR  69
#define SWI_KIND_ACTIVE  65   /* 'A': indice del tab activo */
#define SWI_KIND_LAYOUT  76   /* 'L': console_h,tabs_col,fileman_w */

#define MAX_TABS 16
#define MAX_NAMES 160
#define MAX_LOG 24
#define MAX_CWD 512
#define SWI_FMT_FILE "/tmp/swi_fmt_input.txt"
#define SWI_FORMATS_TMP_FMT "/tmp/swi_ui_%d.fxl"
#define SWI_UI_PATH_MAX 512

/* Formatos del usuario: $XDG_CONFIG_HOME/swi/formats.fxl o
 * $HOME/.config/swi/formats.fxl. Se incluyen en el script que recibe el
 * driver, justo despues de `evaluate \;` de ui.fxl, para que sus
 * definiciones esten en scope antes del loop. */
static const char *swi_formats_path(void) {
    static char path[SWI_UI_PATH_MAX];
    const char *xdg = getenv("XDG_CONFIG_HOME");
    const char *home = getenv("HOME");
    if (xdg != NULL && *xdg != '\0')
        snprintf(path, sizeof(path), "%s/swi/formats.fxl", xdg);
    else if (home != NULL && *home != '\0')
        snprintf(path, sizeof(path), "%s/.config/swi/formats.fxl", home);
    else
        path[0] = '\0';
    return path;
}

static const char *ui_script_effective(void) {
    const char *base = ui_script_path();
    static char tmp[SWI_UI_PATH_MAX];
    struct stat sb;
    const char *fmt = swi_formats_path();
    FILE *in, *extra, *out;
    char line[1024];
    int inserted = 0;

    if (fmt[0] == '\0' || stat(fmt, &sb) != 0) return base;

    snprintf(tmp, sizeof(tmp), SWI_FORMATS_TMP_FMT, (int)getpid());
    in = fopen(base, "r");
    if (in == NULL) return base;
    extra = fopen(fmt, "r");
    if (extra == NULL) { fclose(in); return base; }
    out = fopen(tmp, "w");
    if (out == NULL) { fclose(in); fclose(extra); return base; }

    while (fgets(line, sizeof(line), in) != NULL) {
        fputs(line, out);
        if (!inserted && strstr(line, "evaluate \\;") != NULL) {
            char l2[1024];
            while (fgets(l2, sizeof(l2), extra) != NULL) fputs(l2, out);
            fputc('\n', out);
            inserted = 1;
        }
    }
    fclose(in);
    fclose(extra);
    fclose(out);
    return inserted ? tmp : base;
}

extern int32_t fsio_ensure_dir(const char *path);
extern int32_t fsio_chdir(const char *path);
extern int32_t fsio_list_dir(const char *path, char ***out_names, int64_t *out_count);
extern void fsio_free_dir_list(char **names, int64_t count);
extern char *fsio_path_join(const char *dir, const char *name);

int g_pass = 0, g_fail = 0;
char g_eval_msg[512];
char g_last_pattern[256];

/* estado de la UI (Fexl decide los tres primeros campos) */
UiFrame g_ui;
void *g_tabs[MAX_TABS];
int g_tab_focus[MAX_TABS];
int g_ntabs = 0, g_active = 0;
time_t g_script_mtime = 0;
long g_script_mtime_ns = 0;
void *g_fileman = NULL;   /* dueño del cwd/listado/scroll (fileman.ll) */
int g_fm_rows = 0;        /* filas visibles, calculadas en draw() */
char g_clog[MAX_LOG][200];
int g_clog_n = 0;
char g_cmd[256];
int g_cmd_len = 0;
int g_focus = 0;   /* 0=buffer, 1=consola, 2=file manager */

#define SELF_CHECK(cond, msg) do { \
    if (cond) { printf("  OK   - %s\n", msg); g_pass++; } \
    else      { printf("  FAIL - %s\n", msg); g_fail++; } \
} while (0)


static void usage(const char *prog)
{
    fprintf(stderr, "uso: %s [archivo]\n", prog);
    fprintf(stderr, "  F2 consola  F3 archivos  F4 tabs\n");
    fprintf(stderr, "  Ctrl+T tab nueva  Ctrl+W cerrar  Ctrl+Q salir\n");
}


/* Envia un evento al driver y aplica el frame. Fexl puede agregar una linea
 * de LOG; el motor agrega la salida real de los comandos. */

/* El foco vive por tab: al cambiar de tab se recupera el del otro buffer. */

/* Un BIND solo existe si Fexl lo emitio en el ultimo frame. Si el driver
 * no esta disponible (nbind==0) se usa el mapping historico por robustez. */

/* Sesion: un solo dueno (C). Fexl solo transforma el estado que le pasamos;
 * el estado persistente (tabs, cursor, foco, layout, cwd) se guarda aca. */





/* Pide al driver Fexl los spans de sintaxis del buffer activo y los aplica.
 * El texto viaja por archivo: ui.fxl lo lee con fgetc y corre regex.spans. */

/* Cambia el working directory del proceso. path==NULL significa "usar el
 * directorio que muestra el file manager" (:swd sin argumento). Toda la
 * validacion, el chdir y el refresh del listado viven en fileman.ll. */

/* Entradas de console.ll (no static: el IR las declara con declare). */
int swi_set_wd(const char *path)
{
    return shell_wd_apply(path, 0);
}

int swi_print_wd(void)
{
    char abs[MAX_CWD];
    char msg[sizeof(abs) + 8];
    if (getcwd(abs, sizeof(abs)) == NULL) return 0;
    snprintf(msg, sizeof(msg), "wd: %s", abs);
    shell_log_add(msg);
    return 1;
}




/* --- dibujo de los paneles --- */




/* Despacha una accion al editor activo. Devuelve 1 si pidio quit. */





int main(int argc, char **argv)
{
    const char *filename = NULL;
    int quit = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(argv[0]);
            return 0;
        }
        else if (filename == NULL) filename = argv[i];
    }
    if (tb_init() != TB_OK) { fprintf(stderr, "tb_init fallo\n"); return 1; }
    out_init();

    /* driver Fexl persistente: dueño del layout y de los atajos */
    memset(&g_ui, 0, sizeof(g_ui));
    g_ui.console_h = 3;
    if (!fexl_ui_start(SWI_FEXL_BIN, ui_script_effective()))
        fprintf(stderr, "swi: driver Fexl no disponible; layout por defecto\n");
    else
        shell_ui_sync(FUI_INIT, 3, 0, 0);
    {
        struct stat sb;
        if (stat(ui_script_path(), &sb) == 0) {
            g_script_mtime = sb.st_mtime;
            g_script_mtime_ns = sb.st_mtim.tv_nsec;
        }
    }
    swi_eval_set_bin(SWI_FEXL_BIN);
    swi_eval_reset();     /* session Fexl de consola nueva por proceso */

    g_fileman = fileman_new();
    if (g_fileman == NULL) return 1;

    void *st = state_new();
    void *canvas = canvas_new();
    void *console = console_new();
    if (!st || !canvas || !console) return 1;
    if (filename == NULL) {
        shell_session_load();          /* restaura tabs, cursor, foco, layout, cwd */
        if (g_ntabs == 0) shell_tab_new(NULL);
    } else {
        shell_tab_new(filename);
    }
    void *ed = g_tabs[g_active];
    canvas_set_size(canvas, tb_width(), tb_height());
    void *win = canvas_open(canvas, 0, ed);
    console_set_eval(console, swi_eval);
    if (win == NULL) return 1;
    shell_fmt_send(ed);     /* resaltado inicial del archivo abierto */

    while (!quit && win_editor_quit(ed) == 0) {
        InEvent ev;
        int rc;

        /* hot reload del script Fexl: el estado lo tiene C, asi que
         * reiniciar el driver no pierde nada del editor. */
        {
            struct stat sb;
            int changed = 0;
            if (stat(ui_script_path(), &sb) == 0) {
                changed = (sb.st_mtime != g_script_mtime ||
                           sb.st_mtim.tv_nsec != g_script_mtime_ns);
                g_script_mtime = sb.st_mtime;
                g_script_mtime_ns = sb.st_mtim.tv_nsec;
            }
            if (changed) {
                fexl_ui_stop();
                if (fexl_ui_start(SWI_FEXL_BIN, ui_script_effective())) {
                    shell_ui_sync(FUI_INIT, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
                    shell_log_add("ui.fxl recargado");
                }
            }
        }

        shell_draw(canvas, ed, console, st);
        rc = in_poll(&ev, 100);
        if (rc == IN_ERROR) break;
        if (rc == IN_TIMEOUT) continue;
        if (ev.type == IN_EV_RESIZE) {
            canvas_set_size(canvas, ev.w, ev.h);
            canvas_maximize(canvas, win);
            shell_ui_sync(FUI_MODE, state_mode(st), 0, 0);
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
            if (console_key && shell_has_bind("console.toggle")) { shell_toggle_console(); continue; }
            if (fileman_key && shell_has_bind("fileman.toggle")) { shell_toggle_fileman(); continue; }
            if (tabs_key && shell_has_bind("tabs.collapse")) { shell_toggle_tabs(); continue; }
            if (ctrl && ch == 't' && shell_has_bind("tab.new")) { shell_tab_new(NULL); continue; }
            if (ctrl && ch == 'w' && shell_has_bind("tab.close")) {
                shell_tab_close(); ed = g_tabs[g_active]; continue;
            }
            if (ctrl && ch == 'n' && shell_has_bind("tab.next")) {
                g_active = (g_active + 1) % g_ntabs;
                shell_set_focus(g_tab_focus[g_active]);
                ed = g_tabs[g_active];
                shell_ui_sync(FUI_TABCHG, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
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
                shell_log_add(g_cmd);
                /* el evento pasa por el driver: Fexl decide STATUS/LOG */
                shell_ui_sync(FUI_EVAL, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
                if (swi_eval(g_cmd, g_cmd_len) && swi_eval_output()[0])
                    shell_log_add(swi_eval_output());
                g_cmd_len = 0; g_cmd[0] = '\0';
            } else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_ESC) {
                shell_set_focus(0); g_cmd_len = 0; g_cmd[0] = '\0';
            }
            continue;
        }

        /* --- file manager --- */
        if (g_focus == 2) {
            int64_t sel = fileman_sel(g_fileman);
            int64_t page = g_fm_rows > 1 ? (int64_t)(g_fm_rows - 1) : 1;
            int fctrl = (ev.type == IN_EV_CHAR && (ev.mods & IN_MOD_CTRL)) ? 1 : 0;
            if ((ev.type == IN_EV_KEY && ev.key == IN_KEY_DOWN) ||
                (ev.type == IN_EV_CHAR && ev.ch == 'j')) {
                fileman_set_sel(g_fileman, sel + 1);
            } else if ((ev.type == IN_EV_KEY && ev.key == IN_KEY_UP) ||
                       (ev.type == IN_EV_CHAR && ev.ch == 'k')) {
                fileman_set_sel(g_fileman, sel - 1);
            } else if ((ev.type == IN_EV_KEY && ev.key == IN_KEY_PGDN) ||
                       (fctrl && ev.ch == 'd')) {
                fileman_set_sel(g_fileman, sel + page);
            } else if ((ev.type == IN_EV_KEY && ev.key == IN_KEY_PGUP) ||
                       (fctrl && ev.ch == 'u')) {
                fileman_set_sel(g_fileman, sel - page);
            } else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_HOME) {
                fileman_set_sel(g_fileman, 0);
            } else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_END) {
                fileman_set_sel(g_fileman, fileman_count(g_fileman) - 1);
            } else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_ENTER) {
                shell_fileman_open(0);
                ed = g_tabs[g_active];
            } else if (ev.type == IN_EV_CHAR && ev.ch == 't') {
                shell_fileman_open(1);
                ed = g_tabs[g_active];
            } else if ((ev.type == IN_EV_KEY && ev.key == IN_KEY_BACKSPACE) ||
                       (ev.type == IN_EV_CHAR && ev.ch == 'h')) {
                fileman_parent(g_fileman);
            } else if (ev.type == IN_EV_KEY && ev.key == IN_KEY_ESC) {
                shell_set_focus(0);
            }
            continue;
        }

        /* --- edicion normal: state.ll -> win_editor --- */
        {
            SwiAction a = {0};
            state_step(st, &ev, 1, &a);
            if (shell_dispatch(st, console, ed, &a)) quit = 1;
        }
    }

    /* sesion: C es el unico dueno; se graba antes de destruir los editors */
    shell_session_save();
    shell_ui_sync(FUI_QUIT, g_ui.console_h, g_ui.tabs_col, g_ui.fileman_w);
    fexl_ui_stop();
    console_destroy(console);
    canvas_destroy(canvas);
    for (int i = 0; i < g_ntabs; i++) win_editor_destroy(g_tabs[i]);
    state_free(st);
    fileman_destroy(g_fileman);
    g_fileman = NULL;
    tb_shutdown();
    return 0;
}
