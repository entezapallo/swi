; core/rx_query.ll — busqueda "anywhere" sobre un RxProgram ya compilado.
;
; rx_run (regex_runner.ll) es 100% anclado: matchea desde el inicio del
; slice. Estos entry points itera posiciones de inicio llamando a rx_run
; sobre text+start. El patron se compila UNA vez afuera (RxProgram*) y se
; reusa en todas las posiciones -- no se recompila por posicion.
;
; No conoce TextBuffer ni mmap: entrada pura (ptr, len), igual que el runner.
; No usa `switch` -> no necesita -relocation-model=pic.
;
; %RxProgram/%RxInst duplicados con el mismo layout que regex_compiler.ll.
%RxInst    = type { i64, i64, i64 }
%RxProgram = type { ptr, i64, i64 }

declare ptr @rx_run(ptr, ptr, i64)
declare i64 @thread_get_save(ptr, i64)
declare void @thread_kill(ptr)

; Busca el primer match con inicio >= %from. Devuelve el offset de INICIO
; del match, o -1 si no hay. %forward != 0 = adelante, == 0 = atras.
; Un match de ancho cero se acepta (es logica del llamador avanzar).
define i64 @rx_search_any(ptr %prog, ptr %text, i64 %tlen,
                           i64 %from, i32 %forward) {
entry:
  %is_fwd = icmp ne i32 %forward, 0
  br i1 %is_fwd, label %init_fwd, label %init_back
init_fwd:
  %start0f = icmp slt i64 %from, 0
  %s0f = select i1 %start0f, i64 0, i64 %from
  br label %fwd_check
init_back:
  ; atras: arrancar en min(from, tlen)
  %over = icmp sgt i64 %from, %tlen
  %s0b = select i1 %over, i64 %tlen, i64 %from
  br label %back_check

fwd_check:
  %sf = phi i64 [ %s0f, %init_fwd ], [ %sf_next, %fwd_next ]
  %f_done = icmp sgt i64 %sf, %tlen
  br i1 %f_done, label %none, label %f_try
f_try:
  %slicef = getelementptr i8, ptr %text, i64 %sf
  %remf = sub i64 %tlen, %sf
  %tf = call ptr @rx_run(ptr %prog, ptr %slicef, i64 %remf)
  %hitf = icmp ne ptr %tf, null
  br i1 %hitf, label %found, label %fwd_next
fwd_next:
  %sf_next = add i64 %sf, 1
  br label %fwd_check

back_check:
  %sb = phi i64 [ %s0b, %init_back ], [ %sb_next, %back_next ]
  %b_done = icmp slt i64 %sb, 0
  br i1 %b_done, label %none, label %b_try
b_try:
  %sliceb = getelementptr i8, ptr %text, i64 %sb
  %remb = sub i64 %tlen, %sb
  %tb = call ptr @rx_run(ptr %prog, ptr %sliceb, i64 %remb)
  %hitb = icmp ne ptr %tb, null
  br i1 %hitb, label %found, label %back_next
back_next:
  %sb_next = sub i64 %sb, 1
  br label %back_check

found:
  %tf2 = phi ptr [ %tf, %f_try ], [ %tb, %b_try ]
  %pos = phi i64 [ %sf, %f_try ], [ %sb, %b_try ]
  call void @thread_kill(ptr %tf2)
  ret i64 %pos
none:
  ret i64 -1
}

; Cuenta matches NO solapados de izquierda a derecha. Tras un match que
; termina en %end, sigue buscando desde max(%end, start+1) para no trabarse
; en matches de ancho cero ni re-contar el mismo lugar.
define i64 @rx_count(ptr %prog, ptr %text, i64 %tlen) {
entry:
  br label %loop
loop:
  %from = phi i64 [ 0, %entry ], [ %endok, %have ]
  %n = phi i64 [ 0, %entry ], [ %n1, %have ]
  %s = call i64 @rx_search_any(ptr %prog, ptr %text, i64 %tlen, i64 %from, i32 1)
  %nomatch = icmp eq i64 %s, -1
  br i1 %nomatch, label %done, label %have
have:
  %slice = getelementptr i8, ptr %text, i64 %s
  %rem = sub i64 %tlen, %s
  %t = call ptr @rx_run(ptr %prog, ptr %slice, i64 %rem)
  %endrel = call i64 @thread_get_save(ptr %t, i64 1)
  call void @thread_kill(ptr %t)
  %endabs = add i64 %s, %endrel
  %plus1 = add i64 %s, 1
  %afterempty = icmp sgt i64 %endabs, %plus1
  %endok = select i1 %afterempty, i64 %endabs, i64 %plus1
  %n1 = add i64 %n, 1
  br label %loop
done:
  ret i64 %n
}

; Escribe hasta %max spans en %out_starts / %out_ends (arrays de i64).
; Devuelve la cantidad escrita. Mismo criterio de avance que rx_count.
define i64 @rx_spans(ptr %prog, ptr %text, i64 %tlen,
                      ptr %out_starts, ptr %out_ends, i64 %max) {
entry:
  %full = icmp sle i64 %max, 0
  br i1 %full, label %done, label %loop
loop:
  %from = phi i64 [ 0, %entry ], [ %endok, %have ]
  %k = phi i64 [ 0, %entry ], [ %k1, %have ]
  %nomore = icmp sge i64 %k, %max
  br i1 %nomore, label %done, label %find
find:
  %s = call i64 @rx_search_any(ptr %prog, ptr %text, i64 %tlen, i64 %from, i32 1)
  %nomatch = icmp eq i64 %s, -1
  br i1 %nomatch, label %done, label %have
have:
  %slice = getelementptr i8, ptr %text, i64 %s
  %rem = sub i64 %tlen, %s
  %t = call ptr @rx_run(ptr %prog, ptr %slice, i64 %rem)
  %endrel = call i64 @thread_get_save(ptr %t, i64 1)
  call void @thread_kill(ptr %t)
  %endabs = add i64 %s, %endrel
  %dst_s = getelementptr i64, ptr %out_starts, i64 %k
  store i64 %s, ptr %dst_s
  %dst_e = getelementptr i64, ptr %out_ends, i64 %k
  store i64 %endabs, ptr %dst_e
  %plus1 = add i64 %s, 1
  %afterempty = icmp sgt i64 %endabs, %plus1
  %endok = select i1 %afterempty, i64 %endabs, i64 %plus1
  %k1 = add i64 %k, 1
  br label %loop
done:
  %written = phi i64 [ 0, %entry ], [ %k, %loop ], [ %k, %find ]
  ret i64 %written
}
