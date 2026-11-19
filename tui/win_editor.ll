; win_editor.ll — ventana de editor de swi (TUI), NO el motor del editor.
;
; Consume %Action (state.ll) y usa el motor del editor via `declare`
; (doc_*, tb_*, li_*, find_next, fsio_*). El motor del editor nunca sabe que
; este modulo existe.
;
; El cursor es un offset de byte en el TextBuffer. La traduccion offset->linea
; delega en li_line_for_offset (lineindex.ll, busqueda binaria) via el helper
; ew_line_at. Antes se hacia un scan lineal aca; ahora el core cumple su ABI.
;
; Usa `switch` -> compilar con -relocation-model=pic.
;
; Paleta (espejo de out.h, no reordenar): OUT_DEFAULT=0 OUT_WHITE=8
;   OUT_BRIGHT_WHITE=16 OUT_BRIGHT_BLACK=9 OUT_BLUE=5 OUT_ATTR_NONE=0
;
; Action kind (espejo de state.ll): 1 MODE 2 INSERT_CHAR 3 MOTION
;   4 OPERATOR 5 EDIT 6 CMDLINE 7 EXECUTE 8 CANCEL 9 QUIT
; Motion: 1 left 2 right 3 up 4 down 5 line_start 6 line_end 7 doc_start 8 doc_end
; Op: 1 d 2 y 3 c ; Edit: 1 x 2 dd 3 yy 4 cc 5 p 6 u 7 redo 8 backspace
;
; %EditorWin = { ptr doc, i64 cursor, i64 desire_col, i64 top_line,
;                i64 hscroll, ptr path, ptr reg, i64 reg_len, i64 reg_cap,
;                i32 dirty, i32 quit, i32 vrows, i32 vcols,
;                ptr hl_fmt, ptr hl_pattern, i64 hl_len,
;                i64 anchor, i32 visual }              ; 128 bytes

%EditorWin = type { ptr, i64, i64, i64, i64, ptr, ptr, i64, i64, i32, i32, i32, i32, ptr, ptr, i64, i64, i32 }
%Action    = type { i32, i64, i64, i64 }

declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare ptr @strdup(ptr)

declare ptr @doc_load(ptr)
declare ptr @doc_new()
declare void @doc_destroy(ptr)
declare i32 @doc_save(ptr, ptr)
declare i32 @doc_reindex(ptr)
declare ptr @doc_lineindex(ptr)
declare i32 @doc_insert(ptr, i64, ptr, i64)
declare i32 @doc_delete(ptr, i64, i64)
declare i32 @doc_undo(ptr)
declare i32 @doc_redo(ptr)
declare i64 @li_line_count(ptr)
declare i64 @li_line_offset(ptr, i64)
declare i64 @li_line_length(ptr, i64)
declare i64 @li_line_for_offset(ptr, i64)
declare i64 @doc_length(ptr)
declare i64 @doc_read(ptr, i64, i64, ptr)
declare i32 @find_in_doc(ptr, ptr, i64, i64, i32, i32, ptr, ptr)
declare ptr @fmt_create()
declare void @fmt_destroy(ptr)
declare void @fmt_clear(ptr)
declare i64 @fmt_span_count(ptr)
declare i64 @fmt_span_offset(ptr, i64)
declare i64 @fmt_span_length(ptr, i64)
declare i64 @fmt_span_style(ptr, i64)
declare i32 @fmt_add_span(ptr, i64, i64, i64)
declare i64 @find_next(ptr, i64, ptr, i64, i64, i32, i32)
declare i32 @fsio_write_file(ptr, ptr, i64)
declare i32 @out_cell(i32, i32, i32, i32, i32, i32)

; --- constructores / accesores ---

define ptr @win_editor_new(ptr %path) {
entry:
  %pnull = icmp eq ptr %path, null
  br i1 %pnull, label %untitled, label %given
untitled:
  %tmp = call ptr @strdup(ptr @UNTITLED)
  call void @dismiss_write(ptr @UNTITLED)
  br label %load
given:
  %dup = call ptr @strdup(ptr %path)
  br label %load
load:
  %finalpath = phi ptr [ %tmp, %untitled ], [ %dup, %given ]
  %doc = call ptr @doc_load(ptr %finalpath)
  %dn = icmp eq ptr %doc, null
  br i1 %dn, label %fail, label %alloc
fail:
  call void @free(ptr %finalpath)
  ret ptr null
alloc:
  %ed = call ptr @malloc(i64 128)
  %en = icmp eq ptr %ed, null
  br i1 %en, label %fail2, label %init
fail2:
  call void @doc_destroy(ptr %doc)
  call void @free(ptr %finalpath)
  ret ptr null
init:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  store ptr %doc, ptr %dp
  %c0 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  store i64 0, ptr %c0
  %dc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 2
  store i64 0, ptr %dc
  %tl = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 3
  store i64 0, ptr %tl
  %hs = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 4
  store i64 0, ptr %hs
  %pp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 5
  store ptr %finalpath, ptr %pp
  %rp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 6
  store ptr null, ptr %rp
  %rl = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 7
  store i64 0, ptr %rl
  %rc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 8
  store i64 0, ptr %rc
  %di = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 0, ptr %di
  %qu = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 10
  store i32 0, ptr %qu
  %vr = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 11
  store i32 0, ptr %vr
  %vc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 12
  store i32 0, ptr %vc
  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = call ptr @fmt_create()
  store ptr %hf, ptr %hfp
  %hpp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 14
  store ptr null, ptr %hpp2
  %hlp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 15
  store i64 0, ptr %hlp
  %anp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 16
  store i64 0, ptr %anp
  %vip = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 17
  store i32 0, ptr %vip
  ret ptr %ed
}

; win_editor_new_empty: editor sobre un Document VACIO en memoria (doc_new),
; sin truncar ni crear ningun archivo. %path es solo la ruta donde se guardara
; con :w; el llamador la genera unica por proceso/tab para evitar colisiones.
define ptr @win_editor_new_empty(ptr %path) {
entry:
  %pnull = icmp eq ptr %path, null
  br i1 %pnull, label %fail, label %do_it
do_it:
  %dup = call ptr @strdup(ptr %path)
  %dnp = icmp eq ptr %dup, null
  br i1 %dnp, label %fail, label %make_doc
make_doc:
  %doc = call ptr @doc_new()
  %dn = icmp eq ptr %doc, null
  br i1 %dn, label %fail_dup, label %alloc
alloc:
  %ed = call ptr @malloc(i64 128)
  %en = icmp eq ptr %ed, null
  br i1 %en, label %fail_doc, label %init
init:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  store ptr %doc, ptr %dp
  %c0 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  store i64 0, ptr %c0
  %dc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 2
  store i64 0, ptr %dc
  %tl = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 3
  store i64 0, ptr %tl
  %hs = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 4
  store i64 0, ptr %hs
  %pp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 5
  store ptr %dup, ptr %pp
  %rp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 6
  store ptr null, ptr %rp
  %rl = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 7
  store i64 0, ptr %rl
  %rc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 8
  store i64 0, ptr %rc
  %di = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 0, ptr %di
  %qu = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 10
  store i32 0, ptr %qu
  %vr = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 11
  store i32 0, ptr %vr
  %vc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 12
  store i32 0, ptr %vc
  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = call ptr @fmt_create()
  store ptr %hf, ptr %hfp
  %hpp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 14
  store ptr null, ptr %hpp2
  %hlp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 15
  store i64 0, ptr %hlp
  %anp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 16
  store i64 0, ptr %anp
  %vip = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 17
  store i32 0, ptr %vip
  ret ptr %ed
fail_doc:
  call void @doc_destroy(ptr %doc)
  br label %fail_dup
fail_dup:
  call void @free(ptr %dup)
  br label %fail
fail:
  ret ptr null
}

