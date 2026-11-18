; regex/replace.ll — replace_all puro. NO conoce Document/TextBuffer (regla
; fijada esta sesión: regex/ nunca depende de core/). Opera sobre (ptr,len)
; crudo + un RxProgram* ya compilado (no recompila por posición, a
; diferencia de regex_match_end/group_* que sí recompilan cada llamada).
;
; %RxInst/%RxProgram DUPLICADOS de regex_runner.ll/regex_compiler.ll. DEBEN
; COINCIDIR -- mismo trade-off de duplicación ya aceptado en el resto del
; proyecto (core_abi.h, rx_atom_clone/rx_ast_clone, etc).
%RxInst    = type { i64, i64, i64 }
%RxProgram = type { ptr, i64, i64 }

declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @rx_run(ptr, ptr, i64)
declare i64  @thread_get_save(ptr, i64)
declare void @thread_kill(ptr)

; ---------------------------------------------------------------------
; expand_template: expande \0-\9 del template contra los saves del thread
; ganador (grupo 0 = match completo). \N con N > num_groups, o un grupo
; que no participó (-1), se expande a vacío. Cualquier otro '\X' (X no
; dígito) se copia literal tal cual (backslash + X), sin error -- elección
; deliberada por simplicidad, no hay gramática de escape más rica en los
; templates de reemplazo todavía.
;
; %p: offset absoluto donde arrancó el match en el %text original (los
; saves del thread son relativos a %p, porque así se le pasó el buffer a
; rx_run).
;
; out_buf/out_len: string malloc'd con el reemplazo ya armado.
; ---------------------------------------------------------------------
define internal void @expand_template(ptr %template, i64 %template_len,
                                        ptr %text, i64 %p, ptr %matched,
                                        i64 %num_groups,
                                        ptr %out_buf, ptr %out_len) {
entry:
  %cap_slot = alloca i64
  store i64 64, ptr %cap_slot
  %len_slot = alloca i64
  store i64 0, ptr %len_slot
  %buf_slot = alloca ptr
  %init_buf = call ptr @malloc(i64 64)
  store ptr %init_buf, ptr %buf_slot
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %advance ]
  %done = icmp uge i64 %i, %template_len
  br i1 %done, label %finish, label %check_char

check_char:
  %cp = getelementptr i8, ptr %template, i64 %i
  %c = load i8, ptr %cp
  %is_bslash = icmp eq i8 %c, 92
  br i1 %is_bslash, label %check_next, label %copy_literal

check_next:
  %i1 = add i64 %i, 1
  %has_next = icmp ult i64 %i1, %template_len
  br i1 %has_next, label %peek_next, label %copy_literal

peek_next:
  %np = getelementptr i8, ptr %template, i64 %i1
  %nc = load i8, ptr %np
  %is_digit_lo = icmp uge i8 %nc, 48
  %is_digit_hi = icmp ule i8 %nc, 57
  %is_digit = and i1 %is_digit_lo, %is_digit_hi
  br i1 %is_digit, label %do_group_ref, label %copy_literal

do_group_ref:
  %group = sub i8 %nc, 48
  %group64 = zext i8 %group to i64
  %in_range = icmp ule i64 %group64, %num_groups
  br i1 %in_range, label %fetch_group, label %skip_group_empty

fetch_group:
  %slot_s = mul i64 %group64, 2
  %slot_e = add i64 %slot_s, 1
  %gs = call i64 @thread_get_save(ptr %matched, i64 %slot_s)
  %ge = call i64 @thread_get_save(ptr %matched, i64 %slot_e)
  %gs_ok = icmp sge i64 %gs, 0
  %ge_ok = icmp sge i64 %ge, 0
  %both_ok = and i1 %gs_ok, %ge_ok
  br i1 %both_ok, label %copy_group_bytes, label %skip_group_empty

copy_group_bytes:
  %glen = sub i64 %ge, %gs
  %gsrc_base = add i64 %p, %gs
  %gsrc = getelementptr i8, ptr %text, i64 %gsrc_base
  call void @append_bytes(ptr %buf_slot, ptr %len_slot, ptr %cap_slot, ptr %gsrc, i64 %glen)
  br label %skip_group_empty

skip_group_empty:
  %i_next_group = add i64 %i, 2
  br label %advance

copy_literal:
  %lit_ptr = getelementptr i8, ptr %template, i64 %i
  call void @append_bytes(ptr %buf_slot, ptr %len_slot, ptr %cap_slot, ptr %lit_ptr, i64 1)
  %i_next_lit = add i64 %i, 1
  br label %advance

advance:
  %i_next = phi i64 [ %i_next_group, %skip_group_empty ], [ %i_next_lit, %copy_literal ]
  br label %loop

finish:
  %final_buf = load ptr, ptr %buf_slot
  %final_len = load i64, ptr %len_slot
  store ptr %final_buf, ptr %out_buf
  store i64 %final_len, ptr %out_len
  ret void
}

