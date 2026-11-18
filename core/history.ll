; core/history.ll — undo/redo por comandos invertibles, con coalescing y
; cap de 30 entradas por pila. No sabe qué es un "documento" -- opera
; sobre pos/data/len crudos, document.ll es quien la conecta con
; TextBuffer real via doc_insert/doc_delete/doc_undo/doc_redo.

declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare ptr @memmove(ptr, ptr, i64)

; kind: 0=INSERT 1=DELETE
%HistEntry = type { i64, i64, ptr, i64 }  ; kind, pos, data, len
%HistStack = type { ptr, i64 }            ; entries (array fijo de 30), count
%History   = type { ptr, ptr }            ; undo_stack, redo_stack

; ================= HistStack =================

define ptr @histstack_create() {
entry:
  %entries = call ptr @malloc(i64 960)   ; 30 * sizeof(HistEntry=32)
  %st = call ptr @malloc(i64 16)
  %e_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 0
  store ptr %entries, ptr %e_ptr
  %c_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 1
  store i64 0, ptr %c_ptr
  ret ptr %st
}

define void @histstack_clear(ptr %st) {
entry:
  %c_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 1
  %count = load i64, ptr %c_ptr
  %e_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %e_ptr
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %body ]
  %cond = icmp slt i64 %i, %count
  br i1 %cond, label %body, label %done

body:
  %ent_ptr = getelementptr %HistEntry, ptr %entries, i64 %i
  %d_ptr = getelementptr %HistEntry, ptr %ent_ptr, i32 0, i32 2
  %d = load ptr, ptr %d_ptr
  call void @free(ptr %d)
  %i_next = add i64 %i, 1
  br label %loop

done:
  store i64 0, ptr %c_ptr
  ret void
}

define void @histstack_destroy(ptr %st) {
entry:
  call void @histstack_clear(ptr %st)
  %e_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %e_ptr
  call void @free(ptr %entries)
  call void @free(ptr %st)
  ret void
}

define i32 @histstack_count(ptr %st) {
entry:
  %c_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 1
  %count = load i64, ptr %c_ptr
  %r = trunc i64 %count to i32
  ret i32 %r
}

; push: %data pasa a ser propiedad del stack (se libera con free() cuando
; se descarta por evict o por histstack_clear). El caller debe pasar un
; puntero malloc'd propio, nunca un borrowed pointer.
define void @histstack_push(ptr %st, i64 %kind, i64 %pos, ptr %data, i64 %len) {
entry:
  %c_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 1
  %count = load i64, ptr %c_ptr
  %e_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %e_ptr
  %is_full = icmp sge i64 %count, 30
  br i1 %is_full, label %evict, label %write

evict:
  %first_ptr = getelementptr %HistEntry, ptr %entries, i64 0
  %fd_ptr = getelementptr %HistEntry, ptr %first_ptr, i32 0, i32 2
  %fd = load ptr, ptr %fd_ptr
  call void @free(ptr %fd)
  %src = getelementptr %HistEntry, ptr %entries, i64 1
  call ptr @memmove(ptr %entries, ptr %src, i64 928)   ; 29 * 32
  br label %write

write:
  %write_count = phi i64 [ 29, %evict ], [ %count, %entry ]
  %slot_ptr = getelementptr %HistEntry, ptr %entries, i64 %write_count
  %k_ptr = getelementptr %HistEntry, ptr %slot_ptr, i32 0, i32 0
  store i64 %kind, ptr %k_ptr
  %p_ptr = getelementptr %HistEntry, ptr %slot_ptr, i32 0, i32 1
  store i64 %pos, ptr %p_ptr
  %d_ptr2 = getelementptr %HistEntry, ptr %slot_ptr, i32 0, i32 2
  store ptr %data, ptr %d_ptr2
  %l_ptr = getelementptr %HistEntry, ptr %slot_ptr, i32 0, i32 3
  store i64 %len, ptr %l_ptr
  %new_count = add i64 %write_count, 1
  store i64 %new_count, ptr %c_ptr
  ret void
}

define i32 @histstack_pop(ptr %st, ptr %out_kind, ptr %out_pos, ptr %out_data, ptr %out_len) {
entry:
  %c_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 1
  %count = load i64, ptr %c_ptr
  %is_empty = icmp eq i64 %count, 0
  br i1 %is_empty, label %ret_fail, label %do_pop

do_pop:
  %new_count = sub i64 %count, 1
  store i64 %new_count, ptr %c_ptr
  %e_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %e_ptr
  %top_ptr = getelementptr %HistEntry, ptr %entries, i64 %new_count
  %k_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 0
  %k = load i64, ptr %k_ptr
  store i64 %k, ptr %out_kind
  %p_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 1
  %p = load i64, ptr %p_ptr
  store i64 %p, ptr %out_pos
  %d_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 2
  %d = load ptr, ptr %d_ptr
  store ptr %d, ptr %out_data
  %l_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 3
  %l = load i64, ptr %l_ptr
  store i64 %l, ptr %out_len
  ret i32 1

ret_fail:
  ret i32 0
}

