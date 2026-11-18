; core/rx_runtime.ll — sesion abregex persistente (definiciones en runtime).
;
; abregex_compile_named (macros.ll) crea y destruye un symtab por llamada:
; util para烟雾 tests, pero la consola/Fexl necesita definir macros en una
; sesion y reusarlas despues (@name::...; en un momento, %name en otro).
;
; Este modulo expone una SESION opaca:
;   abregex_session_new()          -> ptr symtab persistente
;   abregex_define_runtime(s, src, len) -> i32  (1 ok, 0 error de sintaxis)
;   abregex_compile_runtime(s, name, nlen) -> RxProgram* (o null)
;   abregex_session_destroy(s)
;
; El llamador (Fexl via shim) guarda el ptr de sesion en un value opaco.
; No hay estado global implicito: todo se pasa explicito.
;
; No usa `switch` -> no necesita -relocation-model=pic.
;
; %Symtab duplicado con el mismo layout que regex_abregex.ll.

%Symtab = type { ptr, i64, i64 }

declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @symtab_create()
declare void @symtab_destroy(ptr)
declare i32 @abregex_parse_defs(ptr, ptr, i64)
declare ptr @abregex_resolve(ptr, ptr, i64)
declare ptr @rx_compile(ptr)
declare void @rx_ast_destroy(ptr)

define ptr @abregex_session_new() {
entry:
  %s = call ptr @symtab_create()
  ret ptr %s
}

define void @abregex_session_destroy(ptr %s) {
entry:
  call void @symtab_destroy(ptr %s)
  ret void
}

; Agrega todas las definiciones de %src al symtab de la sesion.
; Devuelve 1 si parseo ok, 0 si hubo error de sintaxis.
define i32 @abregex_define_runtime(ptr %s, ptr %src, i64 %len) {
entry:
  %ok = call i32 @abregex_parse_defs(ptr %src, i64 %len, ptr %s)
  ret i32 %ok
}

; Resuelve %name contra el symtab de la sesion y compila a RxProgram*.
; null si el nombre no existe o falla la resolucion.
define ptr @abregex_compile_runtime(ptr %s, ptr %name, i64 %nlen) {
entry:
  %resolved = call ptr @abregex_resolve(ptr %s, ptr %name, i64 %nlen)
  %null = icmp eq ptr %resolved, null
  br i1 %null, label %fail, label %compile
compile:
  %prog = call ptr @rx_compile(ptr %resolved)
  call void @rx_ast_destroy(ptr %resolved)
  ret ptr %prog
fail:
  ret ptr null
}
