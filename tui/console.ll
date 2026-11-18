; console.ll — linea de comandos de swi (prefijo ':' o '/').
;
; Guarda el texto que el usuario escribe y lo interpreta. No contiene un
; intérprete: el gancho para Fexl queda marcado (console_execute solo
; reconoce built-ins por ahora). La repeticion de busqueda (n/N) usa el
; ultimo patron, guardado aca.
;
; No usa `switch` -> no necesita -relocation-model=pic.
;
; %Console = { i32 prefix, ptr buf, i64 len, i64 cap,
;              ptr lastpat, i64 lastlen, ptr eval }   ; 56 bytes
;
; `eval` es un puntero a funcion (i32 (ptr, i64))* del intérprete externo
; (Fexl batch). console NO contiene el intérprete: solo lo llama. Si es
; null, los comandos desconocidos se ignoran (comportamiento anterior).

%Console = type { i32, ptr, i64, i64, ptr, i64, ptr }

declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i32 @strcmp(ptr, ptr)
declare i32 @win_editor_save(ptr)
declare i32 @win_editor_save_as(ptr, ptr)
declare i32 @win_editor_open(ptr, ptr)
declare ptr @win_editor_path(ptr)
declare void @win_editor_request_quit(ptr)
declare i32 @win_editor_search(ptr, ptr, i64, i32)

@CMD_W  = private constant [2 x i8] c"w\00"
@CMD_Q  = private constant [2 x i8] c"q\00"
@CMD_QB = private constant [3 x i8] c"q!\00"
@CMD_WQ = private constant [3 x i8] c"wq\00"
@CMD_E  = private constant [2 x i8] c"e\00"

define ptr @console_new() {
entry:
  %c = call ptr @malloc(i64 56)
  %cn = icmp eq ptr %c, null
  br i1 %cn, label %fail, label %buf
fail:
  ret ptr null
buf:
  %b = call ptr @malloc(i64 256)
  %bn = icmp eq ptr %b, null
  br i1 %bn, label %fail_buf, label %init
fail_buf:
  call void @free(ptr %c)
  ret ptr null
init:
  %pp = getelementptr inbounds %Console, ptr %c, i32 0, i32 0
  store i32 0, ptr %pp
  %bp = getelementptr inbounds %Console, ptr %c, i32 0, i32 1
  store ptr %b, ptr %bp
  %lp = getelementptr inbounds %Console, ptr %c, i32 0, i32 2
  store i64 0, ptr %lp
  %cap = getelementptr inbounds %Console, ptr %c, i32 0, i32 3
  store i64 256, ptr %cap
  %lastp = getelementptr inbounds %Console, ptr %c, i32 0, i32 4
  store ptr null, ptr %lastp
  %lastl = getelementptr inbounds %Console, ptr %c, i32 0, i32 5
  store i64 0, ptr %lastl
  %evalp = getelementptr inbounds %Console, ptr %c, i32 0, i32 6
  store ptr null, ptr %evalp
  store i8 0, ptr %b
  ret ptr %c
}

; Registra el callback del intérprete externo (Fexl batch).
define void @console_set_eval(ptr %c, ptr %eval) {
entry:
  %p = getelementptr inbounds %Console, ptr %c, i32 0, i32 6
  store ptr %eval, ptr %p
  ret void
}

define void @console_destroy(ptr %c) {
entry:
  %bp = getelementptr inbounds %Console, ptr %c, i32 0, i32 1
  %b = load ptr, ptr %bp
  call void @free(ptr %b)
  %lp = getelementptr inbounds %Console, ptr %c, i32 0, i32 4
  %last = load ptr, ptr %lp
  %has = icmp ne ptr %last, null
  br i1 %has, label %free_last, label %free_c
free_last:
  call void @free(ptr %last)
  br label %free_c
free_c:
  call void @free(ptr %c)
  ret void
}

define void @console_reset(ptr %c, i32 %prefix) {
entry:
  %pp = getelementptr inbounds %Console, ptr %c, i32 0, i32 0
  store i32 %prefix, ptr %pp
  %lp = getelementptr inbounds %Console, ptr %c, i32 0, i32 2
  store i64 0, ptr %lp
  %bp = getelementptr inbounds %Console, ptr %c, i32 0, i32 1
  %b = load ptr, ptr %bp
  store i8 0, ptr %b
  ret void
}