define i32 @histstack_peek(ptr %st, ptr %out_kind, ptr %out_pos, ptr %out_len) {
entry:
  %c_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 1
  %count = load i64, ptr %c_ptr
  %is_empty = icmp eq i64 %count, 0
  br i1 %is_empty, label %ret_fail, label %do_peek

do_peek:
  %top_idx = sub i64 %count, 1
  %e_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %e_ptr
  %top_ptr = getelementptr %HistEntry, ptr %entries, i64 %top_idx
  %k_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 0
  %k = load i64, ptr %k_ptr
  store i64 %k, ptr %out_kind
  %p_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 1
  %p = load i64, ptr %p_ptr
  store i64 %p, ptr %out_pos
  %l_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 3
  %l = load i64, ptr %l_ptr
  store i64 %l, ptr %out_len
  ret i32 1

ret_fail:
  ret i32 0
}

; agrega %extra_data (copiado internamente) al FINAL del data del tope,
; suma %extra_len a su len.
define void @histstack_extend_append(ptr %st, ptr %extra_data, i64 %extra_len) {
entry:
  %c_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 1
  %count = load i64, ptr %c_ptr
  %top_idx = sub i64 %count, 1
  %e_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %e_ptr
  %top_ptr = getelementptr %HistEntry, ptr %entries, i64 %top_idx
  %d_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 2
  %d = load ptr, ptr %d_ptr
  %l_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 3
  %l = load i64, ptr %l_ptr
  %new_len = add i64 %l, %extra_len
  %new_d = call ptr @realloc(ptr %d, i64 %new_len)
  %append_at = getelementptr i8, ptr %new_d, i64 %l
  call ptr @memcpy(ptr %append_at, ptr %extra_data, i64 %extra_len)
  store ptr %new_d, ptr %d_ptr
  store i64 %new_len, ptr %l_ptr
  ret void
}

; prepende %extra_data (copiado internamente) antes del data del tope,
; ajusta pos hacia atrás.
define void @histstack_extend_prepend(ptr %st, i64 %new_pos, ptr %extra_data, i64 %extra_len) {
entry:
  %c_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 1
  %count = load i64, ptr %c_ptr
  %top_idx = sub i64 %count, 1
  %e_ptr = getelementptr %HistStack, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %e_ptr
  %top_ptr = getelementptr %HistEntry, ptr %entries, i64 %top_idx
  %d_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 2
  %d = load ptr, ptr %d_ptr
  %l_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 3
  %l = load i64, ptr %l_ptr
  %new_len = add i64 %l, %extra_len
  %new_d = call ptr @malloc(i64 %new_len)
  call ptr @memcpy(ptr %new_d, ptr %extra_data, i64 %extra_len)
  %old_at = getelementptr i8, ptr %new_d, i64 %extra_len
  call ptr @memcpy(ptr %old_at, ptr %d, i64 %l)
  call void @free(ptr %d)
  store ptr %new_d, ptr %d_ptr
  store i64 %new_len, ptr %l_ptr
  %p_ptr = getelementptr %HistEntry, ptr %top_ptr, i32 0, i32 1
  store i64 %new_pos, ptr %p_ptr
  ret void
}

; ================= History (undo + redo) =================

define ptr @hist_create() {
entry:
  %h = call ptr @malloc(i64 16)
  %u = call ptr @histstack_create()
  %r = call ptr @histstack_create()
  %u_ptr = getelementptr %History, ptr %h, i32 0, i32 0
  store ptr %u, ptr %u_ptr
  %r_ptr = getelementptr %History, ptr %h, i32 0, i32 1
  store ptr %r, ptr %r_ptr
  ret ptr %h
}

define void @hist_destroy(ptr %h) {
entry:
  %u_ptr = getelementptr %History, ptr %h, i32 0, i32 0
  %u = load ptr, ptr %u_ptr
  call void @histstack_destroy(ptr %u)
  %r_ptr = getelementptr %History, ptr %h, i32 0, i32 1
  %r = load ptr, ptr %r_ptr
  call void @histstack_destroy(ptr %r)
  call void @free(ptr %h)
  ret void
}