; agrega %n bytes desde %src al buffer creciente (*buf_slot/*len_slot),
; duplicando capacidad (*cap_slot) si hace falta.
define internal void @append_bytes(ptr %buf_slot, ptr %len_slot, ptr %cap_slot,
                                     ptr %src, i64 %n) {
entry:
  %len = load i64, ptr %len_slot
  %cap = load i64, ptr %cap_slot
  %needed = add i64 %len, %n
  %needs_grow = icmp ugt i64 %needed, %cap
  br i1 %needs_grow, label %grow, label %do_copy

grow:
  %cap2 = mul i64 %cap, 2
  %still_small = icmp ult i64 %cap2, %needed
  %new_cap = select i1 %still_small, i64 %needed, i64 %cap2
  %old_buf = load ptr, ptr %buf_slot
  %new_buf = call ptr @realloc(ptr %old_buf, i64 %new_cap)
  store ptr %new_buf, ptr %buf_slot
  store i64 %new_cap, ptr %cap_slot
  br label %do_copy

do_copy:
  %buf = load ptr, ptr %buf_slot
  br label %copyloop

copyloop:
  %i = phi i64 [ 0, %do_copy ], [ %i_next, %copybyte ]
  %cdone = icmp uge i64 %i, %n
  br i1 %cdone, label %copydone, label %copybyte

copybyte:
  %sp = getelementptr i8, ptr %src, i64 %i
  %dp_off = add i64 %len, %i
  %dp = getelementptr i8, ptr %buf, i64 %dp_off
  %v = load i8, ptr %sp
  store i8 %v, ptr %dp
  %i_next = add i64 %i, 1
  br label %copyloop

copydone:
  %new_len = add i64 %len, %n
  store i64 %new_len, ptr %len_slot
  ret void
}

; duplica capacidad de los 4 arrays paralelos de resultado si hace falta.
define internal void @ensure_match_capacity(ptr %starts_slot, ptr %ends_slot,
                                              ptr %repls_slot, ptr %repl_lens_slot,
                                              ptr %cap_slot, i64 %count) {
entry:
  %cap = load i64, ptr %cap_slot
  %needs_grow = icmp uge i64 %count, %cap
  br i1 %needs_grow, label %grow, label %done

grow:
  %new_cap = mul i64 %cap, 2
  %old_starts = load ptr, ptr %starts_slot
  %old_ends = load ptr, ptr %ends_slot
  %old_repls = load ptr, ptr %repls_slot
  %old_repl_lens = load ptr, ptr %repl_lens_slot
  %bytes = mul i64 %new_cap, 8
  %new_starts = call ptr @realloc(ptr %old_starts, i64 %bytes)
  %new_ends = call ptr @realloc(ptr %old_ends, i64 %bytes)
  %new_repls = call ptr @realloc(ptr %old_repls, i64 %bytes)
  %new_repl_lens = call ptr @realloc(ptr %old_repl_lens, i64 %bytes)
  store ptr %new_starts, ptr %starts_slot
  store ptr %new_ends, ptr %ends_slot
  store ptr %new_repls, ptr %repls_slot
  store ptr %new_repl_lens, ptr %repl_lens_slot
  store i64 %new_cap, ptr %cap_slot
  br label %done

done:
  ret void
}

; ---------------------------------------------------------------------
; replace_all: busca matches de %prog en [%scan_start, %scan_end) de
; %text (%text_len total), comitea (incluye en el resultado) SOLO los que
; EMPIEZAN dentro de [%core_start, %core_end) -- los que arrancan en la
; zona de overlap se descartan acá; el chunk vecino los toma, porque esa
; misma zona es SU core. Esto evita procesar un match dos veces cuando
; cae en la franja de solape entre dos chunks (ver esquema 60/10+40+10/50
; en el handoff de GUI).
;
; %prog: RxProgram* YA COMPILADO -- no recompila por intento, a
; diferencia de regex_match_end/group_* (que sí recompilan cada llamada,
; aceptable para un solo intento pero no para escanear un chunk entero).
;
; out_starts/out_ends: arrays malloc'd de i64 (offsets absolutos en
; %text). out_repls: array malloc'd de ptr (cada string malloc'd).
; out_repl_lens: array malloc'd de i64. out_count: cantidad comiteada.
;
; Devuelve 1 ok, 0 si %prog es null.
; ---------------------------------------------------------------------
define i32 @replace_all(ptr %text, i64 %text_len, ptr %prog,
                          ptr %replacement_template, i64 %replacement_len,
                          i64 %core_start, i64 %core_end,
                          i64 %scan_start, i64 %scan_end,
                          ptr %out_starts, ptr %out_ends,
                          ptr %out_repls, ptr %out_repl_lens,
                          ptr %out_count) {
entry:
  %prog_null = icmp eq ptr %prog, null
  br i1 %prog_null, label %fail, label %setup

setup:
  %ng_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 2
  %num_groups = load i64, ptr %ng_ptr

  %cap_slot = alloca i64
  store i64 8, ptr %cap_slot
  %count_slot = alloca i64
  store i64 0, ptr %count_slot
  %starts_slot = alloca ptr
  %init_starts = call ptr @malloc(i64 64)
  store ptr %init_starts, ptr %starts_slot
  %ends_slot = alloca ptr
  %init_ends = call ptr @malloc(i64 64)
  store ptr %init_ends, ptr %ends_slot
  %repls_slot = alloca ptr
  %init_repls = call ptr @malloc(i64 64)
  store ptr %init_repls, ptr %repls_slot
  %repl_lens_slot = alloca ptr
  %init_repl_lens = call ptr @malloc(i64 64)
  store ptr %init_repl_lens, ptr %repl_lens_slot

  br label %scan_loop

scan_loop:
  %p = phi i64 [ %scan_start, %setup ], [ %p_next, %advance ]
  %p_done = icmp uge i64 %p, %scan_end
  br i1 %p_done, label %finish, label %try_match

try_match:
  %remaining = sub i64 %text_len, %p
  %slice = getelementptr i8, ptr %text, i64 %p
  %matched = call ptr @rx_run(ptr %prog, ptr %slice, i64 %remaining)
  %no_match = icmp eq ptr %matched, null
  br i1 %no_match, label %no_match_advance, label %got_match

got_match:
  %match_end_rel = call i64 @thread_get_save(ptr %matched, i64 1)
  %in_core_lo = icmp sge i64 %p, %core_start
  %in_core_hi = icmp slt i64 %p, %core_end
  %in_core = and i1 %in_core_lo, %in_core_hi
  br i1 %in_core, label %commit, label %skip_commit

commit:
  %repl_buf_slot = alloca ptr
  %repl_len_slot = alloca i64
  call void @expand_template(ptr %replacement_template, i64 %replacement_len,
                              ptr %text, i64 %p, ptr %matched, i64 %num_groups,
                              ptr %repl_buf_slot, ptr %repl_len_slot)
  %repl_buf = load ptr, ptr %repl_buf_slot
  %repl_len = load i64, ptr %repl_len_slot

  %count = load i64, ptr %count_slot
  call void @ensure_match_capacity(ptr %starts_slot, ptr %ends_slot,
                                    ptr %repls_slot, ptr %repl_lens_slot,
                                    ptr %cap_slot, i64 %count)
  %starts = load ptr, ptr %starts_slot
  %ends = load ptr, ptr %ends_slot
  %repls = load ptr, ptr %repls_slot
  %repl_lens = load ptr, ptr %repl_lens_slot

  %s_slot = getelementptr i64, ptr %starts, i64 %count
  store i64 %p, ptr %s_slot
  %match_end_abs = add i64 %p, %match_end_rel
  %e_slot = getelementptr i64, ptr %ends, i64 %count
  store i64 %match_end_abs, ptr %e_slot
  %r_slot = getelementptr ptr, ptr %repls, i64 %count
  store ptr %repl_buf, ptr %r_slot
  %rl_slot = getelementptr i64, ptr %repl_lens, i64 %count
  store i64 %repl_len, ptr %rl_slot

  %count_next = add i64 %count, 1
  store i64 %count_next, ptr %count_slot
  br label %skip_commit

skip_commit:
  call void @thread_kill(ptr %matched)
  %zero_len = icmp eq i64 %match_end_rel, 0
  br i1 %zero_len, label %no_match_advance, label %advance_past_match

advance_past_match:
  %p_after_match = add i64 %p, %match_end_rel
  br label %advance

no_match_advance:
  %p_plus1 = add i64 %p, 1
  br label %advance

advance:
  %p_next = phi i64 [ %p_after_match, %advance_past_match ], [ %p_plus1, %no_match_advance ]
  br label %scan_loop

finish:
  %final_starts = load ptr, ptr %starts_slot
  %final_ends = load ptr, ptr %ends_slot
  %final_repls = load ptr, ptr %repls_slot
  %final_repl_lens = load ptr, ptr %repl_lens_slot
  %final_count = load i64, ptr %count_slot
  store ptr %final_starts, ptr %out_starts
  store ptr %final_ends, ptr %out_ends
  store ptr %final_repls, ptr %out_repls
  store ptr %final_repl_lens, ptr %out_repl_lens
  store i64 %final_count, ptr %out_count
  ret i32 1

fail:
  ret i32 0
}

; libera lo devuelto por replace_all (los 4 arrays + cada string de
; out_repls). No libera %text -- eso sigue siendo propiedad de quien lo
; pasó (el caller en core/, dueño del TextBuffer).
define void @replace_all_free_results(ptr %starts, ptr %ends, ptr %repls,
                                        ptr %repl_lens, i64 %count) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %loop_body ]
  %done = icmp uge i64 %i, %count
  br i1 %done, label %free_arrays, label %loop_body

loop_body:
  %slot = getelementptr ptr, ptr %repls, i64 %i
  %r = load ptr, ptr %slot
  call void @free(ptr %r)
  %i_next = add i64 %i, 1
  br label %loop

free_arrays:
  call void @free(ptr %starts)
  call void @free(ptr %ends)
  call void @free(ptr %repls)
  call void @free(ptr %repl_lens)
  ret void
}