define i32 @console_prefix(ptr %c) {
entry:
  %p = getelementptr inbounds %Console, ptr %c, i32 0, i32 0
  %v = load i32, ptr %p
  ret i32 %v
}

define ptr @console_text(ptr %c) {
entry:
  %p = getelementptr inbounds %Console, ptr %c, i32 0, i32 1
  %v = load ptr, ptr %p
  ret ptr %v
}

define i64 @console_len(ptr %c) {
entry:
  %p = getelementptr inbounds %Console, ptr %c, i32 0, i32 2
  %v = load i64, ptr %p
  ret i64 %v
}

; Agrega un codepoint (byte bajo). ch == 8 borra el ultimo caracter.
define void @console_push(ptr %c, i64 %ch) {
entry:
  %lp = getelementptr inbounds %Console, ptr %c, i32 0, i32 2
  %len = load i64, ptr %lp
  %is_bs = icmp eq i64 %ch, 8
  br i1 %is_bs, label %backspace, label %append
backspace:
  %can = icmp sgt i64 %len, 0
  br i1 %can, label %do_bs, label %done
do_bs:
  %n1 = sub i64 %len, 1
  store i64 %n1, ptr %lp
  %bp = getelementptr inbounds %Console, ptr %c, i32 0, i32 1
  %b = load ptr, ptr %bp
  %term = getelementptr i8, ptr %b, i64 %n1
  store i8 0, ptr %term
  br label %done
append:
  %capp = getelementptr inbounds %Console, ptr %c, i32 0, i32 3
  %cap = load i64, ptr %capp
  %room = icmp slt i64 %len, %cap
  br i1 %room, label %do_append, label %done
do_append:
  %bp2 = getelementptr inbounds %Console, ptr %c, i32 0, i32 1
  %b2 = load ptr, ptr %bp2
  %at = getelementptr i8, ptr %b2, i64 %len
  %ch8 = trunc i64 %ch to i8
  store i8 %ch8, ptr %at
  %n2 = add i64 %len, 1
  store i64 %n2, ptr %lp
  %term2 = getelementptr i8, ptr %b2, i64 %n2
  store i8 0, ptr %term2
  br label %done
done:
  ret void
}

define void @console_set_last(ptr %c, ptr %pat, i64 %len) {
entry:
  %lastp = getelementptr inbounds %Console, ptr %c, i32 0, i32 4
  %old = load ptr, ptr %lastp
  %has = icmp ne ptr %old, null
  br i1 %has, label %freeold, label %alloc
freeold:
  call void @free(ptr %old)
  br label %alloc
alloc:
  %n = add i64 %len, 1
  %buf = call ptr @malloc(i64 %n)
  %bn = icmp eq ptr %buf, null
  br i1 %bn, label %fail, label %copy
fail:
  store ptr null, ptr %lastp
  %lastl0 = getelementptr inbounds %Console, ptr %c, i32 0, i32 5
  store i64 0, ptr %lastl0
  ret void
copy:
  %r = call ptr @memcpy(ptr %buf, ptr %pat, i64 %len)
  %term = getelementptr i8, ptr %buf, i64 %len
  store i8 0, ptr %term
  store ptr %buf, ptr %lastp
  %lastl = getelementptr inbounds %Console, ptr %c, i32 0, i32 5
  store i64 %len, ptr %lastl
  ret void
}

