#ifndef SWI_FEXL_UI_H
#define SWI_FEXL_UI_H

#include <stdint.h>

/* Puente con el driver Fexl persistente (ui.fxl).
 * El motor guarda el estado; Fexl decide layout y atajos. */

#define FUI_MAX_BINDS 12
#define FUI_KEY_LEN  16
#define FUI_ACT_LEN  32
#define FUI_STATUS_LEN 64
#define FUI_LOG_LEN 256

typedef struct {
    int32_t console_h;   /* 0 = off, 3 = brief, 10 = extended */
    int32_t tabs_col;    /* 0 = expandido, 1 = colapsado */
    int32_t fileman_w;   /* 0 = off, >0 = ancho del panel */
    char status[FUI_STATUS_LEN];
    char log[FUI_LOG_LEN];
    char err[128];      /* ultimo error del script, p. ej. Undefined symbol */
    struct { char key[FUI_KEY_LEN]; char act[FUI_ACT_LEN]; } bind[FUI_MAX_BINDS];
    int32_t nbind;
} UiFrame;

/* Codigos de evento (primer byte del paquete de 4). */
enum {
    FUI_INIT = 'i', FUI_CONSOLE = '2', FUI_FILEMAN = '3',
    FUI_TABS = '4', FUI_MODE = 'm', FUI_COMMAND = 'c',
    FUI_TABCHG = 't', FUI_QUIT = 'q', FUI_EVAL = 'x'
};

int  fexl_ui_start(const char *fexl_bin, const char *script);
void fexl_ui_event(int ev, int a, int b, int c, UiFrame *out);
void fexl_ui_stop(void);
int  fexl_ui_alive(void);

#endif