; win_editor_open: reemplaza el Document de una ventana ya existente con el
; archivo %path. Reutiliza el EditorWin (no lo destruye). Devuelve 1 si cargo,
; 0 si fallo (en ese caso la ventana queda intacta). Resetea todo estado
; dependiente del documento: cursor, scroll, registro, highlight, seleccion.
define i32 @win_editor_open(ptr %ed, ptr %path) {
entry:
  %pnull = icmp eq ptr %path, null
  br i1 %pnull, label %fail, label %do_load
do_load:
  %newdoc = call ptr @doc_load(ptr %path)
  %dn = icmp eq ptr %newdoc, null
  br i1 %dn, label %fail, label %replace
replace:
  %olddp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %olddoc = load ptr, ptr %olddp
  call void @doc_destroy(ptr %olddoc)
  store ptr %newdoc, ptr %olddp

  %c0 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  store i64 0, ptr %c0
  %dc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 2
  store i64 0, ptr %dc
  %tl = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 3
  store i64 0, ptr %tl
  %hs = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 4
  store i64 0, ptr %hs

  %oldpp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 5
  %oldpath = load ptr, ptr %oldpp
  call void @free(ptr %oldpath)
  %newpath = call ptr @strdup(ptr %path)
  store ptr %newpath, ptr %oldpp

  %rp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 6
  %oldreg = load ptr, ptr %rp
  %hasreg = icmp ne ptr %oldreg, null
  br i1 %hasreg, label %free_reg, label %reset_reg
free_reg:
  call void @free(ptr %oldreg)
  br label %reset_reg
reset_reg:
  store ptr null, ptr %rp
  %rl = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 7
  store i64 0, ptr %rl
  %rc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 8
  store i64 0, ptr %rc

  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = load ptr, ptr %hfp
  call void @fmt_clear(ptr %hf)
  %hpp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 14
  %oldhp = load ptr, ptr %hpp2
  %hashp = icmp ne ptr %oldhp, null
  br i1 %hashp, label %free_hp, label %reset_visual
free_hp:
  call void @free(ptr %oldhp)
  store ptr null, ptr %hpp2
  br label %reset_visual
reset_visual:
  %hlp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 15
  store i64 0, ptr %hlp2
  %anp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 16
  store i64 0, ptr %anp2
  %vip2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 17
  store i32 0, ptr %vip2
  %di = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 0, ptr %di
  ret i32 1
fail:
  ret i32 0
}

@UNTITLED = private constant [22 x i8] c"/tmp/swi_untitled.txt\00"

define internal void @dismiss_write(ptr %path) {
entry:
  %empty = alloca [1 x i8]
  store i8 0, ptr %empty
  %r = call i32 @fsio_write_file(ptr %path, ptr %empty, i64 0)
  ret void
}

define void @win_editor_destroy(ptr %ed) {
entry:
  %rp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 6
  %reg = load ptr, ptr %rp
  %rn = icmp ne ptr %reg, null
  br i1 %rn, label %free_reg, label %skip_reg
free_reg:
  call void @free(ptr %reg)
  br label %skip_reg
skip_reg:
  ; liberar highlight
  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = load ptr, ptr %hfp
  call void @fmt_destroy(ptr %hf)
  %hpp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 14
  %hp = load ptr, ptr %hpp2
  %hpn = icmp ne ptr %hp, null
  br i1 %hpn, label %free_hp, label %after_hp
free_hp:
  call void @free(ptr %hp)
  br label %after_hp
after_hp:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  call void @doc_destroy(ptr %doc)
  %pp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 5
  %path = load ptr, ptr %pp
  call void @free(ptr %path)
  call void @free(ptr %ed)
  ret void
}

define ptr @win_editor_doc(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %v = load ptr, ptr %p
  ret ptr %v
}

define i64 @win_editor_cursor(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %v = load i64, ptr %p
  ret i64 %v
}

; fija cursor/top al restaurar una sesion (clamp de cursor a la longitud).
define void @win_editor_set_cursor(ptr %ed, i64 %cursor, i64 %top) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %len = call i64 @doc_length(ptr %doc)
  %neg = icmp slt i64 %cursor, 0
  %c0 = select i1 %neg, i64 0, i64 %cursor
  %big = icmp sgt i64 %c0, %len
  %c = select i1 %big, i64 %len, i64 %c0
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  store i64 %c, ptr %cp
  %tlp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 3
  store i64 %top, ptr %tlp
  ret void
}

; ---------------------------------------------------------------------------
; win_editor_set_highlight: guarda el patron y construye spans de resaltado
; sobre todo el documento usando find_in_doc (multi-chunk) + fmt_add_span.
; STYLE 1 = match de busqueda. Con pat len==0 o null, limpia el resaltado.
; ---------------------------------------------------------------------------
define void @win_editor_set_highlight(ptr %ed, ptr %pat, i64 %len) {
entry:
  %sp = alloca i64
  %ep2 = alloca i64
  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = load ptr, ptr %hfp
  call void @fmt_clear(ptr %hf)
  %hpp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 14
  %oldp = load ptr, ptr %hpp2
  %hasold = icmp ne ptr %oldp, null
  br i1 %hasold, label %freeold, label %allocp
freeold:
  call void @free(ptr %oldp)
  br label %allocp
allocp:
  %empty = icmp eq i64 %len, 0
  br i1 %empty, label %clear, label %copy
clear:
  store ptr null, ptr %hpp2
  %hl0 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 15
  store i64 0, ptr %hl0
  ret void
copy:
  %buf = call ptr @malloc(i64 %len)
  %r = call ptr @memcpy(ptr %buf, ptr %pat, i64 %len)
  store ptr %buf, ptr %hpp2
  %hlp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 15
  store i64 %len, ptr %hlp

  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %total = call i64 @doc_length(ptr %doc)
  br label %scan
scan:
  %from = phi i64 [ 0, %copy ], [ %next, %add_span ]
  %past = icmp sge i64 %from, %total
  br i1 %past, label %done, label %find
find:
  %ok = call i32 @find_in_doc(ptr %doc, ptr %buf, i64 %len, i64 %from,
                               i32 1, i32 1, ptr %sp, ptr %ep2)
  %okb = icmp eq i32 %ok, 1
  br i1 %okb, label %have, label %done
have:
  %s = load i64, ptr %sp
  %e = load i64, ptr %ep2
  ; si el match está detrás del 'from' anterior, find_in_doc hizo wrap:
  ; ya vimos todos los matches -> terminar (evita ciclo).
  %wrapped = icmp slt i64 %s, %from
  br i1 %wrapped, label %done, label %add_span
add_span:
  %slen = sub i64 %e, %s
  %ar = call i32 @fmt_add_span(ptr %hf, i64 %s, i64 %slen, i64 1)
  %next = add i64 %e, 1
  br label %scan
done:
  ret void
}

; Acceso al contenedor de spans (busqueda + sintaxis).
define ptr @win_editor_fmt(ptr %ed) {
entry:
  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = load ptr, ptr %hfp
  ret ptr %hf
}

; Limpia TODOS los spans. llamar antes de recalcular busqueda o sintaxis.
define void @win_editor_clear_spans(ptr %ed) {
entry:
  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = load ptr, ptr %hfp
  call void @fmt_clear(ptr %hf)
  ret void
}

define i64 @win_editor_hl_count(ptr %ed) {
entry:
  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = load ptr, ptr %hfp
  %n = call i64 @fmt_span_count(ptr %hf)
  ret i64 %n
}

define i64 @win_editor_anchor(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 16
  %v = load i64, ptr %p
  ret i64 %v
}

define i32 @win_editor_visual(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 17
  %v = load i32, ptr %p
  ret i32 %v
}

; devuelve el style_id del span que contiene %pos, o 0 si ninguno.
define internal i64 @hl_style_at(ptr %hf, i64 %pos) {
entry:
  %n = call i64 @fmt_span_count(ptr %hf)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %inext, %next ]
  %cont = icmp slt i64 %i, %n
  br i1 %cont, label %body, label %none
