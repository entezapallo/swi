; core/document.ll — Document lazy sobre chunks + mmap (Etapa D, pragmatica).
;
; - doc_load NO lee el archivo completo: solo lo mapea y crea chunks que
;   apuntan al mmap (zero-copy, dirty=0). El TextBuffer maestro queda VACIO.
; - doc_read() lee desde los chunks: los limpios desde el mmap, los sucios
;   desde su TextBuffer privado (copy-on-write al editar).
; - doc_insert/doc_delete editan SOLO el chunk tocado (COW), ajustan su delta
;   y el total_len. No reconstruyen todos los chunks.
; - doc_save() escribe chunk por chunk (sin concatenar todo en un buffer).
; - li_rebuild_doc() ya lee via doc_read, por lo que el indice no materializa.
;
; Deuda aceptada (no perfecto): find_in_doc y doc_replace_all materializan el
; documento; el maestro se usa como caché de compatibilidad para llamadores
; que todavia piden tb_data(doc_textbuffer(doc)); los chunks vacios no se
; compactan; doc_reindex sigue siendo O(n) por edicion.

%Document = type { ptr, ptr, ptr, ptr, i64, ptr, i64, i64 }
; { TextBuffer* maestro, LineIndex*, History*,
;   ptr chunks (head), i64 nchunks, ptr mmap_addr, i64 mmap_len, i64 total_len }

declare ptr @tb_create()
declare i32  @tb_insert(ptr, i64, ptr, i64)
declare i32  @tb_delete(ptr, i64, i64)
declare i64  @tb_length(ptr)
declare ptr  @tb_data(ptr)
declare void @tb_destroy(ptr)

declare i32  @fsio_read_file(ptr, ptr, ptr)
declare i32  @fsio_write_file(ptr, ptr, i64)
declare void @fsio_free_buffer(ptr)
declare i32  @fsio_mmap(ptr, ptr, ptr)
declare i32  @fsio_munmap(ptr, i64)

declare ptr @li_create()
declare void @li_destroy(ptr)
declare i32  @li_rebuild(ptr, ptr)
declare i32  @li_rebuild_doc(ptr, ptr)

declare ptr  @hist_create()
declare void @hist_destroy(ptr)
declare i32  @hist_can_undo(ptr)
declare i32  @hist_can_redo(ptr)
declare void @hist_record_insert(ptr, i64, ptr, i64)
declare void @hist_record_delete(ptr, i64, ptr, i64)
declare i32  @histstack_pop(ptr, ptr, ptr, ptr, ptr)
declare void @histstack_push(ptr, i64, i64, ptr, i64)

declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)

declare ptr @chunk_new(ptr, i64, i64)
declare ptr @chunk_new_mmap(ptr, i64, i64)
declare void @chunk_destroy(ptr)
declare ptr @chunk_src(ptr)
declare void @chunk_set_tb(ptr, ptr)
declare ptr @chunk_next(ptr)
declare i64 @chunk_orig_len(ptr)
declare i64 @chunk_delta(ptr)
declare i32 @chunk_is_dirty(ptr)
declare ptr @chunk_tb(ptr)
declare void @chunk_set_len(ptr, i64)
declare void @chunk_set_next(ptr, ptr)
declare i64 @chunk_to_actual(ptr, i64)
declare i64 @chunk_total(ptr)

declare i32 @replace_all(ptr, i64, ptr, ptr, i64, i64, i64, i64, i64, ptr, ptr, ptr, ptr, ptr)
declare void @replace_all_free_results(ptr, ptr, ptr, ptr, i64)
declare i1 @find_bytes_match(ptr, ptr, i64, i32)
; ================= History es un struct opaco {undo_stack,redo_stack};
; document.ll necesita leer sus dos campos para doc_undo/doc_redo. =======
%History = type { ptr, ptr }

; ---------------------------------------------------------------------------
; doc_build_chunks: sobre un mmap de %len bytes, crea chunks de 10000 ZERO-COPY
; (apuntan al mmap, TextBuffer=null, dirty=0) y los enlaza en %doc.
; ---------------------------------------------------------------------------
define internal void @doc_build_chunks(ptr %doc, ptr %addr, i64 %len) {
entry:
  %head = alloca ptr
  store ptr null, ptr %head
  %tail = alloca ptr
  store ptr null, ptr %tail
  %off = alloca i64
  store i64 0, ptr %off
  %cnt = alloca i64
  store i64 0, ptr %cnt
  br label %loop
loop:
  %o = load i64, ptr %off
  %done = icmp sge i64 %o, %len
  br i1 %done, label %finish, label %body
body:
  %rem = sub i64 %len, %o
  %small = icmp slt i64 %rem, 10000
  %clen = select i1 %small, i64 %rem, i64 10000
  %src = getelementptr i8, ptr %addr, i64 %o
  %c = call ptr @chunk_new_mmap(ptr %src, i64 %o, i64 %clen)
  %t = load ptr, ptr %tail
  %tnull = icmp eq ptr %t, null
  br i1 %tnull, label %first, label %append
first:
  store ptr %c, ptr %head
  store ptr %c, ptr %tail
  br label %next
append:
  call void @chunk_set_next(ptr %t, ptr %c)
  store ptr %c, ptr %tail
  br label %next
next:
  %n = load i64, ptr %cnt
  %n1 = add i64 %n, 1
  store i64 %n1, ptr %cnt
  %o1 = add i64 %o, %clen
  store i64 %o1, ptr %off
  br label %loop
finish:
  %h = load ptr, ptr %head
  %hp = getelementptr %Document, ptr %doc, i32 0, i32 3
  store ptr %h, ptr %hp
  %cn = load i64, ptr %cnt
  %cnp = getelementptr %Document, ptr %doc, i32 0, i32 4
  store i64 %cn, ptr %cnp
  ret void
}

