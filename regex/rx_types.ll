; rx_types.ll — tipos compartidos del motor regex.
;
; Se concatena al comienzo de CADA modulo de regex/ durante el build, de modo
; que exista UNA sola definicion de estos tipos en lugar de las 7 copias que
; habia antes (format, replace, rxprog_cache, regex_abregex, regex_compiler,
; regex_runner y rx_query). LLVM IR no tiene `include`, por eso se inyecta
; por concatenacion en las reglas del Makefile.
;
; DEBEN coincidir con la ABI usada por type_regex.c (fexlswi/src/regex_abi.h).

%RxInst    = type { i64, i64, i64 }  ; opcode, arg1, arg2
%RxProgram = type { ptr, i64, i64 }  ; instructions, count, num_groups