body:
  %o = call i64 @fmt_span_offset(ptr %hf, i64 %i)
  %l = call i64 @fmt_span_length(ptr %hf, i64 %i)
  %end = add i64 %o, %l
  %ge = icmp sge i64 %pos, %o
  %lt = icmp slt i64 %pos, %end
  %inside = and i1 %ge, %lt
  br i1 %inside, label %found, label %next
found:
  %st = call i64 @fmt_span_style(ptr %hf, i64 %i)
  ret i64 %st
next:
  %inext = add i64 %i, 1
  br label %loop
none:
  ret i64 0
}

define i32 @win_editor_dirty(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  %v = load i32, ptr %p
  ret i32 %v
}

define i32 @win_editor_quit(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 10
  %v = load i32, ptr %p
  ret i32 %v
}

define ptr @win_editor_path(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 5
  %v = load ptr, ptr %p
  ret ptr %v
}

define void @win_editor_set_view(ptr %ed, i32 %rows, i32 %cols) {
entry:
  %vr = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 11
  store i32 %rows, ptr %vr
  %vc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 12
  store i32 %cols, ptr %vc
  ret void
}

define i64 @win_editor_top_line(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 3
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @win_editor_hscroll(ptr %ed) {
entry:
  %p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 4
  %v = load i64, ptr %p
  ret i64 %v
}

; --- helpers internos ---

define internal i64 @ew_line_at(ptr %ed, i64 %off) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %li = call ptr @doc_lineindex(ptr %doc)
  %line = call i64 @li_line_for_offset(ptr %li, i64 %off)
  ret i64 %line
}

define internal void @ew_clamp_cursor(ptr %ed) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %len = call i64 @doc_length(ptr %doc)
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %neg = icmp slt i64 %cur, 0
  br i1 %neg, label %to0, label %hi
to0:
  store i64 0, ptr %cp
  ret void
hi:
  %big = icmp sgt i64 %cur, %len
  br i1 %big, label %tolen, label %done
tolen:
  store i64 %len, ptr %cp
  br label %done
done:
  ret void
}

define internal void @ew_sync(ptr %ed) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %r = call i32 @doc_reindex(ptr %doc)
  call void @ew_clamp_cursor(ptr %ed)
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %line = call i64 @ew_line_at(ptr %ed, i64 %cur)
  %tlp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 3
  %top = load i64, ptr %tlp
  %before = icmp slt i64 %line, %top
  br i1 %before, label %fix_up, label %check_view
fix_up:
  store i64 %line, ptr %tlp
  ret void
check_view:
  %vrp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 11
  %vr = load i32, ptr %vrp
  %has = icmp sgt i32 %vr, 0
  br i1 %has, label %check_down, label %done
check_down:
  %vri = sext i32 %vr to i64
  %limit = add i64 %top, %vri
  %after = icmp sge i64 %line, %limit
  br i1 %after, label %fix_down, label %done
fix_down:
  %raw = sub i64 %line, %vri
  %newtop = add i64 %raw, 1
  store i64 %newtop, ptr %tlp
  ret void
done:
  ret void
}

define internal void @ew_move_to(ptr %ed, i64 %line, i64 %col) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %li = call ptr @doc_lineindex(ptr %doc)
  %n = call i64 @li_line_count(ptr %li)
  %nz = icmp sgt i64 %n, 0
  br i1 %nz, label %valid, label %empty
empty:
  %c0 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  store i64 0, ptr %c0
  %d0 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 2
  store i64 %col, ptr %d0
  ret void
valid:
  %last = sub i64 %n, 1
  %lhi = icmp sgt i64 %line, %last
  %ln = select i1 %lhi, i64 %last, i64 %line
  %llo = icmp slt i64 %ln, 0
  %l = select i1 %llo, i64 0, i64 %ln
  %o = call i64 @li_line_offset(ptr %li, i64 %l)
  %len = call i64 @li_line_length(ptr %li, i64 %l)
  %chi = icmp sgt i64 %col, %len
  %c = select i1 %chi, i64 %len, i64 %col
  %clo = icmp slt i64 %c, 0
  %cc = select i1 %clo, i64 0, i64 %c
  %off = add i64 %o, %cc
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  store i64 %off, ptr %cp
  %dcp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 2
  store i64 %cc, ptr %dcp
  ret void
}

; --- movimientos de palabra (ASCII alnum + '_' = palabra) ---

define internal i32 @ew_is_word(i8 %c) {
entry:
  %ci = zext i8 %c to i32
  %ga = icmp sge i32 %ci, 97
  %lz = icmp sle i32 %ci, 122
  %low = and i1 %ga, %lz
  %ga2 = icmp sge i32 %ci, 65
  %lz2 = icmp sle i32 %ci, 90
  %up = and i1 %ga2, %lz2
  %g0 = icmp sge i32 %ci, 48
  %l9 = icmp sle i32 %ci, 57
  %dig = and i1 %g0, %l9
  %us = icmp eq i32 %ci, 95
  %lo_up = or i1 %low, %up
  %lo_up_dig = or i1 %lo_up, %dig
  %any = or i1 %lo_up_dig, %us
  %r = zext i1 %any to i32
  ret i32 %r
}

define internal i64 @ew_skip_word(ptr %data, i64 %len, i64 %pos) {
entry:
  %lt = icmp slt i64 %pos, %len
  br i1 %lt, label %loop, label %ret_pos
ret_pos:
  ret i64 %pos
loop:
  %i = phi i64 [ %pos, %entry ], [ %inext, %inc ]
  %cont = icmp slt i64 %i, %len
  br i1 %cont, label %body, label %ret_i
body:
  %at = getelementptr i8, ptr %data, i64 %i
  %b = load i8, ptr %at
  %w = call i32 @ew_is_word(i8 %b)
  %isw = icmp ne i32 %w, 0
  br i1 %isw, label %inc, label %ret_i
inc:
  %inext = add i64 %i, 1
  br label %loop
ret_i:
  ret i64 %i
}

define internal i64 @ew_skip_nonword(ptr %data, i64 %len, i64 %pos) {
entry:
  %lt = icmp slt i64 %pos, %len
  br i1 %lt, label %loop, label %ret_pos
ret_pos:
  ret i64 %pos
loop:
  %i = phi i64 [ %pos, %entry ], [ %inext, %inc ]
  %cont = icmp slt i64 %i, %len
  br i1 %cont, label %body, label %ret_i
body:
  %at = getelementptr i8, ptr %data, i64 %i
  %b = load i8, ptr %at
  %w = call i32 @ew_is_word(i8 %b)
  %isw = icmp ne i32 %w, 0
  br i1 %isw, label %ret_i, label %inc
inc:
  %inext = add i64 %i, 1
  br label %loop
ret_i:
  ret i64 %i
}

define internal i64 @ew_skip_word_back(ptr %data, i64 %pos) {
entry:
  %gt = icmp sgt i64 %pos, 0
  br i1 %gt, label %loop, label %ret_zero
ret_zero:
  ret i64 0
loop:
  %i = phi i64 [ %pos, %entry ], [ %inext, %inc ]
  %cont = icmp sgt i64 %i, 0
  br i1 %cont, label %body, label %ret_i
body:
  %prev = sub i64 %i, 1
  %at = getelementptr i8, ptr %data, i64 %prev
  %b = load i8, ptr %at
  %w = call i32 @ew_is_word(i8 %b)
  %isw = icmp ne i32 %w, 0
  br i1 %isw, label %inc, label %ret_i
inc:
  %inext = sub i64 %i, 1
  br label %loop
ret_i:
  ret i64 %i
}

