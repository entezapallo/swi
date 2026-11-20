/*
 * eval.c — puente de la consola al intérprete Fexl.
 *
 * SWI_FEXL_BIN se define en el Makefile con la ruta ABSOLUTA al binario.
 *
 * El script de sesión se ACUMULA: cada línea que escribe el usuario se
 * agrega al archivo y se re-evalúa el script COMPLETO. Así las definiciones
 * (\mi_fn=...) sobreviven a los comandos siguientes, algo que no pasaba
 * cuando cada línea corría en un batch aislado.
 */

#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "eval.h"

#ifndef SWI_FEXL_BIN
#define SWI_FEXL_BIN "fexlswi-llvm/bin/fexlswi0"
#endif

#define SWI_EVAL_SESSION_FMT "/tmp/swi_fexl_session_%d.fxl"
#define SWI_EVAL_OUT_FMT     "/tmp/swi_eval_%d.out"
#define SWI_EVAL_PATH_MAX    128
#define SWI_EVAL_OUT_MAX     4096

#define SWI_EVAL_PRELOAD \
    "load_basic\nload_output\nload_cmp\nload_file\nload_str\n" \
    "load_extend\nload_regex\nload_script\nevaluate \\;\n"

static char g_session[SWI_EVAL_PATH_MAX];
static char g_out[SWI_EVAL_PATH_MAX];
static char g_eval_output[SWI_EVAL_OUT_MAX];
static int g_ready = 0;

static void paths_init(void)
{
    snprintf(g_session, sizeof(g_session), SWI_EVAL_SESSION_FMT, (int)getpid());
    snprintf(g_out, sizeof(g_out), SWI_EVAL_OUT_FMT, (int)getpid());
}

const char *swi_eval_output(void)
{
    return g_eval_output;
}

void swi_eval_reset(void)
{
    if (!g_ready) paths_init();
    remove(g_session);
    g_ready = 0;
    g_eval_output[0] = '\0';
}

int swi_eval(const char *line, int64_t len)
{
    FILE *f, *ofd;
    pid_t pid;
    int status = -1;

    if (line == NULL || len < 0) return -1;
    if (!g_ready) paths_init();

    g_eval_output[0] = '\0';

    /* crear el script de sesion con los preloads la primera vez */
    f = fopen(g_session, "a+b");
    if (f == NULL) return -1;
    fseek(f, 0, SEEK_END);              /* "a+b" arranca en 0 aunque tenga datos */
    if (ftell(f) == 0) fwrite(SWI_EVAL_PRELOAD, 1, strlen(SWI_EVAL_PRELOAD), f);
    fwrite(line, 1, (size_t)len, f);
    fwrite("\n", 1, 1, f);
    fclose(f);
    g_ready = 1;

    /* fork/exec directo: sin shell, sin system() */
    pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        int fd = open(g_out, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0) _exit(127);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        close(fd);
        execl(SWI_FEXL_BIN, SWI_FEXL_BIN, g_session, (char *)NULL);
        _exit(127);
    }
    waitpid(pid, &status, 0);

    ofd = fopen(g_out, "rb");
    if (ofd != NULL) {
        size_t n = fread(g_eval_output, 1, sizeof(g_eval_output) - 1, ofd);
        g_eval_output[n] = '\0';
        fclose(ofd);
    }
    remove(g_out);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 1 : 0;
}
