/* test_fexl_ui.c — prueba el driver Fexl persistente y el parser de frames. */

#include <stdio.h>
#include <string.h>
#include "tui/fexl_ui.h"

#ifndef SWI_FEXL_BIN
#define SWI_FEXL_BIN "fexlswi-llvm/bin/fexlswi0"
#endif

static int g_pass = 0, g_fail = 0;

#define CHECK(c, m) do { \
    if (c) { printf("  OK   - %s\n", m); g_pass++; } \
    else   { printf("  FAIL - %s\n", m); g_fail++; } \
} while (0)

int main(void)
{
    UiFrame f;

    printf("=== fexl_ui: driver persistente ===\n");
    CHECK(fexl_ui_start(SWI_FEXL_BIN, "ui.fxl") == 1,
          "arranca el driver Fexl");
    CHECK(fexl_ui_alive() == 1, "proceso vivo");

    fexl_ui_event(FUI_INIT, 3, 0, 0, &f);
    CHECK(f.console_h == 3 && f.tabs_col == 0 && f.fileman_w == 0,
          "frame INIT con layout por defecto");
    printf("  [dbg] nbind=%d key=[%s] act=[%s]\n",
           f.nbind, f.nbind ? f.bind[0].key : "", f.nbind ? f.bind[0].act : "");
    CHECK(f.nbind >= 1 && strcmp(f.bind[0].act, "console.toggle") == 0,
          "frame trae BIND desde Fexl");

    fexl_ui_event(FUI_CONSOLE, 3, 0, 0, &f);
    CHECK(f.console_h == 10, "F2: brief -> extended");
    fexl_ui_event(FUI_CONSOLE, 10, 0, 0, &f);
    CHECK(f.console_h == 0, "F2: extended -> off");
    fexl_ui_event(FUI_CONSOLE, 0, 0, 0, &f);
    CHECK(f.console_h == 3, "F2: off -> brief");

    fexl_ui_event(FUI_FILEMAN, 3, 0, 0, &f);
    CHECK(f.fileman_w == 40, "F3: abre file manager");
    fexl_ui_event(FUI_TABS, 3, 0, 0, &f);
    CHECK(f.tabs_col == 1, "F4: colapsa tabs");

    fexl_ui_event(FUI_MODE, 1, 0, 0, &f);
    CHECK(strcmp(f.status, "INSERT") == 0, "Fexl reporta modo INSERT");

    fexl_ui_event(FUI_QUIT, 3, 1, 40, &f);
    fexl_ui_stop();
    CHECK(fexl_ui_alive() == 0, "driver detenido");

    printf("=== fexl_ui: script con error ===\n");
    {
        FILE *bad = fopen("/tmp/swi_bad_ui.fxl", "wb");
        if (bad != NULL) {
            fputs("say \"sin preloads\"\n", bad);
            fclose(bad);
            CHECK(fexl_ui_start(SWI_FEXL_BIN, "/tmp/swi_bad_ui.fxl") == 1,
                  "arranca script con error");
            fexl_ui_event(FUI_INIT, 3, 0, 0, &f);
            CHECK(f.err[0] != '\0' && strstr(f.err, "Undefined") != NULL,
                  "error del script capturado en el frame");
            CHECK(f.console_h == 3, "layout por defecto tras error");
            fexl_ui_stop();
            remove("/tmp/swi_bad_ui.fxl");
        }
    }

    printf("=== resumen ===\n  %d ok, %d fail\n", g_pass, g_fail);
    return g_fail > 0 ? 1 : 0;
}