define internal i64 @ew_skip_nonword_back(ptr %data, i64 %pos) {
entry:
  %gt = icmp sgt i64 %pos, 0
  br i1 %gt, label %loop, label %ret_zero
ret_zero:
  ret i64 0
loop:
  %i = phi i64 [ %pos, %entry ], [ %inext, %inc ]
  %cont = icmp sgt i64 %i, 0
  br i1 %cont, label %body, label %ret_i
body:
  %prev = sub i64 %i, 1
  %at = getelementptr i8, ptr %data, i64 %prev
  %b = load i8, ptr %at
  %w = call i32 @ew_is_word(i8 %b)
  %isw = icmp ne i32 %w, 0
  br i1 %isw, label %ret_i, label %inc
inc:
  %inext = sub i64 %i, 1
  br label %loop
ret_i:
  ret i64 %i
}

define internal i64 @ew_word_fwd(ptr %ed, i64 %from, i64 %count) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %total = call i64 @doc_length(ptr %doc)
  %clampf = icmp sgt i64 %from, %total
  %base = select i1 %clampf, i64 %total, i64 %from
  %buf = alloca [4096 x i8]
  %data = getelementptr [4096 x i8], ptr %buf, i32 0, i32 0
  %len = call i64 @doc_read(ptr %doc, i64 %base, i64 4096, ptr %data)
  %p0 = add i64 0, 0
  br label %loop
loop:
  %p = phi i64 [ %p0, %entry ], [ %pnext, %body ]
  %n = phi i64 [ 0, %entry ], [ %nnext, %body ]
  %done = icmp sge i64 %n, %count
  br i1 %done, label %ret_p, label %body
body:
  %a = call i64 @ew_skip_word(ptr %data, i64 %len, i64 %p)
  %b2 = call i64 @ew_skip_nonword(ptr %data, i64 %len, i64 %a)
  %overb = icmp sgt i64 %b2, %len
  %pnext = select i1 %overb, i64 %len, i64 %b2
  %nnext = add i64 %n, 1
  br label %loop
ret_p:
  %abs = add i64 %base, %p
  ret i64 %abs
}

define internal i64 @ew_word_back(ptr %ed, i64 %from, i64 %count) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %rawbase = sub i64 %from, 4096
  %negbase = icmp slt i64 %rawbase, 0
  %base = select i1 %negbase, i64 0, i64 %rawbase
  %buf = alloca [4096 x i8]
  %data = getelementptr [4096 x i8], ptr %buf, i32 0, i32 0
  %len = call i64 @doc_read(ptr %doc, i64 %base, i64 4096, ptr %data)
  %relraw = sub i64 %from, %base
  %p0raw = sub i64 %relraw, 1
  %neg = icmp slt i64 %p0raw, 0
  %p0 = select i1 %neg, i64 0, i64 %p0raw
  br label %loop
loop:
  %p = phi i64 [ %p0, %entry ], [ %pnext, %body ]
  %n = phi i64 [ 0, %entry ], [ %nnext, %body ]
  %done = icmp sge i64 %n, %count
  br i1 %done, label %ret_p, label %body
body:
  %a = call i64 @ew_skip_nonword_back(ptr %data, i64 %p)
  %b2 = call i64 @ew_skip_word_back(ptr %data, i64 %a)
  %negp = icmp slt i64 %b2, 0
  %pnext = select i1 %negp, i64 0, i64 %b2
  %nnext = add i64 %n, 1
  br label %loop
ret_p:
  %abs = add i64 %base, %p
  ret i64 %abs
}

define internal i64 @ew_word_end(ptr %ed, i64 %from, i64 %count) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %total = call i64 @doc_length(ptr %doc)
  %clamp2 = icmp sgt i64 %from, %total
  %base = select i1 %clamp2, i64 %total, i64 %from
  %buf = alloca [4096 x i8]
  %data = getelementptr [4096 x i8], ptr %buf, i32 0, i32 0
  %len = call i64 @doc_read(ptr %doc, i64 %base, i64 4096, ptr %data)
  %p0raw = add i64 0, 1
  %over = icmp sgt i64 %p0raw, %len
  %p0 = select i1 %over, i64 %len, i64 %p0raw
  br label %loop
loop:
  %p = phi i64 [ %p0, %entry ], [ %pnext, %body ]
  %n = phi i64 [ 0, %entry ], [ %nnext, %body ]
  %done = icmp sge i64 %n, %count
  br i1 %done, label %ret_p, label %body
body:
  %a = call i64 @ew_skip_nonword(ptr %data, i64 %len, i64 %p)
  %b2 = call i64 @ew_skip_word(ptr %data, i64 %len, i64 %a)
  %p1 = sub i64 %b2, 1
  %negp = icmp slt i64 %p1, 0
  %pnext = select i1 %negp, i64 0, i64 %p1
  %nnext = add i64 %n, 1
  br label %loop
ret_p:
  %abs = add i64 %base, %p
  ret i64 %abs
}

; --- movimientos ---

define internal void @ew_apply_motion(ptr %ed, i64 %motion, i64 %count) {
entry:
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %dcp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 2
  %des = load i64, ptr %dcp
  %line = call i64 @ew_line_at(ptr %ed, i64 %cur)
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %li = call ptr @doc_lineindex(ptr %doc)
  %lbase = call i64 @li_line_offset(ptr %li, i64 %line)
  %llen = call i64 @li_line_length(ptr %li, i64 %line)
  %lend = add i64 %lbase, %llen
  %nlines = call i64 @li_line_count(ptr %li)

  switch i64 %motion, label %done [
    i64 1, label %left
    i64 2, label %right
    i64 3, label %up
    i64 4, label %down
    i64 5, label %lstart
    i64 6, label %motion_lend
    i64 7, label %dstart
    i64 8, label %dend
    i64 9, label %word_fwd
    i64 10, label %word_back
    i64 11, label %word_end
  ]

left:
  %step_l = mul i64 %count, 1
  %raw_l = sub i64 %cur, %step_l
  %clamp_l = icmp slt i64 %raw_l, %lbase
  %nl = select i1 %clamp_l, i64 %lbase, i64 %raw_l
  store i64 %nl, ptr %cp
  %ndes_l = sub i64 %nl, %lbase
  store i64 %ndes_l, ptr %dcp
  br label %done

right:
  %raw_r = add i64 %cur, %count
  %clamp_r = icmp sgt i64 %raw_r, %lend
  %nr = select i1 %clamp_r, i64 %lend, i64 %raw_r
  store i64 %nr, ptr %cp
  %ndes_r = sub i64 %nr, %lbase
  store i64 %ndes_r, ptr %dcp
  br label %done

up:
  %raw_u = sub i64 %line, %count
  %clamp_u = icmp slt i64 %raw_u, 0
  %nu = select i1 %clamp_u, i64 0, i64 %raw_u
  call void @ew_move_to(ptr %ed, i64 %nu, i64 %des)
  br label %done

down:
  %raw_d = add i64 %line, %count
  %last_d = sub i64 %nlines, 1
  %clamp_d = icmp sgt i64 %raw_d, %last_d
  %nd = select i1 %clamp_d, i64 %last_d, i64 %raw_d
  call void @ew_move_to(ptr %ed, i64 %nd, i64 %des)
  br label %done

lstart:
  call void @ew_move_to(ptr %ed, i64 %line, i64 0)
  br label %done

motion_lend:
  call void @ew_move_to(ptr %ed, i64 %line, i64 %llen)
  br label %done

dstart:
  call void @ew_move_to(ptr %ed, i64 0, i64 0)
  br label %done

dend:
  %last_de = sub i64 %nlines, 1
  %len_de = call i64 @li_line_length(ptr %li, i64 %last_de)
  call void @ew_move_to(ptr %ed, i64 %last_de, i64 %len_de)
  br label %done

word_fwd:
  %wf = call i64 @ew_word_fwd(ptr %ed, i64 %cur, i64 %count)
  store i64 %wf, ptr %cp
  br label %done

word_back:
  %wb = call i64 @ew_word_back(ptr %ed, i64 %cur, i64 %count)
  store i64 %wb, ptr %cp
  br label %done

word_end:
  %we = call i64 @ew_word_end(ptr %ed, i64 %cur, i64 %count)
  store i64 %we, ptr %cp
  br label %done

done:
  ; columna deseada y hscroll: que el cursor nunca quede fuera de la vista
  %newcur = load i64, ptr %cp
  %newline = call i64 @ew_line_at(ptr %ed, i64 %newcur)
  %newbase = call i64 @li_line_offset(ptr %li, i64 %newline)
  %newcol = sub i64 %newcur, %newbase
  store i64 %newcol, ptr %dcp
  %hsp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 4
  %hs = load i64, ptr %hsp
  %col_left = icmp slt i64 %newcol, %hs
  br i1 %col_left, label %hs_left, label %hs_right_chk
hs_left:
  store i64 %newcol, ptr %hsp
  ret void
hs_right_chk:
  %vcp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 12
  %vc = load i32, ptr %vcp
  %vcpos = icmp sgt i32 %vc, 0
  br i1 %vcpos, label %hs_right_do, label %finish
hs_right_do:
  %vci = sext i32 %vc to i64
  %hs_edge = add i64 %hs, %vci
  %beyond = icmp sge i64 %newcol, %hs_edge
  br i1 %beyond, label %hs_right, label %finish
hs_right:
  %raw = sub i64 %newcol, %vci
  %newhs = add i64 %raw, 1
  store i64 %newhs, ptr %hsp
  br label %finish
finish:
  ret void
}

