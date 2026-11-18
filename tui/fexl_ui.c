/* fexl_ui.c — proceso Fexl persistente que decide layout y atajos. */
#define _POSIX_C_SOURCE 200809L

#include <signal.h>
#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#include "fexl_ui.h"

static pid_t g_pid = -1;
static FILE *g_in = NULL;   /* hacia stdin de Fexl */
static FILE *g_out = NULL;  /* desde stdout de Fexl */
static char g_bin[512], g_script[512];

int fexl_ui_alive(void)
{
    return g_pid > 0;
}

int fexl_ui_start(const char *fexl_bin, const char *script)
{
    int to[2], from[2];

    if (fexl_bin == NULL || script == NULL) return 0;
    signal(SIGPIPE, SIG_IGN);
    strncpy(g_bin, fexl_bin, sizeof(g_bin) - 1); g_bin[sizeof(g_bin) - 1] = '\0';
    strncpy(g_script, script, sizeof(g_script) - 1); g_script[sizeof(g_script) - 1] = '\0';
    if (pipe(to) != 0) return 0;
    if (pipe(from) != 0) { close(to[0]); close(to[1]); return 0; }

    g_pid = fork();
    if (g_pid < 0) {
        close(to[0]); close(to[1]); close(from[0]); close(from[1]);
        g_pid = -1;
        return 0;
    }
    if (g_pid == 0) {
        dup2(to[0], STDIN_FILENO);
        dup2(from[1], STDOUT_FILENO);
        dup2(from[1], STDERR_FILENO);
        close(to[0]); close(to[1]); close(from[0]); close(from[1]);
        execl(fexl_bin, fexl_bin, script, (char *)NULL);
        _exit(127);
    }

    close(to[0]); close(from[1]);
    g_in = fdopen(to[1], "wb");
    g_out = fdopen(from[0], "rb");
    if (g_in == NULL || g_out == NULL) {
        fexl_ui_stop();
        return 0;
    }
    setvbuf(g_in, NULL, _IONBF, 0);
    return 1;
}

void fexl_ui_stop(void)
{
    if (g_pid > 0) {
        fclose(g_in);
        kill(g_pid, SIGTERM);
        waitpid(g_pid, NULL, 0);
        g_pid = -1;
    }
    if (g_out) { fclose(g_out); g_out = NULL; }
    g_in = NULL;
}

void fexl_ui_event(int ev, int a, int b, int c, UiFrame *out)
{
    unsigned char pkt[4];
    char line[512], errbuf[128];
    static UiFrame last_good;
    static int has_good = 0;
    int attempt;

    if (out == NULL) return;
    errbuf[0] = '\0';

    /* loop acotado: como maximo un reinicio del driver. Nada de recursión. */
    for (attempt = 0; attempt < 2; attempt++) {
        int ok = 1, got_dot = 0;

        memset(out, 0, sizeof(*out));
        out->console_h = 3;
        out->tabs_col = 0;
        out->fileman_w = 0;

        pkt[0] = (unsigned char)ev;
        pkt[1] = (unsigned char)(a & 0xff);
        pkt[2] = (unsigned char)(b & 0xff);
        pkt[3] = (unsigned char)(c & 0xff);

        if (g_pid <= 0 || g_in == NULL || g_out == NULL) ok = 0;
        if (ok && fwrite(pkt, 1, 4, g_in) != 4) ok = 0;
        if (ok && fflush(g_in) != 0) ok = 0;

        if (ok) {
            /* frame hasta "."; capturamos errores del script */
            while (fgets(line, sizeof(line), g_out) != NULL) {
                if (getenv("FUI_DBG")) fprintf(stderr, "[fui] [%s]\n", line);
                if (line[0] == '.' && (line[1] == '\n' || line[1] == '\0')) {
                    got_dot = 1;
                    break;
                }
                if (strncmp(line, "Undefined symbol", 16) == 0 ||
                    strstr(line, "syntax error") != NULL) {
                    strncpy(errbuf, line, sizeof(errbuf) - 1);
                    errbuf[sizeof(errbuf) - 1] = '\0';
                    continue;
                }
                if (sscanf(line, "CONSOLE_H %d", &out->console_h) == 1) continue;
                if (sscanf(line, "TABS_COL %d", &out->tabs_col) == 1) continue;
                if (sscanf(line, "FILEMAN_W %d", &out->fileman_w) == 1) continue;
                if (sscanf(line, "STATUS %63s", out->status) == 1) continue;
                if (sscanf(line, "LOG %255s", out->log) == 1) continue;
                if (strncmp(line, "BIND ", 5) == 0 && out->nbind < FUI_MAX_BINDS) {
                    if (sscanf(line + 5, "%15s %31s",
                               out->bind[out->nbind].key,
                               out->bind[out->nbind].act) == 2)
                        out->nbind++;
                }
            }
            if (!got_dot) ok = 0;
        }

        if (ok) {
            last_good = *out;
            has_good = 1;
            return;
        }

        if (errbuf[0] && !out->err[0])
            strncpy(out->err, errbuf, sizeof(out->err) - 1);

        if (attempt == 0) {
            /* ante un frame roto conservamos el ultimo bueno: el editor no
             * cambia de layout por un error de sintaxis en ui.fxl */
            if (has_good) {
                UiFrame good = last_good;
                strncpy(good.err, errbuf, sizeof(good.err) - 1);
                *out = good;
            }
            fexl_ui_stop();
            if (g_bin[0] == '\0' || !fexl_ui_start(g_bin, g_script))
                return;
        }
    }
}
