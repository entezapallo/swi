/*
 * shell_globals.c — definiciones de los globals que shell.ll declara extern.
 * Los provee main.c en el binario real; aca se definen para los arneses que
 * linkean shell.o sin main.o (test_win_editor).
 */
#include <stdint.h>
#include <time.h>
#include "../abi/tui_abi.h"

UiFrame g_ui;
void   *g_tabs[16];
int     g_tab_focus[16];
int     g_ntabs = 0, g_active = 0;
int     g_focus = 0;
char    g_clog[24][200];
int     g_clog_n = 0;
char    g_cmd[256];
int     g_cmd_len = 0;
char    g_last_pattern[256];
char    g_eval_msg[512];
int     g_fm_rows = 0;
void   *g_fileman = NULL;
time_t  g_script_mtime = 0;
long    g_script_mtime_ns = 0;