; --- operaciones de registro ---

define internal void @ew_set_reg(ptr %ed, ptr %src, i64 %len) {
entry:
  %rp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 6
  %old = load ptr, ptr %rp
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
  store ptr null, ptr %rp
  %rz = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 7
  store i64 0, ptr %rz
  ret void
copy:
  %r = call ptr @memcpy(ptr %buf, ptr %src, i64 %len)
  %term = getelementptr i8, ptr %buf, i64 %len
  store i8 0, ptr %term
  store ptr %buf, ptr %rp
  %rl = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 7
  store i64 %len, ptr %rl
  %rc = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 8
  store i64 %n, ptr %rc
  ret void
}

; --- ediciones ---

define internal void @ew_insert_char(ptr %ed, i64 %code, i64 %count) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %ch8 = trunc i64 %code to i8
  %buf = alloca [1 x i8]
  store i8 %ch8, ptr %buf
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %inext, %body ]
  %cont = icmp slt i64 %i, %count
  br i1 %cont, label %body, label %done
body:
  %pos = load i64, ptr %cp
  %r = call i32 @doc_insert(ptr %doc, i64 %pos, ptr %buf, i64 1)
  %p1 = add i64 %pos, 1
  store i64 %p1, ptr %cp
  %inext = add i64 %i, 1
  br label %loop
done:
  %dirty = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 1, ptr %dirty
  call void @ew_sync(ptr %ed)
  ret void
}

define internal void @ew_backspace(ptr %ed) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %can = icmp sgt i64 %cur, 0
  br i1 %can, label %do, label %done
do:
  %p = sub i64 %cur, 1
  %r = call i32 @doc_delete(ptr %doc, i64 %p, i64 1)
  store i64 %p, ptr %cp
  %dirty = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 1, ptr %dirty
  call void @ew_sync(ptr %ed)
  br label %done
done:
  ret void
}

define internal void @ew_delete_char(ptr %ed, i64 %count) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %len = call i64 @doc_length(ptr %doc)
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %avail = sub i64 %len, %cur
  %take = sub i64 %count, 1
  %n = add i64 %take, 1
  %toobig = icmp sgt i64 %n, %avail
  %usen = select i1 %toobig, i64 %avail, i64 %n
  %has = icmp sgt i64 %usen, 0
  br i1 %has, label %do, label %done
do:
  %r = call i32 @doc_delete(ptr %doc, i64 %cur, i64 %usen)
  %dirty = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 1, ptr %dirty
  call void @ew_sync(ptr %ed)
  br label %done
done:
  ret void
}

; rango de la linea %line [start, end) en offsets de byte (end incluye \n si hay)
define internal void @ew_line_range(ptr %ed, i64 %line, ptr %out_start, ptr %out_end) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %li = call ptr @doc_lineindex(ptr %doc)
  %nlines = call i64 @li_line_count(ptr %li)
  %o = call i64 @li_line_offset(ptr %li, i64 %line)
  %l = call i64 @li_line_length(ptr %li, i64 %line)
  %plain_end = add i64 %o, %l
  %line1 = add i64 %line, 1
  %has_next = icmp slt i64 %line1, %nlines
  br i1 %has_next, label %with_nl, label %last
with_nl:
  %e = add i64 %plain_end, 1
  store i64 %o, ptr %out_start
  store i64 %e, ptr %out_end
  ret void
last:
  store i64 %o, ptr %out_start
  store i64 %plain_end, ptr %out_end
  ret void
}

define internal void @ew_yank_or_delete_line(ptr %ed, i64 %count, i32 %yank_only) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %line = call i64 @ew_line_at(ptr %ed, i64 %cur)
  %li = call ptr @doc_lineindex(ptr %doc)
  %nlines = call i64 @li_line_count(ptr %li)
  %last = sub i64 %nlines, 1
  %raw_end = add i64 %line, %count
  %over = icmp sgt i64 %raw_end, %last
  %clamped = select i1 %over, i64 %last, i64 %raw_end
  %s = alloca i64
  %e = alloca i64
  call void @ew_line_range(ptr %ed, i64 %line, ptr %s, ptr %e)
  %last_s = alloca i64
  %last_e = alloca i64
  call void @ew_line_range(ptr %ed, i64 %clamped, ptr %last_s, ptr %last_e)
  %start = load i64, ptr %s
  %end = load i64, ptr %last_e
  %len = sub i64 %end, %start
  %tmp = call ptr @malloc(i64 %len)
  %got0 = call i64 @doc_read(ptr %doc, i64 %start, i64 %len, ptr %tmp)
  call void @ew_set_reg(ptr %ed, ptr %tmp, i64 %got0)
  call void @free(ptr %tmp)
  %is_yank = icmp ne i32 %yank_only, 0
  br i1 %is_yank, label %done, label %delete
delete:
  %r = call i32 @doc_delete(ptr %doc, i64 %start, i64 %len)
  store i64 %start, ptr %cp
  %dirty = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 1, ptr %dirty
  call void @ew_sync(ptr %ed)
  br label %done
done:
  ret void
}

define internal void @ew_paste(ptr %ed) {
entry:
  %rp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 6
  %reg = load ptr, ptr %rp
  %has = icmp ne ptr %reg, null
  br i1 %has, label %do, label %done
do:
  %rl = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 7
  %len = load i64, ptr %rl
  %nz = icmp sgt i64 %len, 0
  br i1 %nz, label %insert, label %done
insert:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %r = call i32 @doc_insert(ptr %doc, i64 %cur, ptr %reg, i64 %len)
  %after = add i64 %cur, %len
  store i64 %after, ptr %cp
  %dirty = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 1, ptr %dirty
  call void @ew_sync(ptr %ed)
  br label %done
done:
  ret void
}

; --- busqueda literal con wrap ---

