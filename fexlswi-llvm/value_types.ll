; fexl/value_types.ll — tipos compartidos del intérprete Fexl.
;
; Se inyecta por concatenación al compilar cada módulo IR (LLVM IR no tiene
; `include`), igual que regex/rx_types.ll. No se compila como módulo suelto.
;
; %value es el espejo exacto de `struct value` (fexlswi-llvm/src/value.h):
;
;   union { unsigned long N; value next; };            offset  0, 8 bytes
;   union { type T; void (*clear)(value); };           offset  8, 8 bytes
;   value L;                                          offset 16, 8 bytes
;   union { value R; void *v_ptr; double v_double; };  offset 24, 8 bytes
;
; sizeof(struct value) == 32. El campo T es un puntero a función
; `value (*)(value)`; en IR es un `ptr` opaco y se llama con
; `load ptr` + `call ptr %T(ptr %f)`. Las comparaciones `x->T == type_num`
; del C son parte de la semántica: por eso el link usa --icf=safe.

%value = type { i64, ptr, ptr, ptr }
