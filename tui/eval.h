#ifndef TUI_EVAL_H
#define TUI_EVAL_H

/*
 * eval.h — puente de la consola al intérprete Fexl (batch, externo a la TUI).
 *
 * La consola (console.ll) no contiene el intérprete: solo llama a este
 * callback con la línea escrita. Aca se escribe la línea a un archivo temporal
 * y se invoca `fexlswi0`, que es el mismo interprete que corre los scripts
 * batch (spec seccion 8: "console solo llama al intérprete").
 *
 * El path del binario se puede fijar en compilacion con
 * -DSWI_FEXL_BIN="..." (por defecto fexlswi-llvm/bin/fexlswi0).
 */

#include <stdint.h>

/* Fija la ruta absoluta al binario (llamado al arrancar desde main.c). */
void swi_eval_set_bin(const char *bin);

/* Firma del callback que registra console_set_eval(). */
int swi_eval(const char *line, int64_t len);

/* Ultima salida del interprete (para la barra de estado; "" si no hay). */
const char *swi_eval_output(void);

/* Borra el script de sesion (llamado al arrancar). */
void swi_eval_reset(void);

#endif