define i32 @win_editor_search(ptr %ed, ptr %pat, i64 %plen, i32 %forward) {
entry:
  %patnull = icmp eq ptr %pat, null
  br i1 %patnull, label %no, label %lenchk
lenchk:
  %nz = icmp sgt i64 %plen, 0
  br i1 %nz, label %go, label %no
go:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %buflen = call i64 @doc_length(ptr %doc)
  %buf = call ptr @malloc(i64 %buflen)
  %got1 = call i64 @doc_read(ptr %doc, i64 0, i64 %buflen, ptr %buf)
  %cp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur = load i64, ptr %cp
  %fwd = icmp ne i32 %forward, 0
  br i1 %fwd, label %fwd_first, label %back_first
fwd_first:
  %fromf = add i64 %cur, 1
  %mf = call i64 @find_next(ptr %buf, i64 %buflen, ptr %pat, i64 %plen,
                            i64 %fromf, i32 1, i32 1)
  %okf = icmp sge i64 %mf, 0
  br i1 %okf, label %found, label %wrapf
wrapf:
  %mw = call i64 @find_next(ptr %buf, i64 %buflen, ptr %pat, i64 %plen,
                            i64 0, i32 1, i32 1)
  %okw = icmp sge i64 %mw, 0
  br i1 %okw, label %found_w, label %no
back_first:
  %fromb = sub i64 %cur, 1
  %mb = call i64 @find_next(ptr %buf, i64 %buflen, ptr %pat, i64 %plen,
                            i64 %fromb, i32 0, i32 1)
  %okb = icmp sge i64 %mb, 0
  br i1 %okb, label %found, label %wrapb
wrapb:
  %end = sub i64 %buflen, 1
  %mwb = call i64 @find_next(ptr %buf, i64 %buflen, ptr %pat, i64 %plen,
                             i64 %end, i32 0, i32 1)
  %okwb = icmp sge i64 %mwb, 0
  br i1 %okwb, label %found_w, label %no
found:
  %pf = phi i64 [ %mf, %fwd_first ], [ %mb, %back_first ]
  br label %place
found_w:
  %pw = phi i64 [ %mw, %wrapf ], [ %mwb, %wrapb ]
  br label %place
place:
  %p = phi i64 [ %pf, %found ], [ %pw, %found_w ]
  store i64 %p, ptr %cp
  %line = call i64 @ew_line_at(ptr %ed, i64 %p)
  %tlp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 3
  store i64 %line, ptr %tlp
  %li = call ptr @doc_lineindex(ptr %doc)
  %lo = call i64 @li_line_offset(ptr %li, i64 %line)
  %col = sub i64 %p, %lo
  %dcp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 2
  store i64 %col, ptr %dcp
  ret i32 1
no:
  ret i32 0
}

define void @win_editor_request_quit(ptr %ed) {
entry:
  %qp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 10
  store i32 1, ptr %qp
  ret void
}

define i32 @win_editor_save(ptr %ed) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %pp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 5
  %path = load ptr, ptr %pp
  %r = call i32 @doc_save(ptr %doc, ptr %path)
  %saveok = icmp eq i32 %r, 1
  br i1 %saveok, label %ok, label %fail
ok:
  %dirty = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 0, ptr %dirty
  ret i32 1
fail:
  ret i32 0
}

define i32 @win_editor_save_as(ptr %ed, ptr %path) {
entry:
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %r = call i32 @doc_save(ptr %doc, ptr %path)
  %ok = icmp eq i32 %r, 1
  br i1 %ok, label %yes, label %no
yes:
  %pp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 5
  %old = load ptr, ptr %pp
  %freeold = icmp ne ptr %old, null
  br i1 %freeold, label %free_it, label %dup
free_it:
  call void @free(ptr %old)
  br label %dup
dup:
  %newpath = call ptr @strdup(ptr %path)
  store ptr %newpath, ptr %pp
  %dirty = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 0, ptr %dirty
  ret i32 1
no:
  ret i32 0
}

; --- paso de acciones ---

define i32 @win_editor_step(ptr %ed, ptr %action) {
entry:
  %kp = getelementptr inbounds %Action, ptr %action, i32 0, i32 0
  %ap = getelementptr inbounds %Action, ptr %action, i32 0, i32 1
  %bp = getelementptr inbounds %Action, ptr %action, i32 0, i32 2
  %kind = load i32, ptr %kp
  %a = load i64, ptr %ap
  %b = load i64, ptr %bp

  switch i32 %kind, label %none [
    i32 1, label %mode_change
    i32 2, label %char
    i32 3, label %motion
    i32 4, label %operator
    i32 5, label %edit
    i32 9, label %quit
    i32 12, label %hscroll
    i32 14, label %visual_op
  ]

mode_change:
  %vip2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 17
  %is_visual = icmp eq i64 %a, 2
  %vflag = zext i1 %is_visual to i32
  store i32 %vflag, ptr %vip2
  br i1 %is_visual, label %set_anchor, label %mode_done
set_anchor:
  %cpp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %curc = load i64, ptr %cpp
  %anp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 16
  store i64 %curc, ptr %anp2
  br label %mode_done
mode_done:
  ret i32 1
char:
  call void @ew_insert_char(ptr %ed, i64 %a, i64 1)
  ret i32 1
motion:
  call void @ew_apply_motion(ptr %ed, i64 %a, i64 %b)
  call void @ew_sync(ptr %ed)   ; ajusta top_line también al mover
  ret i32 1
operator:
  ; a = op (1 d, 2 y, 3 c), b = motion, c = count.
  ; Se calcula el rango moviendo el cursor y restaurandolo; asi 'y' y 'c'
  ; usan EXACTAMENTE el mismo rango que 'd'.
  %count_ptr = getelementptr inbounds %Action, ptr %action, i32 0, i32 3
  %cnt = load i64, ptr %count_ptr
  %curp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %orig = load i64, ptr %curp
  call void @ew_apply_motion(ptr %ed, i64 %b, i64 %cnt)
  %target = load i64, ptr %curp
  store i64 %orig, ptr %curp
  %origlo = icmp slt i64 %orig, %target
  %orighi = icmp sgt i64 %orig, %target
  %lo = select i1 %origlo, i64 %orig, i64 %target
  %hi = select i1 %orighi, i64 %orig, i64 %target
  %dellen = sub i64 %hi, %lo
  %is_y = icmp eq i64 %a, 2
  br i1 %is_y, label %op_yank_range, label %op_cut
op_yank_range:
  %docy_p = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %docy = load ptr, ptr %docy_p
  %tmpy = call ptr @malloc(i64 %dellen)
  %goty = call i64 @doc_read(ptr %docy, i64 %lo, i64 %dellen, ptr %tmpy)
  call void @ew_set_reg(ptr %ed, ptr %tmpy, i64 %goty)
  call void @free(ptr %tmpy)
  ret i32 1
op_cut:
  %docp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc2 = load ptr, ptr %docp
  %nonempty = icmp sgt i64 %dellen, 0
  br i1 %nonempty, label %do_cut, label %cut_done
do_cut:
  %r = call i32 @doc_delete(ptr %doc2, i64 %lo, i64 %dellen)
  store i64 %lo, ptr %curp
  %dirty = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 9
  store i32 1, ptr %dirty
  call void @ew_sync(ptr %ed)
  br label %cut_done
cut_done:
  ; bit 4 = el caller debe poner INSERT (c / cc)
  %is_c = icmp eq i64 %a, 3
  %want = select i1 %is_c, i32 5, i32 1
  ret i32 %want
edit:
  %akind = trunc i64 %a to i32
  switch i32 %akind, label %none [
    i32 1, label %ed_x
    i32 2, label %ed_dd
    i32 3, label %ed_yy
    i32 4, label %ed_cc
    i32 5, label %ed_p
    i32 6, label %ed_u
    i32 7, label %ed_redo
    i32 8, label %ed_bs
  ]
ed_x:
  call void @ew_delete_char(ptr %ed, i64 %b)
  ret i32 1
ed_dd:
  call void @ew_yank_or_delete_line(ptr %ed, i64 %b, i32 0)
  ret i32 1
ed_yy:
  call void @ew_yank_or_delete_line(ptr %ed, i64 %b, i32 1)
  ret i32 1
ed_cc:
  call void @ew_yank_or_delete_line(ptr %ed, i64 %b, i32 0)
  ret i32 5   ; redraw + want_insert
ed_p:
  call void @ew_paste(ptr %ed)
  ret i32 1
ed_u:
  %docup = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %docu = load ptr, ptr %docup
  %ru = call i32 @doc_undo(ptr %docu)
  call void @ew_sync(ptr %ed)
  ret i32 1
ed_redo:
  %docrp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %docr = load ptr, ptr %docrp
  %rr = call i32 @doc_redo(ptr %docr)
  call void @ew_sync(ptr %ed)
  ret i32 1
ed_bs:
  call void @ew_backspace(ptr %ed)
  ret i32 1
quit:
  %qp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 10
  store i32 1, ptr %qp
  ret i32 2
hscroll:
  %hsp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 4
  %hs = load i64, ptr %hsp
  %delta = mul i64 %a, %b
  %raw = add i64 %hs, %delta
  %neg = icmp slt i64 %raw, 0
  %new = select i1 %neg, i64 0, i64 %raw
  store i64 %new, ptr %hsp
  ret i32 1
visual_op:
  ; rango [lo,hi) entre anchor y cursor. d=1 borra, y=2 yanks, c=3 borra+INSERT
  %anp3 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 16
  %anchor = load i64, ptr %anp3
  %cpp3 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur3 = load i64, ptr %cpp3
  %alo = icmp slt i64 %anchor, %cur3
  %vlo = select i1 %alo, i64 %anchor, i64 %cur3
  %ahi = icmp sgt i64 %anchor, %cur3
  %vhi = select i1 %ahi, i64 %anchor, i64 %cur3
  %rlen = sub i64 %vhi, %vlo
  %vis_is_y = icmp eq i64 %a, 2
  br i1 %vis_is_y, label %vyank, label %vcut
vyank:
  %dp3 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc3 = load ptr, ptr %dp3
  %tmpy3 = call ptr @malloc(i64 %rlen)
  %goty3 = call i64 @doc_read(ptr %doc3, i64 %vlo, i64 %rlen, ptr %tmpy3)
  call void @ew_set_reg(ptr %ed, ptr %tmpy3, i64 %goty3)
  call void @free(ptr %tmpy3)
  br label %vdone
vcut:
  %vis_nonempty = icmp sgt i64 %rlen, 0
  br i1 %vis_nonempty, label %vis_do_cut, label %vdone
vis_do_cut:
  %vis_dp4 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %vis_doc4 = load ptr, ptr %vis_dp4
  %vis_r = call i32 @doc_delete(ptr %vis_doc4, i64 %vlo, i64 %rlen)
  store i64 %vlo, ptr %cpp3
  call void @ew_sync(ptr %ed)
  br label %vdone
vdone:
  ; limpiar seleccion
  %vip4 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 17
  store i32 0, ptr %vip4
  %vis_is_c = icmp eq i64 %a, 3
  %retv = select i1 %vis_is_c, i32 5, i32 1   ; c -> want_insert
  ret i32 %retv
none:
  ret i32 0
}