; doc_load: lee %path, crea TextBuffer + LineIndex + History, auto-construye
; el índice una vez. Devuelve Document* o null si falla lectura, insert, o
; el rebuild inicial del índice.
; doc_new: Document vacio en memoria, sin archivo ni mmap. Evita que dos
; instancias (o dos tabs "untitled" con distinta ruta) se pisen el /tmp fijo.
define ptr @doc_new() {
entry:
  %tb = call ptr @tb_create()
  %tbn = icmp eq ptr %tb, null
  br i1 %tbn, label %fail_tb, label %make_li
make_li:
  %li = call ptr @li_create()
  %lin = icmp eq ptr %li, null
  br i1 %lin, label %fail_li, label %reindex
reindex:
  %rok = call i32 @li_rebuild(ptr %li, ptr %tb)
  br label %make_hist
make_hist:
  %hist = call ptr @hist_create()
  %hn = icmp eq ptr %hist, null
  br i1 %hn, label %fail_hist, label %alloc
alloc:
  %doc = call ptr @malloc(i64 64)
  %dn = icmp eq ptr %doc, null
  br i1 %dn, label %fail_alloc, label %init
init:
  %f0 = getelementptr %Document, ptr %doc, i32 0, i32 0
  store ptr %tb, ptr %f0
  %f1 = getelementptr %Document, ptr %doc, i32 0, i32 1
  store ptr %li, ptr %f1
  %f2 = getelementptr %Document, ptr %doc, i32 0, i32 2
  store ptr %hist, ptr %f2
  %f3 = getelementptr %Document, ptr %doc, i32 0, i32 3
  store ptr null, ptr %f3
  %f4 = getelementptr %Document, ptr %doc, i32 0, i32 4
  store i64 0, ptr %f4
  %f5 = getelementptr %Document, ptr %doc, i32 0, i32 5
  store ptr null, ptr %f5
  %f6 = getelementptr %Document, ptr %doc, i32 0, i32 6
  store i64 0, ptr %f6
  %f7 = getelementptr %Document, ptr %doc, i32 0, i32 7
  store i64 0, ptr %f7
  ; un chunk vacío y sucio con su PROPIO TB (no compartir el maestro:
  ; doc_destroy libera ambos y eso seria doble-free)
  %ctb0 = call ptr @tb_create()
  %c0 = call ptr @chunk_new(ptr %ctb0, i64 0, i64 0)
  %hp0 = getelementptr %Document, ptr %doc, i32 0, i32 3
  store ptr %c0, ptr %hp0
  %cnp0 = getelementptr %Document, ptr %doc, i32 0, i32 4
  store i64 1, ptr %cnp0
  ret ptr %doc
fail_alloc:
  call void @hist_destroy(ptr %hist)
  br label %fail_hist
fail_hist:
  call void @li_destroy(ptr %li)
  br label %fail_li
fail_li:
  call void @tb_destroy(ptr %tb)
  br label %fail_tb
fail_tb:
  ret ptr null
}

define ptr @doc_load(ptr %path) {
entry:
  %out_data = alloca ptr
  %out_len  = alloca i64
  %read_ok = call i32 @fsio_read_file(ptr %path, ptr %out_data, ptr %out_len)
  %read_ok_b = icmp eq i32 %read_ok, 1
  br i1 %read_ok_b, label %make_buffer, label %fail_noalloc

make_buffer:
  %tb = call ptr @tb_create()          ; maestro VACIO (compatibilidad)
  %fdata = load ptr, ptr %out_data
  call void @fsio_free_buffer(ptr %fdata)
  br label %make_index

make_index:
  %li = call ptr @li_create()
  %hist = call ptr @hist_create()
  br label %make_doc

make_doc:
  %doc = call ptr @malloc(i64 64)
  ; { ptr,ptr,ptr,ptr,i64,ptr,i64,i64 } = 64
  %tb_field = getelementptr %Document, ptr %doc, i32 0, i32 0
  store ptr %tb, ptr %tb_field
  %li_field = getelementptr %Document, ptr %doc, i32 0, i32 1
  store ptr %li, ptr %li_field
  %hist_field = getelementptr %Document, ptr %doc, i32 0, i32 2
  store ptr %hist, ptr %hist_field
  ; --- mmap + chunks (campos 3..7) ---
  %ma = alloca ptr
  store ptr null, ptr %ma
  %ml = alloca i64
  store i64 0, ptr %ml
  %mok = call i32 @fsio_mmap(ptr %path, ptr %ma, ptr %ml)
  %mokb = icmp eq i32 %mok, 1
  br i1 %mokb, label %mmap_ok, label %init_chunks_empty
mmap_ok:
  %ma_v = load ptr, ptr %ma
  %ml_v = load i64, ptr %ml
  %has_data = icmp sgt i64 %ml_v, 0
  br i1 %has_data, label %do_chunks, label %init_chunks_empty
do_chunks:
  call void @doc_build_chunks(ptr %doc, ptr %ma_v, i64 %ml_v)
  br label %store_map
init_chunks_empty:
  %hp0 = getelementptr %Document, ptr %doc, i32 0, i32 3
  store ptr null, ptr %hp0
  %cnp0 = getelementptr %Document, ptr %doc, i32 0, i32 4
  store i64 0, ptr %cnp0
  ; archivo vacío: un chunk vacío sucio con su propio TB
  %ctbe = call ptr @tb_create()
  %cempty = call ptr @chunk_new(ptr %ctbe, i64 0, i64 0)
  store ptr %cempty, ptr %hp0
  store i64 1, ptr %cnp0
  br label %store_map
store_map:
  %ma_f = load ptr, ptr %ma
  %ml_f = load i64, ptr %ml
  %map_p = getelementptr %Document, ptr %doc, i32 0, i32 5
  store ptr %ma_f, ptr %map_p
  %maplen_p = getelementptr %Document, ptr %doc, i32 0, i32 6
  store i64 %ml_f, ptr %maplen_p
  %tot_p = getelementptr %Document, ptr %doc, i32 0, i32 7
  store i64 %ml_f, ptr %tot_p
  ; indice sobre el contenido del Document (lee via doc_read, no materializa)
  %rok = call i32 @li_rebuild_doc(ptr %li, ptr %doc)
  ret ptr %doc

fail_after_index:
  call void @li_destroy(ptr %li)
  call void @tb_destroy(ptr %tb)
  ret ptr null

fail_after_tb:
  %fdata2 = load ptr, ptr %out_data
  call void @fsio_free_buffer(ptr %fdata2)
  call void @tb_destroy(ptr %tb)
  ret ptr null

fail_noalloc:
  ret ptr null
}