define i32 @console_execute(ptr %c, ptr %ed) {
entry:
  %pp = getelementptr inbounds %Console, ptr %c, i32 0, i32 0
  %prefix = load i32, ptr %pp
  %bp = getelementptr inbounds %Console, ptr %c, i32 0, i32 1
  %buf = load ptr, ptr %bp
  %lp = getelementptr inbounds %Console, ptr %c, i32 0, i32 2
  %len = load i64, ptr %lp
  %iscolon = icmp eq i32 %prefix, 58
  br i1 %iscolon, label %cmd_colon, label %cmd_slash
cmd_colon:
  %rw = call i32 @strcmp(ptr %buf, ptr @CMD_W)
  %isw = icmp eq i32 %rw, 0
  br i1 %isw, label %do_save, label %qbchk
qbchk:
  %rqb = call i32 @strcmp(ptr %buf, ptr @CMD_QB)
  %isqb = icmp eq i32 %rqb, 0
  br i1 %isqb, label %do_quit, label %qchk
qchk:
  %rq = call i32 @strcmp(ptr %buf, ptr @CMD_Q)
  %isq = icmp eq i32 %rq, 0
  br i1 %isq, label %do_quit, label %wqchk
wqchk:
  %rwq = call i32 @strcmp(ptr %buf, ptr @CMD_WQ)
  %iswq = icmp eq i32 %rwq, 0
  br i1 %iswq, label %do_savequit, label %saveas_chk
saveas_chk:
  ; "w <ruta>" -> save_as con el substring desde buf+2
  %b0 = load i8, ptr %buf
  %b0w = icmp eq i8 %b0, 119
  %len2 = icmp sgt i64 %len, 2
  %b1p = getelementptr i8, ptr %buf, i64 1
  %b1 = load i8, ptr %b1p
  %b1sp = icmp eq i8 %b1, 32
  %c1 = and i1 %b0w, %len2
  %is_saveas = and i1 %c1, %b1sp
  br i1 %is_saveas, label %do_saveas, label %open_chk
open_chk:
  ; "e <ruta>" -> open; "e" solo -> recargar la ruta actual
  %b0e = icmp eq i8 %b0, 101
  %len_e = icmp sge i64 %len, 1
  %is_e = and i1 %b0e, %len_e
  br i1 %is_e, label %do_open, label %unknown
do_open:
  %len_e2 = icmp sgt i64 %len, 2
  br i1 %len_e2, label %open_path, label %open_reload
open_path:
  %opath = getelementptr i8, ptr %buf, i64 2
  %ro = call i32 @win_editor_open(ptr %ed, ptr %opath)
  ret i32 1
open_reload:
  ; "e" sin ruta: recargar desde la ruta actual del editor
  %rpath = call ptr @win_editor_path(ptr %ed)
  %rr = call i32 @win_editor_open(ptr %ed, ptr %rpath)
  ret i32 1
do_saveas:
  %pathp = getelementptr i8, ptr %buf, i64 2
  %rsa = call i32 @win_editor_save_as(ptr %ed, ptr %pathp)
  ret i32 1
do_save:
  %sr = call i32 @win_editor_save(ptr %ed)
  ret i32 1
do_quit:
  call void @win_editor_request_quit(ptr %ed)
  ret i32 1
do_savequit:
  %sr2 = call i32 @win_editor_save(ptr %ed)
  call void @win_editor_request_quit(ptr %ed)
  ret i32 1
cmd_slash:
  call void @console_set_last(ptr %c, ptr %buf, i64 %len)
  %srch = call i32 @win_editor_search(ptr %ed, ptr %buf, i64 %len, i32 1)
  ret i32 %srch
unknown:
  ; comando no-builtin: delegar al intérprete externo (Fexl batch) via
  ; callback. console no contiene el intérprete, solo lo llama.
  %evalp2 = getelementptr inbounds %Console, ptr %c, i32 0, i32 6
  %eval = load ptr, ptr %evalp2
  %has = icmp ne ptr %eval, null
  br i1 %has, label %call_eval, label %no_eval
call_eval:
  %res = call i32 %eval(ptr %buf, i64 %len)
  ret i32 %res
no_eval:
  ret i32 0
}

define i32 @console_repeat(ptr %c, ptr %ed, i32 %forward) {
entry:
  %lastp = getelementptr inbounds %Console, ptr %c, i32 0, i32 4
  %pat = load ptr, ptr %lastp
  %null = icmp eq ptr %pat, null
  br i1 %null, label %no, label %lenchk
lenchk:
  %lastl = getelementptr inbounds %Console, ptr %c, i32 0, i32 5
  %len = load i64, ptr %lastl
  %nz = icmp sgt i64 %len, 0
  br i1 %nz, label %go, label %no
go:
  %r = call i32 @win_editor_search(ptr %ed, ptr %pat, i64 %len, i32 %forward)
  ret i32 %r
no:
  ret i32 0
}