; --- dibujo: mismo algoritmo que gui/viewport.c (wrap 120%, si no trunca) ---

define void @win_editor_draw(ptr %ed, i32 %x, i32 %y, i32 %w, i32 %h) {
entry:
  %wpos = icmp sgt i32 %w, 0
  %hpos = icmp sgt i32 %h, 0
  %ok = and i1 %wpos, %hpos
  br i1 %ok, label %go, label %done_small
go:
  %vrp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 11
  store i32 %h, ptr %vrp
  %vcp2 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 12
  store i32 %w, ptr %vcp2
  %hfp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 13
  %hf = load ptr, ptr %hfp
  %vip5 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 17
  %visual = load i32, ptr %vip5
  %anp5 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 16
  %anchor = load i64, ptr %anp5
  %cpp5 = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 1
  %cur5 = load i64, ptr %cpp5
  %alo5 = icmp slt i64 %anchor, %cur5
  %sel_lo = select i1 %alo5, i64 %anchor, i64 %cur5
  %ahi5 = icmp sgt i64 %anchor, %cur5
  %sel_hi = select i1 %ahi5, i64 %anchor, i64 %cur5
  %dp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 0
  %doc = load ptr, ptr %dp
  %li = call ptr @doc_lineindex(ptr %doc)
  %nlines = call i64 @li_line_count(ptr %li)
  %tlp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 3
  %first = load i64, ptr %tlp
  %hsp = getelementptr inbounds %EditorWin, ptr %ed, i32 0, i32 4
  %hscroll = load i64, ptr %hsp
  %wi64 = sext i32 %w to i64
  %thresh = mul i64 %wi64, 6
  %threshold = sdiv i64 %thresh, 5
  br label %rowloop
rowloop:
  %line = phi i64 [ %first, %go ], [ %line_next, %next_line ]
  %row = phi i32 [ 0, %go ], [ %row_next, %next_line ]
  %rowsleft = icmp slt i32 %row, %h
  %lineok = icmp slt i64 %line, %nlines
  %continue = and i1 %rowsleft, %lineok
  br i1 %continue, label %rowbody, label %fill_tildes
rowbody:
  %off = call i64 @li_line_offset(ptr %li, i64 %line)
  %len = call i64 @li_line_length(ptr %li, i64 %line)
  %fits = icmp ule i64 %len, %wi64
  br i1 %fits, label %draw_simple, label %check_wrap
check_wrap:
  %wraps = icmp ule i64 %len, %threshold
  br i1 %wraps, label %draw_wrap1, label %draw_trunc

draw_simple:
  call void @draw_span(ptr %doc, i64 %off, i64 %len, i32 %x, i32 %y, i32 %row, i32 %w, ptr %hf, i32 %visual, i64 %sel_lo, i64 %sel_hi)
  %rs1 = add i32 %row, 1
  %ln1 = add i64 %line, 1
  br label %next_line_assign
draw_wrap1:
  call void @draw_span(ptr %doc, i64 %off, i64 %wi64, i32 %x, i32 %y, i32 %row, i32 %w, ptr %hf, i32 %visual, i64 %sel_lo, i64 %sel_hi)
  %rs2 = add i32 %row, 1
  %room = icmp slt i32 %rs2, %h
  br i1 %room, label %draw_wrap2, label %wrap_done
draw_wrap2:
  %rest = sub i64 %len, %wi64
  %off2 = add i64 %off, %wi64
  call void @draw_span(ptr %doc, i64 %off2, i64 %rest, i32 %x, i32 %y, i32 %rs2, i32 %w, ptr %hf, i32 %visual, i64 %sel_lo, i64 %sel_hi)
  %rs2b = add i32 %rs2, 1
  br label %wrap_done
wrap_done:
  %rs2f = phi i32 [ %rs2, %draw_wrap1 ], [ %rs2b, %draw_wrap2 ]
  %ln2 = add i64 %line, 1
  br label %next_line_assign_from_wrap
draw_trunc:
  %hs0 = icmp slt i64 %hscroll, 0
  %hs1 = select i1 %hs0, i64 0, i64 %hscroll
  %hbig = icmp sgt i64 %hs1, %len
  %start = select i1 %hbig, i64 %len, i64 %hs1
  %rem = sub i64 %len, %start
  %remsmall = icmp slt i64 %rem, %wi64
  %shown = select i1 %remsmall, i64 %rem, i64 %wi64
  %off3 = add i64 %off, %start
  call void @draw_span(ptr %doc, i64 %off3, i64 %shown, i32 %x, i32 %y, i32 %row, i32 %w, ptr %hf, i32 %visual, i64 %sel_lo, i64 %sel_hi)
  %rs3 = add i32 %row, 1
  %ln3 = add i64 %line, 1
  br label %next_line_assign

next_line_assign:
  %ra = phi i32 [ %rs1, %draw_simple ], [ %rs3, %draw_trunc ]
  %la = phi i64 [ %ln1, %draw_simple ], [ %ln3, %draw_trunc ]
  br label %next_line
next_line_assign_from_wrap:
  br label %next_line
next_line:
  %row_next = phi i32 [ %ra, %next_line_assign ], [ %rs2f, %next_line_assign_from_wrap ]
  %line_next = phi i64 [ %la, %next_line_assign ], [ %ln2, %next_line_assign_from_wrap ]
  br label %rowloop

fill_tildes:
  br label %tilde_loop
tilde_loop:
  %tr = phi i32 [ %row, %fill_tildes ], [ %trn, %tilde_body ]
  %tcont = icmp slt i32 %tr, %h
  br i1 %tcont, label %tilde_body, label %done_cursor
tilde_body:
  %ry = add i32 %y, %tr
  %rc = call i32 @out_cell(i32 %x, i32 %ry, i32 126,
                            i32 9, i32 0, i32 0)
  %tx = alloca i32
  store i32 1, ptr %tx
  %trn = add i32 %tr, 1
  br label %tilde_loop
done_cursor:
  ; ---- cursor visible: bloque en video inverso ----
  ; Se dibuja al final para que sobrescriba la celda del texto. Con
  ; documento vacio el LineIndex no tiene entradas: no hay cursor que
  ; dibujar (li_line_offset no es seguro ahi).
  %cur_has = icmp sgt i64 %nlines, 0
  br i1 %cur_has, label %cur_line, label %cur_end
cur_line:
  %cur_ln = call i64 @li_line_for_offset(ptr %li, i64 %cur5)
  %cur_loff = call i64 @li_line_offset(ptr %li, i64 %cur_ln)
  %cur_row = sub i64 %cur_ln, %first
  %cur_col = sub i64 %cur5, %cur_loff
  %cur_cneg = icmp slt i64 %cur_col, 0
  %cur_c0 = select i1 %cur_cneg, i64 0, i64 %cur_col
  %cur_wm1 = sub i64 %wi64, 1
  %cur_cgt = icmp sgt i64 %cur_c0, %cur_wm1
  %cur_cc = select i1 %cur_cgt, i64 %cur_wm1, i64 %cur_c0
  %cur_h64 = sext i32 %h to i64
  %cur_rneg = icmp slt i64 %cur_row, 0
  %cur_rge = icmp sge i64 %cur_row, %cur_h64
  %cur_rbad = or i1 %cur_rneg, %cur_rge
  br i1 %cur_rbad, label %cur_end, label %cur_draw
cur_draw:
  %cur_c32 = trunc i64 %cur_cc to i32
  %cur_r32 = trunc i64 %cur_row to i32
  %cur_rx = add i32 %x, %cur_c32
  %cur_ry2 = add i32 %y, %cur_r32
  %cur_total = call i64 @doc_length(ptr %doc)
  %cur_atend = icmp sge i64 %cur5, %cur_total
  br i1 %cur_atend, label %cur_space, label %cur_char
cur_space:
  br label %cur_cell
cur_char:
  %cur_buf = alloca [1 x i8]
  %cur_got = call i64 @doc_read(ptr %doc, i64 %cur5, i64 1, ptr %cur_buf)
  %cur_b = load i8, ptr %cur_buf
  %cur_ch = zext i8 %cur_b to i32
  br label %cur_cell
cur_cell:
  %cur_chv = phi i32 [ 32, %cur_space ], [ %cur_ch, %cur_char ]
  ; fg=OUT_BLACK(1), bg=OUT_WHITE(8) -> bloque invertido bien visible
  %cur_rc = call i32 @out_cell(i32 %cur_rx, i32 %cur_ry2, i32 %cur_chv,
                               i32 1, i32 8, i32 0)
  br label %cur_end
cur_end:
  br label %done_small
done_small:
  ret void
}