; doc_save: escribe chunk por chunk SIN concatenar el documento en memoria.
; Cada chunk limpio se lee directo del mmap; el sucio desde su TextBuffer.
define i32 @doc_save(ptr %doc, ptr %path) {
entry:
  ; crear/vaciar archivo destino
  %init = call i32 @fsio_write_file(ptr %path, ptr null, i64 0)
  %init_ok = icmp eq i32 %init, 1
  br i1 %init_ok, label %open, label %fail
open:
  %fd = call i32 @fsio_open_append(ptr %path)
  %fd_ok = icmp sge i32 %fd, 0
  br i1 %fd_ok, label %fill, label %fail
fill:
  %headp = getelementptr %Document, ptr %doc, i32 0, i32 3
  %head = load ptr, ptr %headp
  %cur = alloca ptr
  store ptr %head, ptr %cur
  br label %loop
loop:
  %c = load ptr, ptr %cur
  %cn = icmp eq ptr %c, null
  br i1 %cn, label %write_done, label %body
body:
  %dirty = call i32 @chunk_is_dirty(ptr %c)
  %is = icmp ne i32 %dirty, 0
  br i1 %is, label %from_tb, label %from_src
from_tb:
  %ctb = call ptr @chunk_tb(ptr %c)
  %clen = call i64 @tb_length(ptr %ctb)
  %cdata = call ptr @tb_data(ptr %ctb)
  br label %write_chunk
from_src:
  %src = call ptr @chunk_src(ptr %c)
  %olen = call i64 @chunk_orig_len(ptr %c)
  %d = call i64 @chunk_delta(ptr %c)
  %clen2 = add i64 %olen, %d
  br label %write_chunk_src
write_chunk:
  %okc = call i32 @fsio_write_fd(i32 %fd, ptr %cdata, i64 %clen)
  br label %advance
write_chunk_src:
  %okc2 = call i32 @fsio_write_fd(i32 %fd, ptr %src, i64 %clen2)
  br label %advance
advance:
  %nx = call ptr @chunk_next(ptr %c)
  store ptr %nx, ptr %cur
  br label %loop
write_done:
  %close = call i32 @fsio_close_fd(i32 %fd)
  ret i32 1
fail:
  ret i32 0
}

declare i32 @fsio_open_append(ptr)
declare i32 @fsio_write_fd(i32, ptr, i64)
declare i32 @fsio_close_fd(i32)

; doc_length: largo total del documento (offset actual).
define i64 @doc_length(ptr %doc) {
entry:
  %p = getelementptr %Document, ptr %doc, i32 0, i32 7
  %v = load i64, ptr %p
  ret i64 %v
}