define i32 @hist_can_undo(ptr %h) {
entry:
  %u_ptr = getelementptr %History, ptr %h, i32 0, i32 0
  %u = load ptr, ptr %u_ptr
  %c = call i32 @histstack_count(ptr %u)
  %r = icmp sgt i32 %c, 0
  %rz = zext i1 %r to i32
  ret i32 %rz
}

define i32 @hist_can_redo(ptr %h) {
entry:
  %r_ptr = getelementptr %History, ptr %h, i32 0, i32 1
  %rs = load ptr, ptr %r_ptr
  %c = call i32 @histstack_count(ptr %rs)
  %ok = icmp sgt i32 %c, 0
  %okz = zext i1 %ok to i32
  ret i32 %okz
}

; hist_record_insert: llamar DESPUÉS de un tb_insert exitoso. %data es
; borrowed (se copia adentro si hace falta pushear nueva entrada).
define void @hist_record_insert(ptr %h, i64 %pos, ptr %data, i64 %len) {
entry:
  %r_ptr = getelementptr %History, ptr %h, i32 0, i32 1
  %redo = load ptr, ptr %r_ptr
  call void @histstack_clear(ptr %redo)

  %u_ptr = getelementptr %History, ptr %h, i32 0, i32 0
  %undo = load ptr, ptr %u_ptr

  %pk = alloca i64
  %pp = alloca i64
  %pl = alloca i64
  %peek_ok = call i32 @histstack_peek(ptr %undo, ptr %pk, ptr %pp, ptr %pl)
  %peek_ok_b = icmp eq i32 %peek_ok, 1
  br i1 %peek_ok_b, label %check_coalesce, label %do_push

check_coalesce:
  %pk_v = load i64, ptr %pk
  %pp_v = load i64, ptr %pp
  %pl_v = load i64, ptr %pl
  %same_kind = icmp eq i64 %pk_v, 0
  %prev_end = add i64 %pp_v, %pl_v
  %contiguous = icmp eq i64 %prev_end, %pos
  %can_coalesce = and i1 %same_kind, %contiguous
  br i1 %can_coalesce, label %do_coalesce, label %do_push

do_coalesce:
  call void @histstack_extend_append(ptr %undo, ptr %data, i64 %len)
  ret void

do_push:
  %owned = call ptr @malloc(i64 %len)
  call ptr @memcpy(ptr %owned, ptr %data, i64 %len)
  call void @histstack_push(ptr %undo, i64 0, i64 %pos, ptr %owned, i64 %len)
  ret void
}

; hist_record_delete: llamar ANTES de tb_delete (los bytes todavía tienen
; que existir en el buffer). %data es borrowed, se copia adentro siempre.
define void @hist_record_delete(ptr %h, i64 %pos, ptr %data, i64 %len) {
entry:
  %r_ptr = getelementptr %History, ptr %h, i32 0, i32 1
  %redo = load ptr, ptr %r_ptr
  call void @histstack_clear(ptr %redo)

  %u_ptr = getelementptr %History, ptr %h, i32 0, i32 0
  %undo = load ptr, ptr %u_ptr

  %pk = alloca i64
  %pp = alloca i64
  %pl = alloca i64
  %peek_ok = call i32 @histstack_peek(ptr %undo, ptr %pk, ptr %pp, ptr %pl)
  %peek_ok_b = icmp eq i32 %peek_ok, 1
  br i1 %peek_ok_b, label %check_coalesce, label %do_push

check_coalesce:
  %pk_v = load i64, ptr %pk
  %pp_v = load i64, ptr %pp
  %same_kind = icmp eq i64 %pk_v, 1
  br i1 %same_kind, label %check_direction, label %do_push

check_direction:
  %new_end = add i64 %pos, %len
  %is_backspace = icmp eq i64 %new_end, %pp_v
  br i1 %is_backspace, label %do_prepend, label %check_forward

check_forward:
  %is_forward = icmp eq i64 %pos, %pp_v
  br i1 %is_forward, label %do_append, label %do_push

do_prepend:
  call void @histstack_extend_prepend(ptr %undo, i64 %pos, ptr %data, i64 %len)
  ret void

do_append:
  call void @histstack_extend_append(ptr %undo, ptr %data, i64 %len)
  ret void

do_push:
  %owned = call ptr @malloc(i64 %len)
  call ptr @memcpy(ptr %owned, ptr %data, i64 %len)
  call void @histstack_push(ptr %undo, i64 1, i64 %pos, ptr %owned, i64 %len)
  ret void
}