define internal void @draw_span(ptr %doc, i64 %off, i64 %len,
                                 i32 %x, i32 %y, i32 %row, i32 %w, ptr %hf, i32 %visual, i64 %sel_lo, i64 %sel_hi) {
entry:
  ; solo se pintan columnas visibles: leer como maximo %w bytes del Document
  %buf = alloca [256 x i8]
  %bp = getelementptr [256 x i8], ptr %buf, i32 0, i32 0
  %wi0 = sext i32 %w to i64
  %want = sub i64 %len, 0
  %cap = icmp sgt i64 %want, 256
  %use = select i1 %cap, i64 256, i64 %want
  %got = call i64 @doc_read(ptr %doc, i64 %off, i64 %use, ptr %bp)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %inext, %body ]
  %cont = icmp slt i64 %i, %len
  %ww = sext i32 %w to i64
  %colok = icmp slt i64 %i, %ww
  %both = and i1 %cont, %colok
  %i32v = trunc i64 %i to i32
  br i1 %both, label %body, label %pad
body:
  %pos = add i64 %off, %i
  %inbuf = icmp slt i64 %i, %got
  %cp = getelementptr i8, ptr %bp, i64 %i
  %b0 = load i8, ptr %cp
  %byte = select i1 %inbuf, i8 %b0, i8 32
  %ch = zext i8 %byte to i32
  %rx = add i32 %x, %i32v
  %ry = add i32 %y, %row
  ; highlight de busqueda (amarillo/bold)
  %style = call i64 @hl_style_at(ptr %hf, i64 %pos)
  %is_hl = icmp eq i64 %style, 1
  %is_kw = icmp eq i64 %style, 2
  %is_str = icmp eq i64 %style, 3
  %is_com = icmp eq i64 %style, 4
  %is_num = icmp eq i64 %style, 5
  ; seleccion visual (blanco sobre azul): visual != 0 y pos en [sel_lo,sel_hi)
  %vis_on = icmp ne i32 %visual, 0
  %sge = icmp sge i64 %pos, %sel_lo
  %slt = icmp slt i64 %pos, %sel_hi
  %sinrange = and i1 %sge, %slt
  %is_sel = and i1 %vis_on, %sinrange
  ; color: highlight gana, luego seleccion, luego normal
  ; 1=búsqueda(amarillo) 2=keyword(cian) 3=string(verde)
  ; 4=comment(gris) 5=number(magenta)
  %fg_num = select i1 %is_num, i32 14, i32 0     ; OUT_BRIGHT_MAGENTA
  %fg_com = select i1 %is_com, i32 9, i32 %fg_num ; OUT_BRIGHT_BLACK
  %fg_str = select i1 %is_str, i32 11, i32 %fg_com ; OUT_BRIGHT_GREEN
  %fg_kw = select i1 %is_kw, i32 13, i32 %fg_str  ; OUT_BRIGHT_CYAN
  %fg_hl = select i1 %is_hl, i32 12, i32 %fg_kw   ; OUT_BRIGHT_YELLOW
  %fg_sel = select i1 %is_sel, i32 15, i32 %fg_hl ; OUT_BRIGHT_WHITE
  %bg = select i1 %is_sel, i32 4, i32 0          ; OUT_BLUE
  %attr_hl = select i1 %is_hl, i32 1, i32 0
  %attr_sel = select i1 %is_sel, i32 0, i32 %attr_hl
  %r = call i32 @out_cell(i32 %rx, i32 %ry, i32 %ch, i32 %fg_sel, i32 %bg, i32 %attr_sel)
  %inext = add i64 %i, 1
  br label %loop
pad:
  %pi = phi i32 [ %i32v, %loop ], [ %pinext, %pad_body ]
  %pcont = icmp slt i32 %pi, %w
  br i1 %pcont, label %pad_body, label %done
pad_body:
  %rx2 = add i32 %x, %pi
  %ry2 = add i32 %y, %row
  %r2 = call i32 @out_cell(i32 %rx2, i32 %ry2, i32 32, i32 0, i32 0, i32 0)
  %pinext = add i32 %pi, 1
  br label %pad
done:
  ret void
}