; sincroniza el Document tras una edicion sobre el maestro:
;  - total_len
;  - los chunks (se reconstruyen desde el maestro)
; O(n) por edicion -- pendiente de optimizar con delta incremental en chunks.
; Por ahora garantiza que doc_read (que lee chunks) vea los edits.
define internal void @doc_sync_len(ptr %doc) {
entry:
  ; total_len = suma de longitudes actuales de los chunks. O(#chunks),
  ; pero NO destruye ni reconstruye: las ediciones ya ajustaron cada delta.
  %hp = getelementptr %Document, ptr %doc, i32 0, i32 3
  %head = load ptr, ptr %hp
  %total = call i64 @chunk_total(ptr %head)
  %lp = getelementptr %Document, ptr %doc, i32 0, i32 7
  store i64 %total, ptr %lp
  ret void
}

; doc_ensure_cow: si el chunk es limpio (apunta al mmap), copia su porcion a
; un TextBuffer privado y lo marca sucio. Los editables posteriores van ahi.
define internal ptr @doc_ensure_cow(ptr %c) {
entry:
  %dirty = call i32 @chunk_is_dirty(ptr %c)
  %is = icmp ne i32 %dirty, 0
  br i1 %is, label %have, label %copy
have:
  %tb0 = call ptr @chunk_tb(ptr %c)
  ret ptr %tb0
copy:
  %src = call ptr @chunk_src(ptr %c)
  %olen = call i64 @chunk_orig_len(ptr %c)
  %d = call i64 @chunk_delta(ptr %c)
  %clen = add i64 %olen, %d
  %tb = call ptr @tb_create()
  %ok = call i32 @tb_insert(ptr %tb, i64 0, ptr %src, i64 %clen)
  call void @chunk_set_tb(ptr %c, ptr %tb)
  ret ptr %tb
}

; doc_locate: encuentra el chunk que contiene el offset ACTUAL %pos.
; Escribe en %out_chunk, %out_local (offset dentro del chunk) y %out_acc
; (offset actual donde empieza el chunk). Si %pos == total, devuelve el
; ultimo chunk con local == su longitud.
define internal void @doc_locate(ptr %doc, i64 %pos,
                                 ptr %out_chunk, ptr %out_local, ptr %out_acc) {
entry:
  %hp = getelementptr %Document, ptr %doc, i32 0, i32 3
  %head = load ptr, ptr %hp
  %acc = alloca i64
  store i64 0, ptr %acc
  %cur = alloca ptr
  store ptr %head, ptr %cur
  br label %loop
loop:
  %c = load ptr, ptr %cur
  %null = icmp eq ptr %c, null
  br i1 %null, label %notfound, label %body
body:
  %olen = call i64 @chunk_orig_len(ptr %c)
  %d = call i64 @chunk_delta(ptr %c)
  %clen = add i64 %olen, %d
  %a = load i64, ptr %acc
  %end = add i64 %a, %clen
  %nx = call ptr @chunk_next(ptr %c)
  %last = icmp eq ptr %nx, null
  %ge = icmp sge i64 %pos, %a
  %lt = icmp slt i64 %pos, %end
  %inside = and i1 %ge, %lt
  %at_end = icmp eq i64 %pos, %end
  %take = or i1 %inside, %at_end
  br i1 %take, label %found, label %advance
advance:
  store i64 %end, ptr %acc
  store ptr %nx, ptr %cur
  br label %loop
found:
  %local0 = sub i64 %pos, %a
  store ptr %c, ptr %out_chunk
  store i64 %local0, ptr %out_local
  store i64 %a, ptr %out_acc
  ret void
notfound:
  store ptr null, ptr %out_chunk
  store i64 0, ptr %out_local
  store i64 0, ptr %out_acc
  ret void
}

; ---------------------------------------------------------------------------
; doc_read: copia hasta %len bytes desde el offset actual %off hasta %out.
; Los chunks limpios se leen directo del mmap; los sucios desde su TB privado.
; ---------------------------------------------------------------------------
define i64 @doc_read(ptr %doc, i64 %off, i64 %len, ptr %out) {
entry:
  %zero_len = icmp sle i64 %len, 0
  br i1 %zero_len, label %zero, label %multi_init
zero:
  ret i64 0
multi_init:
  %done = alloca i64
  store i64 0, ptr %done
  %headp = getelementptr %Document, ptr %doc, i32 0, i32 3
  %head = load ptr, ptr %headp
  br label %outer
outer:
  %d = load i64, ptr %done
  %finished = icmp sge i64 %d, %len
  br i1 %finished, label %ok, label %find_init
find_init:
  %acc = alloca i64
  store i64 0, ptr %acc
  %cur = alloca ptr
  store ptr %head, ptr %cur
  br label %find_loop
find_loop:
  %c = load ptr, ptr %cur
  %cn = icmp eq ptr %c, null
  br i1 %cn, label %fail, label %find_body
find_body:
  %olen = call i64 @chunk_orig_len(ptr %c)
  %delt = call i64 @chunk_delta(ptr %c)
  %clen = add i64 %olen, %delt
  %a = load i64, ptr %acc
  %cend = add i64 %a, %clen
  %pos = add i64 %off, %d
  %ge = icmp sge i64 %pos, %a
  %lt = icmp slt i64 %pos, %cend
  %inside = and i1 %ge, %lt
  br i1 %inside, label %do_copy, label %next_chunk
next_chunk:
  store i64 %cend, ptr %acc
  %nx = call ptr @chunk_next(ptr %c)
  store ptr %nx, ptr %cur
  br label %find_loop
do_copy:
  %local = sub i64 %pos, %a
  %rem = sub i64 %clen, %local
  %want = sub i64 %len, %d
  %rem_lt = icmp slt i64 %rem, %want
  %take_m = select i1 %rem_lt, i64 %rem, i64 %want
  %dirty_c = call i32 @chunk_is_dirty(ptr %c)
  %is_d = icmp ne i32 %dirty_c, 0
  br i1 %is_d, label %from_tb, label %from_mmap
from_tb:
  %tb_c = call ptr @chunk_tb(ptr %c)
  %data_tb = call ptr @tb_data(ptr %tb_c)
  br label %have_src
from_mmap:
  %data_mm = call ptr @chunk_src(ptr %c)
  br label %have_src
have_src:
  %data_c = phi ptr [ %data_tb, %from_tb ], [ %data_mm, %from_mmap ]
  %srcc = getelementptr i8, ptr %data_c, i64 %local
  %dstc = getelementptr i8, ptr %out, i64 %d
  %rc = call ptr @memcpy(ptr %dstc, ptr %srcc, i64 %take_m)
  %d2 = add i64 %d, %take_m
  store i64 %d2, ptr %done
  br label %outer
ok:
  %rd = load i64, ptr %done
  ret i64 %rd
fail:
  %rd2 = load i64, ptr %done
  ret i64 %rd2
}

; ---------------------------------------------------------------------------
; find_in_doc: busqueda literal sobre el Document (multi-chunk), via doc_read.
; POC: materializa el documento una vez con doc_read (igual que li_rebuild_doc
; hacia antes) y reutiliza find_bytes_match de find.ll. Devuelve 1 si encontro
; y escribe [out_start,out_end); 0 si no.
; forward != 0 = adelante con wraparound; == 0 = atras.
; ---------------------------------------------------------------------------
define i32 @find_in_doc(ptr %doc, ptr %needle, i64 %nlen, i64 %from,
                         i32 %forward, i32 %match_case,
                         ptr %out_start, ptr %out_end) {
entry:
  %len = call i64 @doc_length(ptr %doc)
  %nempty = icmp eq i64 %nlen, 0
  %toobig = icmp ugt i64 %nlen, %len
  %bad = or i1 %nempty, %toobig
  br i1 %bad, label %no, label %alloc
alloc:
  %buf = call ptr @malloc(i64 %len)
  %null = icmp eq ptr %buf, null
  br i1 %null, label %no, label %read
read:
  %got = call i64 @doc_read(ptr %doc, i64 0, i64 %len, ptr %buf)
  %fwd = icmp ne i32 %forward, 0
  br i1 %fwd, label %fw1_setup, label %bw1_setup

; ---- forward fase 1: [from, maxs] ----
fw1_setup:
  %maxs = sub i64 %got, %nlen
  %frombig = icmp ugt i64 %from, %maxs
  %s1 = select i1 %frombig, i64 0, i64 %from
  br label %fw1_loop
fw1_loop:
  %p1 = phi i64 [ %s1, %fw1_setup ], [ %p1next, %fw1_next ]
  %done1 = icmp ugt i64 %p1, %maxs
  br i1 %done1, label %fw2_setup, label %fw1_check
fw1_check:
  %hp1 = getelementptr i8, ptr %buf, i64 %p1
  %m1 = call i1 @find_bytes_match(ptr %hp1, ptr %needle, i64 %nlen, i32 %match_case)
  br i1 %m1, label %found, label %fw1_next
fw1_next:
  %p1next = add i64 %p1, 1
  br label %fw1_loop

; ---- forward fase 2: [0, from-1] (wrap) ----
fw2_setup:
  %fromzero = icmp eq i64 %from, 0
  br i1 %fromzero, label %no_cleanup, label %fw2_loop
fw2_loop:
  %p2 = phi i64 [ 0, %fw2_setup ], [ %p2next, %fw2_next ]
  %done2 = icmp sge i64 %p2, %from
  br i1 %done2, label %no_cleanup, label %fw2_check
fw2_check:
  %hp2 = getelementptr i8, ptr %buf, i64 %p2
  %m2 = call i1 @find_bytes_match(ptr %hp2, ptr %needle, i64 %nlen, i32 %match_case)
  br i1 %m2, label %found2, label %fw2_next
fw2_next:
  %p2next = add i64 %p2, 1
  br label %fw2_loop

; ---- backward fase 1: [from, 0] ----
bw1_setup:
  %maxs_b = sub i64 %got, %nlen
  %frombig_b = icmp ugt i64 %from, %maxs_b
  %s1_b = select i1 %frombig_b, i64 %maxs_b, i64 %from
  br label %bw1_loop
bw1_loop:
  %pb1 = phi i64 [ %s1_b, %bw1_setup ], [ %pb1next, %bw1_next ]
  %hp1b = getelementptr i8, ptr %buf, i64 %pb1
  %mb1 = call i1 @find_bytes_match(ptr %hp1b, ptr %needle, i64 %nlen, i32 %match_case)
  br i1 %mb1, label %found_b, label %bw1_check0
bw1_check0:
  %iszero = icmp eq i64 %pb1, 0
  br i1 %iszero, label %bw2_setup, label %bw1_next
bw1_next:
  %pb1next = sub i64 %pb1, 1
  br label %bw1_loop

; ---- backward fase 2: [maxs, from+1] (wrap) ----
bw2_setup:
  %frommax = icmp sge i64 %from, %maxs_b
  br i1 %frommax, label %no_cleanup, label %bw2_loop
bw2_loop:
  %pb2 = phi i64 [ %maxs_b, %bw2_setup ], [ %pb2next, %bw2_next ]
  %doneb2 = icmp sle i64 %pb2, %from
  br i1 %doneb2, label %no_cleanup, label %bw2_check
bw2_check:
  %hp2b = getelementptr i8, ptr %buf, i64 %pb2
  %mb2 = call i1 @find_bytes_match(ptr %hp2b, ptr %needle, i64 %nlen, i32 %match_case)
  br i1 %mb2, label %found_b2, label %bw2_next
bw2_next:
  %pb2next = sub i64 %pb2, 1
  br label %bw2_loop

found:
  %sf = phi i64 [ %p1, %fw1_check ]
  store i64 %sf, ptr %out_start
  %ef = add i64 %sf, %nlen
  store i64 %ef, ptr %out_end
  call void @free(ptr %buf)
  ret i32 1
found2:
  %sf2 = phi i64 [ %p2, %fw2_check ]
  store i64 %sf2, ptr %out_start
  %ef2 = add i64 %sf2, %nlen
  store i64 %ef2, ptr %out_end
  call void @free(ptr %buf)
  ret i32 1
found_b:
  %sbf = phi i64 [ %pb1, %bw1_loop ]
  store i64 %sbf, ptr %out_start
  %ebf = add i64 %sbf, %nlen
  store i64 %ebf, ptr %out_end
  call void @free(ptr %buf)
  ret i32 1
found_b2:
  %sbf2 = phi i64 [ %pb2, %bw2_check ]
  store i64 %sbf2, ptr %out_start
  %ebf2 = add i64 %sbf2, %nlen
  store i64 %ebf2, ptr %out_end
  call void @free(ptr %buf)
  ret i32 1
no_cleanup:
  call void @free(ptr %buf)
  ret i32 0
no:
  ret i32 0
}

define i32 @doc_reindex(ptr %doc) {
entry:
  %tb_field = getelementptr %Document, ptr %doc, i32 0, i32 0
  %tb = load ptr, ptr %tb_field
  %li_field = getelementptr %Document, ptr %doc, i32 0, i32 1
  %li = load ptr, ptr %li_field
  %ok = call i32 @li_rebuild_doc(ptr %li, ptr %doc)
  ret i32 %ok
}

define ptr @doc_textbuffer(ptr %doc) {
entry:
  %tb_field = getelementptr %Document, ptr %doc, i32 0, i32 0
  %tb = load ptr, ptr %tb_field
  ret ptr %tb
}

define ptr @doc_lineindex(ptr %doc) {
entry:
  %li_field = getelementptr %Document, ptr %doc, i32 0, i32 1
  %li = load ptr, ptr %li_field
  ret ptr %li
}

define void @doc_destroy(ptr %doc) {
entry:
  ; liberar lista de chunks (cada uno destruye su TextBuffer)
  %hp = getelementptr %Document, ptr %doc, i32 0, i32 3
  %head = load ptr, ptr %hp
  br label %chunk_loop
chunk_loop:
  %c = phi ptr [ %head, %entry ], [ %cnx, %destroy_one ]
  %isnull = icmp eq ptr %c, null
  br i1 %isnull, label %destroy_chunks_done, label %destroy_one
destroy_one:
  ; chunk_destroy ya libera el TB solo si está sucio
  %cnx = call ptr @chunk_next(ptr %c)
  call void @chunk_destroy(ptr %c)
  br label %chunk_loop
destroy_chunks_done:
  ; desmapear
  %map_p = getelementptr %Document, ptr %doc, i32 0, i32 5
  %addr = load ptr, ptr %map_p
  %maplen_p = getelementptr %Document, ptr %doc, i32 0, i32 6
  %mlen = load i64, ptr %maplen_p
  %has_map = icmp ne ptr %addr, null
  br i1 %has_map, label %do_unmap, label %after_unmap
do_unmap:
  %urc = call i32 @fsio_munmap(ptr %addr, i64 %mlen)
  br label %after_unmap
after_unmap:
  %tb_field = getelementptr %Document, ptr %doc, i32 0, i32 0
  %tb = load ptr, ptr %tb_field
  call void @tb_destroy(ptr %tb)
  %li_field = getelementptr %Document, ptr %doc, i32 0, i32 1
  %li = load ptr, ptr %li_field
  call void @li_destroy(ptr %li)
  %hist_field = getelementptr %Document, ptr %doc, i32 0, i32 2
  %hist = load ptr, ptr %hist_field
  call void @hist_destroy(ptr %hist)
  call void @free(ptr %doc)
  ret void
}

; ================= edición con historial =================
; Reemplazan a tb_insert/tb_delete directo cuando se edita un Document --
; gui/ debería llamar SIEMPRE estas, nunca tb_insert/tb_delete sobre
; doc_textbuffer(doc) directo, o el historial queda inconsistente.

define i32 @doc_insert(ptr %doc, i64 %pos, ptr %src, i64 %srclen) {
entry:
  %chunk = alloca ptr
  %local = alloca i64
  %acc = alloca i64
  call void @doc_locate(ptr %doc, i64 %pos, ptr %chunk, ptr %local, ptr %acc)
  %c = load ptr, ptr %chunk
  %null = icmp eq ptr %c, null
  br i1 %null, label %fail, label %cow
cow:
  %l = load i64, ptr %local
  %tb = call ptr @doc_ensure_cow(ptr %c)
  %ok = call i32 @tb_insert(ptr %tb, i64 %l, ptr %src, i64 %srclen)
  %ok_b = icmp eq i32 %ok, 1
  br i1 %ok_b, label %record, label %fail
record:
  %d = call i64 @chunk_delta(ptr %c)
  %d2 = add i64 %d, %srclen
  call void @chunk_set_delta(ptr %c, i64 %d2)
  %hist_field = getelementptr %Document, ptr %doc, i32 0, i32 2
  %hist = load ptr, ptr %hist_field
  call void @hist_record_insert(ptr %hist, i64 %pos, ptr %src, i64 %srclen)
  call void @doc_sync_len(ptr %doc)
  ret i32 1
fail:
  ret i32 0
}

define i32 @doc_delete(ptr %doc, i64 %pos, i64 %dellen) {
entry:
  ; se leen los bytes a borrar ANTES de modificar (el historial los copia)
  %tmp = call ptr @malloc(i64 %dellen)
  %null = icmp eq ptr %tmp, null
  br i1 %null, label %fail, label %read
read:
  %got = call i64 @doc_read(ptr %doc, i64 %pos, i64 %dellen, ptr %tmp)
  %chunk = alloca ptr
  %local = alloca i64
  %acc = alloca i64
  call void @doc_locate(ptr %doc, i64 %pos, ptr %chunk, ptr %local, ptr %acc)
  %c = load ptr, ptr %chunk
  %cn = icmp eq ptr %c, null
  br i1 %cn, label %fail_free, label %cow
cow:
  %l = load i64, ptr %local
  %tb = call ptr @doc_ensure_cow(ptr %c)
  %ok = call i32 @tb_delete(ptr %tb, i64 %l, i64 %got)
  %ok_b = icmp eq i32 %ok, 1
  br i1 %ok_b, label %record, label %fail_free
record:
  %d = call i64 @chunk_delta(ptr %c)
  %d2 = sub i64 %d, %got
  call void @chunk_set_delta(ptr %c, i64 %d2)
  %hist_field = getelementptr %Document, ptr %doc, i32 0, i32 2
  %hist = load ptr, ptr %hist_field
  call void @hist_record_delete(ptr %hist, i64 %pos, ptr %tmp, i64 %got)
  call void @free(ptr %tmp)
  call void @doc_sync_len(ptr %doc)
  ret i32 1
fail_free:
  call void @free(ptr %tmp)
  ret i32 0
fail:
  ret i32 0
}

declare void @chunk_set_delta(ptr, i64)

; --- edición sin historial (para undo/redo): mismosCOW por chunk ---
define i32 @doc_insert_raw(ptr %doc, i64 %pos, ptr %src, i64 %srclen) {
entry:
  %chunk = alloca ptr
  %local = alloca i64
  %acc = alloca i64
  call void @doc_locate(ptr %doc, i64 %pos, ptr %chunk, ptr %local, ptr %acc)
  %c = load ptr, ptr %chunk
  %null = icmp eq ptr %c, null
  br i1 %null, label %fail, label %cow
cow:
  %l = load i64, ptr %local
  %tb = call ptr @doc_ensure_cow(ptr %c)
  %ok = call i32 @tb_insert(ptr %tb, i64 %l, ptr %src, i64 %srclen)
  %ok_b = icmp eq i32 %ok, 1
  br i1 %ok_b, label %upd, label %fail
upd:
  %d = call i64 @chunk_delta(ptr %c)
  %d2 = add i64 %d, %srclen
  call void @chunk_set_delta(ptr %c, i64 %d2)
  call void @doc_sync_len(ptr %doc)
  ret i32 1
fail:
  ret i32 0
}

define i32 @doc_delete_raw(ptr %doc, i64 %pos, i64 %dellen) {
entry:
  %chunk = alloca ptr
  %local = alloca i64
  %acc = alloca i64
  call void @doc_locate(ptr %doc, i64 %pos, ptr %chunk, ptr %local, ptr %acc)
  %c = load ptr, ptr %chunk
  %null = icmp eq ptr %c, null
  br i1 %null, label %fail, label %cow
cow:
  %l = load i64, ptr %local
  %tb = call ptr @doc_ensure_cow(ptr %c)
  %ok = call i32 @tb_delete(ptr %tb, i64 %l, i64 %dellen)
  %ok_b = icmp eq i32 %ok, 1
  br i1 %ok_b, label %upd, label %fail
upd:
  %d = call i64 @chunk_delta(ptr %c)
  %d2 = sub i64 %d, %dellen
  call void @chunk_set_delta(ptr %c, i64 %d2)
  call void @doc_sync_len(ptr %doc)
  ret i32 1
fail:
  ret i32 0
}

define i32 @doc_can_undo(ptr %doc) {
entry:
  %hist_field = getelementptr %Document, ptr %doc, i32 0, i32 2
  %hist = load ptr, ptr %hist_field
  %r = call i32 @hist_can_undo(ptr %hist)
  ret i32 %r
}

define i32 @doc_can_redo(ptr %doc) {
entry:
  %hist_field = getelementptr %Document, ptr %doc, i32 0, i32 2
  %hist = load ptr, ptr %hist_field
  %r = call i32 @hist_can_redo(ptr %hist)
  ret i32 %r
}

define i32 @doc_undo(ptr %doc) {
entry:
  %hist_field = getelementptr %Document, ptr %doc, i32 0, i32 2
  %hist = load ptr, ptr %hist_field
  %u_ptr = getelementptr %History, ptr %hist, i32 0, i32 0
  %undo = load ptr, ptr %u_ptr

  %ok_kind = alloca i64
  %ok_pos = alloca i64
  %ok_data = alloca ptr
  %ok_len = alloca i64
  %popped = call i32 @histstack_pop(ptr %undo, ptr %ok_kind, ptr %ok_pos, ptr %ok_data, ptr %ok_len)
  %popped_b = icmp eq i32 %popped, 1
  br i1 %popped_b, label %do_undo, label %ret_fail

do_undo:
  %kind = load i64, ptr %ok_kind
  %pos = load i64, ptr %ok_pos
  %data = load ptr, ptr %ok_data
  %len = load i64, ptr %ok_len

  %is_insert = icmp eq i64 %kind, 0
  br i1 %is_insert, label %undo_insert, label %undo_delete

undo_insert:
  %del_ok = call i32 @doc_delete_raw(ptr %doc, i64 %pos, i64 %len)
  br label %push_redo

undo_delete:
  %ins_ok = call i32 @doc_insert_raw(ptr %doc, i64 %pos, ptr %data, i64 %len)
  br label %push_redo

push_redo:
  %r_ptr = getelementptr %History, ptr %hist, i32 0, i32 1
  %redo = load ptr, ptr %r_ptr
  call void @histstack_push(ptr %redo, i64 %kind, i64 %pos, ptr %data, i64 %len)
  call void @doc_sync_len(ptr %doc)
  ret i32 1

ret_fail:
  ret i32 0
}

define i32 @doc_redo(ptr %doc) {
entry:
  %hist_field = getelementptr %Document, ptr %doc, i32 0, i32 2
  %hist = load ptr, ptr %hist_field
  %r_ptr = getelementptr %History, ptr %hist, i32 0, i32 1
  %redo = load ptr, ptr %r_ptr

  %ok_kind = alloca i64
  %ok_pos = alloca i64
  %ok_data = alloca ptr
  %ok_len = alloca i64
  %popped = call i32 @histstack_pop(ptr %redo, ptr %ok_kind, ptr %ok_pos, ptr %ok_data, ptr %ok_len)
  %popped_b = icmp eq i32 %popped, 1
  br i1 %popped_b, label %do_redo, label %ret_fail

do_redo:
  %kind = load i64, ptr %ok_kind
  %pos = load i64, ptr %ok_pos
  %data = load ptr, ptr %ok_data
  %len = load i64, ptr %ok_len

  %is_insert = icmp eq i64 %kind, 0
  br i1 %is_insert, label %redo_insert, label %redo_delete

redo_insert:
  %ins2 = call i32 @doc_insert_raw(ptr %doc, i64 %pos, ptr %data, i64 %len)
  br label %push_undo

redo_delete:
  %del2 = call i32 @doc_delete_raw(ptr %doc, i64 %pos, i64 %len)
  br label %push_undo

push_undo:
  %u_ptr = getelementptr %History, ptr %hist, i32 0, i32 0
  %undo = load ptr, ptr %u_ptr
  call void @histstack_push(ptr %undo, i64 %kind, i64 %pos, ptr %data, i64 %len)
  call void @doc_sync_len(ptr %doc)
  ret i32 1

ret_fail:
  ret i32 0
}
; doc_replace_all: aplica replace_all (regex/replace.ll) sobre el
; contenido del documento (materializado via doc_read), en el rango
; [scan_start, scan_end) con [core_start, core_end) como zona comiteable
; (ver chunk_plan.ll para cómo se calculan esos 4 offsets -- acá se reciben
; ya resueltos, este archivo no sabe de líneas ni de chunking)
; Aplica los matches encontrados de ATRÁS PARA ADELANTE (mayor %start
; primero) via doc_delete/doc_insert -- así cada edición no invalida los
; offsets de los matches que todavía faltan aplicar, sin necesidad de
; llevar un delta acumulado.
; Devuelve la cantidad de reemplazos aplicados, o -1 si %prog es null
; (replace_all devolvió 0).


define i64 @doc_replace_all(ptr %doc, ptr %prog,ptr %replacement_template, i64 %replacement_len,i64 %core_start, i64 %core_end,i64 %scan_start, i64 %scan_end) {
entry:
  %prog_null = icmp eq ptr %prog, null
  br i1 %prog_null, label %fail_null, label %setup

setup:
  ; Deuda aceptada: materializa el documento via doc_read (el maestro esta
  ; vacio en cargas lazy). Los resultados se aplican luego con doc_delete /
  ; doc_insert sobre los chunks.
  %text_len = call i64 @doc_length(ptr %doc)
  %text = call ptr @malloc(i64 %text_len)
  %got = call i64 @doc_read(ptr %doc, i64 0, i64 %text_len, ptr %text)

  %starts_slot = alloca ptr
  %ends_slot = alloca ptr
  %repls_slot = alloca ptr
  %repl_lens_slot = alloca ptr
  %count_slot = alloca i64
  store ptr null, ptr %starts_slot
  store ptr null, ptr %ends_slot
  store ptr null, ptr %repls_slot
  store ptr null, ptr %repl_lens_slot
  store i64 0, ptr %count_slot

  %rc = call i32 @replace_all(ptr %text, i64 %text_len, ptr %prog,
                               ptr %replacement_template, i64 %replacement_len,
                               i64 %core_start, i64 %core_end,
                               i64 %scan_start, i64 %scan_end,
                               ptr %starts_slot, ptr %ends_slot,
                               ptr %repls_slot, ptr %repl_lens_slot,
                               ptr %count_slot)
  %rc_ok = icmp eq i32 %rc, 1
  br i1 %rc_ok, label %apply, label %fail

apply:
  %starts = load ptr, ptr %starts_slot
  %ends = load ptr, ptr %ends_slot
  %repls = load ptr, ptr %repls_slot
  %repl_lens = load ptr, ptr %repl_lens_slot
  %count = load i64, ptr %count_slot

  %start_i = sub i64 %count, 1
  br label %apply_loop

apply_loop:
  %i = phi i64 [ %start_i, %apply ], [ %i_next, %apply_body ]
  %more = icmp sge i64 %i, 0
  br i1 %more, label %apply_body, label %apply_done

apply_body:
  %s_slot = getelementptr i64, ptr %starts, i64 %i
  %e_slot = getelementptr i64, ptr %ends, i64 %i
  %r_slot = getelementptr ptr, ptr %repls, i64 %i
  %rl_slot = getelementptr i64, ptr %repl_lens, i64 %i
  %match_start = load i64, ptr %s_slot
  %match_end = load i64, ptr %e_slot
  %repl = load ptr, ptr %r_slot
  %repl_len = load i64, ptr %rl_slot
  %match_len = sub i64 %match_end, %match_start

  %del_ok = call i32 @doc_delete(ptr %doc, i64 %match_start, i64 %match_len)
  %ins_ok = call i32 @doc_insert(ptr %doc, i64 %match_start, ptr %repl, i64 %repl_len)

  %i_next = sub i64 %i, 1
  br label %apply_loop

apply_done:
  call void @replace_all_free_results(ptr %starts, ptr %ends, ptr %repls, ptr %repl_lens, i64 %count)
  call void @free(ptr %text)
  ret i64 %count

fail:
  call void @free(ptr %text)
  ret i64 -1

fail_null:
  ret i64 -1
}
