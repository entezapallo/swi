#ifndef SWI_FEXL_UI_H
#define SWI_FEXL_UI_H

/* Puente con el driver Fexl persistente (ui.fxl).
 * El motor guarda el estado; Fexl decide layout y atajos.
 *
 * El driver paso a ser tui/fexl_ui.ll: UiFrame y las funciones viven en el
 * espejo de ABI. Este header se conserva por compatibilidad con test_fexl_ui.c
 * y con los includes existentes.
 */
#include "../abi/tui_abi.h"

#endif
