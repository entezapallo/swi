; core/format.ll — runner regex-driven de formato/resaltado de sintaxis.
; No sabe qué es Markdown/TSV/JSON -- consume una tabla de patrones ya
; compilados y con estilos por grupo, armada AFUERA de este archivo
; (gui/ o quien orqueste, típicamente via abregex + un .def).
;
; Reglas de diseño confirmadas:
; - Cada patrón se compila UNA vez (RxProgram* reusado), nunca recompilado
;   por posición -- format.ll no toca abregex/regex_parse directo, solo
;   corre programas ya listos via rx_run.
; - Cuando dos+ patrones matchean en la misma posición, gana el de match
;   más largo (no el primero de la lista).
; - Sin solapamiento: tras un match, el escaneo salta al final del span.
; - Estilo por grupo: cada PatternEntry declara qué grupos capturados le
;   importan y con qué style_id cada uno -- sin default implícito.
; - LUT de primer byte (256 buckets), calculado una vez al armar la tabla
;   via clausura épsilon sobre el NFA. CHAR/CHAR_CLASS aportan bytes
;   reales; ^/$/\b/\B y MATCH-alcanzable-sin-consumir marcan el patrón
;   "universal" (se prueba en las 256 posiciones -- no se puede acotar en
;   compile-time, pero es siempre seguro, solo pierde algo de la
;   optimización)
; - Cache persistente por documento: fmt_cache_ensure/query/invalidate.
;   ensure() solo extiende el rango cubierto hacia ADELANTE -- si el rango
;   pedido empieza antes de lo cubierto, se descarta todo y se re-escanea
;   entero (simplificación deliberada: cubre scroll hacia abajo con
;   prefetch, que es el caso real de uso; se revisa si se mide que hace
;   falta más).

declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)

declare ptr @rx_run(ptr, ptr, i64)                ; regex_runner.ll
declare i64  @thread_get_save(ptr, i64)           ; regex_thread.ll
declare void @thread_kill(ptr)                    ; regex_thread.ll
declare void @rx_charclass_set(ptr, i8)           ; regex_parser.ll
declare ptr @regex_compile(ptr, i64)
declare void @rx_program_destroy(ptr)
declare i1   @rx_charclass_test(ptr, i8)          ; regex_parser.ll

; ================= FormatResult / FormatSpan =================

%FormatSpan   = type { i64, i64, i64 }  ; offset, length, style_id
%FormatResult = type { ptr, i64, i64 }  ; spans (array), count, capacity

define ptr @fmt_create() {
entry:
  %fr = call ptr @malloc(i64 24)
  %spans_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 0
  store ptr null, ptr %spans_ptr
  %count_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 1
  store i64 0, ptr %count_ptr
  %cap_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 2
  store i64 0, ptr %cap_ptr
  ret ptr %fr
}

define void @fmt_destroy(ptr %fr) {
entry:
  %spans_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 0
  %spans = load ptr, ptr %spans_ptr
  call void @free(ptr %spans)
  call void @free(ptr %fr)
  ret void
}

define void @fmt_clear(ptr %fr) {
entry:
  %count_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 1
  store i64 0, ptr %count_ptr
  ret void
}

define void @fmt_truncate(ptr %fr, i64 %new_count) {
entry:
  %count_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 1
  store i64 %new_count, ptr %count_ptr
  ret void
}

define i64 @fmt_span_count(ptr %fr) {
entry:
  %count_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  ret i64 %count
}

define i64 @fmt_span_offset(ptr %fr, i64 %idx) {
entry:
  %spans_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 0
  %spans = load ptr, ptr %spans_ptr
  %span_ptr = getelementptr %FormatSpan, ptr %spans, i64 %idx
  %off_ptr = getelementptr %FormatSpan, ptr %span_ptr, i32 0, i32 0
  %off = load i64, ptr %off_ptr
  ret i64 %off
}

define i64 @fmt_span_length(ptr %fr, i64 %idx) {
entry:
  %spans_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 0
  %spans = load ptr, ptr %spans_ptr
  %span_ptr = getelementptr %FormatSpan, ptr %spans, i64 %idx
  %len_ptr = getelementptr %FormatSpan, ptr %span_ptr, i32 0, i32 1
  %len = load i64, ptr %len_ptr
  ret i64 %len
}

define i64 @fmt_span_style(ptr %fr, i64 %idx) {
entry:
  %spans_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 0
  %spans = load ptr, ptr %spans_ptr
  %span_ptr = getelementptr %FormatSpan, ptr %spans, i64 %idx
  %style_ptr = getelementptr %FormatSpan, ptr %span_ptr, i32 0, i32 2
  %style = load i64, ptr %style_ptr
  ret i64 %style
}

define i32 @fmt_add_span(ptr %fr, i64 %offset, i64 %length, i64 %style_id) {
entry:
  %count_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  %cap_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 2
  %cap = load i64, ptr %cap_ptr
  %needs_grow = icmp uge i64 %count, %cap
  br i1 %needs_grow, label %grow, label %write

grow:
  %is_zero = icmp eq i64 %cap, 0
  %doubled = mul i64 %cap, 2
  %final_cap = select i1 %is_zero, i64 16, i64 %doubled
  %needed_bytes = mul i64 %final_cap, 24
  %spans_ptr = getelementptr %FormatResult, ptr %fr, i32 0, i32 0
  %old_spans = load ptr, ptr %spans_ptr
  %new_spans = call ptr @realloc(ptr %old_spans, i64 %needed_bytes)
  %alloc_ok = icmp ne ptr %new_spans, null
  br i1 %alloc_ok, label %store_grown, label %fail

store_grown:
  store ptr %new_spans, ptr %spans_ptr
  store i64 %final_cap, ptr %cap_ptr
  br label %write

write:
  %spans_ptr2 = getelementptr %FormatResult, ptr %fr, i32 0, i32 0
  %spans = load ptr, ptr %spans_ptr2
  %span_ptr = getelementptr %FormatSpan, ptr %spans, i64 %count
  %off_ptr = getelementptr %FormatSpan, ptr %span_ptr, i32 0, i32 0
  store i64 %offset, ptr %off_ptr
  %len_ptr = getelementptr %FormatSpan, ptr %span_ptr, i32 0, i32 1
  store i64 %length, ptr %len_ptr
  %style_ptr = getelementptr %FormatSpan, ptr %span_ptr, i32 0, i32 2
  store i64 %style_id, ptr %style_ptr
  %new_count = add i64 %count, 1
  store i64 %new_count, ptr %count_ptr
  ret i32 1

fail:
  ret i32 0
}

; ================= tabla de patrones (armada afuera, solo lectura) =====

%GroupStyle   = type { i64, i64 }       ; group_index, style_id
%PatternEntry = type { ptr, ptr, i64 }  ; RxProgram*, GroupStyle*, group_style_count

; ================= LUT de primer byte =================

%LutBucket = type { ptr, i64, i64 }  ; i64* indices, count, capacity

define internal void @bitset_or(ptr %dst, ptr %src) {
entry:
  %d0 = getelementptr i64, ptr %dst, i64 0
  %s0 = getelementptr i64, ptr %src, i64 0
  %dv0 = load i64, ptr %d0
  %sv0 = load i64, ptr %s0
  %r0 = or i64 %dv0, %sv0
  store i64 %r0, ptr %d0
  %d1 = getelementptr i64, ptr %dst, i64 1
  %s1 = getelementptr i64, ptr %src, i64 1
  %dv1 = load i64, ptr %d1
  %sv1 = load i64, ptr %s1
  %r1 = or i64 %dv1, %sv1
  store i64 %r1, ptr %d1
  %d2 = getelementptr i64, ptr %dst, i64 2
  %s2 = getelementptr i64, ptr %src, i64 2
  %dv2 = load i64, ptr %d2
  %sv2 = load i64, ptr %s2
  %r2 = or i64 %dv2, %sv2
  store i64 %r2, ptr %d2
  %d3 = getelementptr i64, ptr %dst, i64 3
  %s3 = getelementptr i64, ptr %src, i64 3
  %dv3 = load i64, ptr %d3
  %sv3 = load i64, ptr %s3
  %r3 = or i64 %dv3, %sv3
  store i64 %r3, ptr %d3
  ret void
}

; compute_first_bytes: recorre la clausura épsilon del programa desde
; pc=0 (siempre SAVE(0), el wrap implícito de rx_compile), acumulando
; qué bytes puede consumir la primera instrucción real. %out_bitset ya
; viene alocado y en cero (32 bytes). Marca *%out_universal=1 si el
; patrón puede alcanzar MATCH o un assertion zero-width (^ $ \b \B) sin
; que podamos acotar el byte en compile-time.
define internal void @compute_first_bytes(ptr %prog, ptr %out_bitset, ptr %out_universal) {
entry:
  %instrs_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 0
  %instrs = load ptr, ptr %instrs_ptr
  %count_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 1
  %ninst = load i64, ptr %count_ptr

  %stack_bytes = mul i64 %ninst, 8
  %stack = call ptr @malloc(i64 %stack_bytes)
  %visited = call ptr @malloc(i64 %ninst)
  br label %init_visited

init_visited:
  %vi = phi i64 [ 0, %entry ], [ %vi_next, %init_visited_body ]
  %vi_done = icmp uge i64 %vi, %ninst
  br i1 %vi_done, label %push_start, label %init_visited_body

init_visited_body:
  %v_ptr = getelementptr i8, ptr %visited, i64 %vi
  store i8 0, ptr %v_ptr
  %vi_next = add i64 %vi, 1
  br label %init_visited

push_start:
  store i64 0, ptr %stack
  store i8 0, ptr %out_universal
  br label %loop

loop:
  %top = phi i64 [ 1, %push_start ], [ %top_next, %loop_continue ]
  %top_empty = icmp eq i64 %top, 0
  br i1 %top_empty, label %done, label %pop

pop:
  %top_minus1 = sub i64 %top, 1
  %pc_ptr = getelementptr i64, ptr %stack, i64 %top_minus1
  %pc = load i64, ptr %pc_ptr

  %vpc_ptr = getelementptr i8, ptr %visited, i64 %pc
  %vpc = load i8, ptr %vpc_ptr
  %already = icmp ne i8 %vpc, 0
  br i1 %already, label %loop_continue_popped, label %mark_visit

mark_visit:
  store i8 1, ptr %vpc_ptr
  %inst_ptr = getelementptr %RxInst, ptr %instrs, i64 %pc
  %op_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 0
  %opcode = load i64, ptr %op_ptr

  switch i64 %opcode, label %unknown_op [
    i64 0, label %op_char
    i64 1, label %op_split
    i64 2, label %op_jmp
    i64 3, label %op_save
    i64 4, label %op_match
    i64 5, label %op_charclass
    i64 6, label %op_zerowidth
    i64 7, label %op_zerowidth
    i64 8, label %op_zerowidth
  ]

op_char:
  %a1c_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %a1c = load i64, ptr %a1c_ptr
  %bchar = trunc i64 %a1c to i8
  call void @rx_charclass_set(ptr %out_bitset, i8 %bchar)
  br label %loop_continue_popped

op_charclass:
  %a1cc_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %a1cc = load i64, ptr %a1cc_ptr
  %bs = inttoptr i64 %a1cc to ptr
  call void @bitset_or(ptr %out_bitset, ptr %bs)
  br label %loop_continue_popped

op_zerowidth:
  store i8 1, ptr %out_universal
  %pc_next_zw = add i64 %pc, 1
  %new_top_ptr_zw = getelementptr i64, ptr %stack, i64 %top
  store i64 %pc_next_zw, ptr %new_top_ptr_zw
  %top_after_zw = add i64 %top, 1
  br label %loop_continue_pushed

op_split:
  %a1sp_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %a1sp = load i64, ptr %a1sp_ptr
  %a2sp_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 2
  %a2sp = load i64, ptr %a2sp_ptr
  %new_top_ptr2a = getelementptr i64, ptr %stack, i64 %top
  store i64 %a1sp, ptr %new_top_ptr2a
  %top2 = add i64 %top, 1
  %new_top_ptr2b = getelementptr i64, ptr %stack, i64 %top2
  store i64 %a2sp, ptr %new_top_ptr2b
  %top_after_two = add i64 %top2, 1
  br label %loop_continue_pushed

op_jmp:
  %a1j_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %a1j = load i64, ptr %a1j_ptr
  %new_top_ptr_j = getelementptr i64, ptr %stack, i64 %top
  store i64 %a1j, ptr %new_top_ptr_j
  %top_after_j = add i64 %top, 1
  br label %loop_continue_pushed

op_save:
  %pc_next_sv = add i64 %pc, 1
  %new_top_ptr_sv = getelementptr i64, ptr %stack, i64 %top
  store i64 %pc_next_sv, ptr %new_top_ptr_sv
  %top_after_sv = add i64 %top, 1
  br label %loop_continue_pushed

op_match:
  store i8 1, ptr %out_universal
  br label %loop_continue_popped

unknown_op:
  unreachable

loop_continue_pushed:
  %top_next_a = phi i64 [ %top_after_two, %op_split ], [ %top_after_j, %op_jmp ], [ %top_after_sv, %op_save ], [ %top_after_zw, %op_zerowidth ]
  br label %loop_continue

loop_continue_popped:
  br label %loop_continue

loop_continue:
  %top_next = phi i64 [ %top_next_a, %loop_continue_pushed ], [ %top_minus1, %loop_continue_popped ]
  br label %loop

done:
  call void @free(ptr %stack)
  call void @free(ptr %visited)
  ret void
}

define internal void @lut_bucket_add(ptr %lut, i8 %byte, i64 %pattern_idx) {
entry:
  %bidx = zext i8 %byte to i64
  %bucket_ptr = getelementptr %LutBucket, ptr %lut, i64 %bidx
  %count_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  %cap_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 2
  %cap = load i64, ptr %cap_ptr
  %needs_grow = icmp uge i64 %count, %cap
  br i1 %needs_grow, label %grow, label %write

grow:
  %is_zero = icmp eq i64 %cap, 0
  %doubled = mul i64 %cap, 2
  %final_cap = select i1 %is_zero, i64 4, i64 %doubled
  %needed_bytes = mul i64 %final_cap, 8
  %idx_ptr_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 0
  %old_idx = load ptr, ptr %idx_ptr_ptr
  %new_idx = call ptr @realloc(ptr %old_idx, i64 %needed_bytes)
  store ptr %new_idx, ptr %idx_ptr_ptr
  store i64 %final_cap, ptr %cap_ptr
  br label %write

write:
  %idx_ptr_ptr2 = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 0
  %idx_arr = load ptr, ptr %idx_ptr_ptr2
  %slot_ptr = getelementptr i64, ptr %idx_arr, i64 %count
  store i64 %pattern_idx, ptr %slot_ptr
  %new_count = add i64 %count, 1
  store i64 %new_count, ptr %count_ptr
  ret void
}

define void @lut_destroy(ptr %lut) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %body ]
  %done = icmp uge i64 %i, 256
  br i1 %done, label %ret, label %body

body:
  %bucket_ptr = getelementptr %LutBucket, ptr %lut, i64 %i
  %idx_ptr_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 0
  %idx_arr = load ptr, ptr %idx_ptr_ptr
  call void @free(ptr %idx_arr)
  %i_next = add i64 %i, 1
  br label %loop

ret:
  call void @free(ptr %lut)
  ret void
}

; build_lut: arma la LUT de 256 buckets a partir de %patterns/%pattern_count.
; Se llama UNA vez, junto con la compilación de los patrones -- no es hot
; path. Devuelve el ptr a los 256 %LutBucket.
define ptr @build_lut(ptr %patterns, i64 %pattern_count) {
entry:
  %lut = call ptr @malloc(i64 6144)   ; 256 * sizeof(LutBucket=24)
  br label %init_loop

init_loop:
  %bi = phi i64 [ 0, %entry ], [ %bi_next, %init_body ]
  %bi_done = icmp uge i64 %bi, 256
  br i1 %bi_done, label %fill_loop_init, label %init_body

init_body:
  %bucket_ptr = getelementptr %LutBucket, ptr %lut, i64 %bi
  %bp_i_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 0
  store ptr null, ptr %bp_i_ptr
  %bp_c_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 1
  store i64 0, ptr %bp_c_ptr
  %bp_cap_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 2
  store i64 0, ptr %bp_cap_ptr
  %bi_next = add i64 %bi, 1
  br label %init_loop

fill_loop_init:
  %tmp_bs = call ptr @malloc(i64 32)
  br label %fill_loop

fill_loop:
  %pi = phi i64 [ 0, %fill_loop_init ], [ %pi_next, %fill_body_done ]
  %pi_done = icmp uge i64 %pi, %pattern_count
  br i1 %pi_done, label %fill_done, label %fill_body

fill_body:
  %tw0 = getelementptr i64, ptr %tmp_bs, i64 0
  store i64 0, ptr %tw0
  %tw1 = getelementptr i64, ptr %tmp_bs, i64 1
  store i64 0, ptr %tw1
  %tw2 = getelementptr i64, ptr %tmp_bs, i64 2
  store i64 0, ptr %tw2
  %tw3 = getelementptr i64, ptr %tmp_bs, i64 3
  store i64 0, ptr %tw3

  %univ_out = alloca i8
  store i8 0, ptr %univ_out

  %pe_ptr = getelementptr %PatternEntry, ptr %patterns, i64 %pi
  %prog_ptr = getelementptr %PatternEntry, ptr %pe_ptr, i32 0, i32 0
  %prog = load ptr, ptr %prog_ptr

  call void @compute_first_bytes(ptr %prog, ptr %tmp_bs, ptr %univ_out)
  %universal = load i8, ptr %univ_out
  %is_universal = icmp ne i8 %universal, 0
  br i1 %is_universal, label %add_all_buckets, label %add_selective_buckets

add_all_buckets:
  br label %all_loop

all_loop:
  %ab = phi i64 [ 0, %add_all_buckets ], [ %ab_next, %all_body ]
  %ab_done = icmp uge i64 %ab, 256
  br i1 %ab_done, label %fill_body_done, label %all_body

all_body:
  %ab8 = trunc i64 %ab to i8
  call void @lut_bucket_add(ptr %lut, i8 %ab8, i64 %pi)
  %ab_next = add i64 %ab, 1
  br label %all_loop

add_selective_buckets:
  br label %sel_loop

sel_loop:
  %sb = phi i64 [ 0, %add_selective_buckets ], [ %sb_next, %sel_next ]
  %sb_done = icmp uge i64 %sb, 256
  br i1 %sb_done, label %fill_body_done, label %sel_check

sel_check:
  %sb8 = trunc i64 %sb to i8
  %in_set = call i1 @rx_charclass_test(ptr %tmp_bs, i8 %sb8)
  br i1 %in_set, label %sel_add, label %sel_next

sel_add:
  call void @lut_bucket_add(ptr %lut, i8 %sb8, i64 %pi)
  br label %sel_next

sel_next:
  %sb_next = add i64 %sb, 1
  br label %sel_loop

fill_body_done:
  %pi_next = add i64 %pi, 1
  br label %fill_loop

fill_done:
  call void @free(ptr %tmp_bs)
  ret ptr %lut
}

; ================= cache persistente =================

%FormatCache = type { ptr, i64, i64, i64 }  ; FormatResult*, covered_start, covered_end, has_coverage

define internal i64 @i64_min(i64 %a, i64 %b) {
entry:
  %lt = icmp ult i64 %a, %b
  %r = select i1 %lt, i64 %a, i64 %b
  ret i64 %r
}
define void @fmt_apply_pattern(ptr %result, ptr %pattern, i64 %plen, ptr %text, i64 %text_len, i64 %style_id) {
entry:
  %patterns = alloca %PatternEntry
  %compiled = call ptr @regex_compile(ptr %pattern, i64 %plen)
  %prog_ptr = getelementptr %PatternEntry, ptr %patterns, i32 0, i32 0
  store ptr %compiled, ptr %prog_ptr  %gs_ptr = getelementptr %PatternEntry, ptr %patterns, i32 0, i32 1
  %gs = alloca %GroupStyle
  %g_idx_ptr = getelementptr %GroupStyle, ptr %gs, i32 0, i32 0
  store i64 0, ptr %g_idx_ptr
  %g_style_ptr = getelementptr %GroupStyle, ptr %gs, i32 0, i32 1
  store i64 %style_id, ptr %g_style_ptr
  store ptr %gs, ptr %gs_ptr
  %gsc_ptr = getelementptr %PatternEntry, ptr %patterns, i32 0, i32 2
  store i64 1, ptr %gsc_ptr
  %lut = call ptr @build_lut(ptr %patterns, i64 1)
  call void @scan_range(ptr %result, ptr %patterns, i64 1, ptr %lut, ptr %text, i64 %text_len, i64 0, i64 %plen)
  call void @lut_destroy(ptr %lut)
  call void @rx_program_destroy(ptr %compiled)
  ret void
}
define ptr @fmt_cache_create() {
entry:
  %c = call ptr @malloc(i64 32)
  %spans = call ptr @fmt_create()
  %s_ptr = getelementptr %FormatCache, ptr %c, i32 0, i32 0
  store ptr %spans, ptr %s_ptr
  %cs_ptr = getelementptr %FormatCache, ptr %c, i32 0, i32 1
  store i64 0, ptr %cs_ptr
  %ce_ptr = getelementptr %FormatCache, ptr %c, i32 0, i32 2
  store i64 0, ptr %ce_ptr
  %hc_ptr = getelementptr %FormatCache, ptr %c, i32 0, i32 3
  store i64 0, ptr %hc_ptr
  ret ptr %c
}

define void @fmt_cache_destroy(ptr %c) {
entry:
  %s_ptr = getelementptr %FormatCache, ptr %c, i32 0, i32 0
  %spans = load ptr, ptr %s_ptr
  call void @fmt_destroy(ptr %spans)
  call void @free(ptr %c)
  ret void
}

; fmt_cache_query: expone el FormatResult* interno para lectura directa
; (fmt_span_count/offset/length/style sobre lo ya cubierto). No recalcula
; nada -- si el rango pedido no está cubierto, es responsabilidad del
; caller haber llamado fmt_cache_ensure antes.
define ptr @fmt_cache_query(ptr %cache) {
entry:
  %s_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 0
  %spans = load ptr, ptr %s_ptr
  ret ptr %spans
}

define void @fmt_cache_invalidate(ptr %cache, i64 %edit_pos) {
entry:
  %hc_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 3
  %hc = load i64, ptr %hc_ptr
  %has_cov = icmp ne i64 %hc, 0
  br i1 %has_cov, label %do_invalidate, label %ret

do_invalidate:
  %ce_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 2
  %ce = load i64, ptr %ce_ptr
  %new_ce = call i64 @i64_min(i64 %ce, i64 %edit_pos)
  store i64 %new_ce, ptr %ce_ptr

  %cs_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 1
  %cs = load i64, ptr %cs_ptr
  %cs_too_big = icmp ugt i64 %cs, %new_ce
  br i1 %cs_too_big, label %reset_empty, label %prune_spans

reset_empty:
  store i64 0, ptr %hc_ptr
  %s_ptr0 = getelementptr %FormatCache, ptr %cache, i32 0, i32 0
  %spans0 = load ptr, ptr %s_ptr0
  call void @fmt_clear(ptr %spans0)
  br label %ret

prune_spans:
  %s_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 0
  %spans = load ptr, ptr %s_ptr
  %cnt = call i64 @fmt_span_count(ptr %spans)
  br label %prune_loop

prune_loop:
  %i = phi i64 [ %cnt, %prune_spans ], [ %i_next, %prune_body ]
  %i_zero = icmp eq i64 %i, 0
  br i1 %i_zero, label %prune_done, label %prune_check

prune_check:
  %i_minus1 = sub i64 %i, 1
  %off = call i64 @fmt_span_offset(ptr %spans, i64 %i_minus1)
  %still_bad = icmp uge i64 %off, %edit_pos
  br i1 %still_bad, label %prune_body, label %prune_done

prune_body:
  %i_next = sub i64 %i, 1
  br label %prune_loop

prune_done:
  call void @fmt_truncate(ptr %spans, i64 %i)
  br label %ret

ret:
  ret void
}

; ================= scan_range: el matching loop en sí =================
; Recorre [start,end) probando candidatos via la LUT en cada posición sin
; match, y saltando al final del span en cada match (sin solapamiento).
; Entre candidatos que matchean en la misma posición, gana el de mayor
; end (match más largo). Emite un span por cada (grupo,style) configurado
; en la regla ganadora que efectivamente participó del match.

define internal void @scan_range(ptr %spans, ptr %patterns, i64 %pattern_count, ptr %lut, ptr %text, i64 %text_len, i64 %start, i64 %end) {
entry:
  br label %pos_loop

pos_loop:
  %p = phi i64 [ %start, %entry ], [ %p_next, %advance_one ], [ %best_end_c, %after_match ]
  %p_done = icmp uge i64 %p, %end
  br i1 %p_done, label %ret, label %try_match

try_match:
  %byte_ptr = getelementptr i8, ptr %text, i64 %p
  %byte = load i8, ptr %byte_ptr
  %byte_idx = zext i8 %byte to i64
  %bucket_ptr = getelementptr %LutBucket, ptr %lut, i64 %byte_idx
  %idx_arr_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 0
  %idx_arr = load ptr, ptr %idx_arr_ptr
  %bcount_ptr = getelementptr %LutBucket, ptr %bucket_ptr, i32 0, i32 1
  %bcount = load i64, ptr %bcount_ptr
  %remaining = sub i64 %text_len, %p
  br label %cand_loop

cand_loop:
  %ci = phi i64 [ 0, %try_match ], [ %ci_next, %cand_next ]
  %best_thread = phi ptr [ null, %try_match ], [ %best_thread_next, %cand_next ]
  %best_end_c = phi i64 [ -1, %try_match ], [ %best_end_next, %cand_next ]
  %best_idx = phi i64 [ -1, %try_match ], [ %best_idx_next, %cand_next ]
  %ci_done = icmp uge i64 %ci, %bcount
  br i1 %ci_done, label %cand_done, label %cand_body

cand_body:
  %cand_slot_ptr = getelementptr i64, ptr %idx_arr, i64 %ci
  %cand_idx = load i64, ptr %cand_slot_ptr
  %pe_ptr2 = getelementptr %PatternEntry, ptr %patterns, i64 %cand_idx
  %prog_ptr2 = getelementptr %PatternEntry, ptr %pe_ptr2, i32 0, i32 0
  %prog2 = load ptr, ptr %prog_ptr2
  %text_at_p = getelementptr i8, ptr %text, i64 %p
  %t = call ptr @rx_run(ptr %prog2, ptr %text_at_p, i64 %remaining)
  %t_null = icmp eq ptr %t, null
  br i1 %t_null, label %cand_next, label %cand_got_match

cand_got_match:
  %end_local = call i64 @thread_get_save(ptr %t, i64 1)
  %end_global = add i64 %p, %end_local
  %is_longer = icmp sgt i64 %end_global, %best_end_c
  br i1 %is_longer, label %cand_take, label %cand_discard

cand_take:
  %had_prev_best = icmp ne ptr %best_thread, null
  br i1 %had_prev_best, label %kill_prev_best, label %cand_take_direct

kill_prev_best:
  call void @thread_kill(ptr %best_thread)
  br label %cand_take_direct

cand_take_direct:
  br label %cand_next

cand_discard:
  call void @thread_kill(ptr %t)
  br label %cand_next

cand_next:
  %best_thread_next = phi ptr [ %best_thread, %cand_body ], [ %best_thread, %cand_discard ], [ %t, %cand_take_direct ]
  %best_end_next = phi i64 [ %best_end_c, %cand_body ], [ %best_end_c, %cand_discard ], [ %end_global, %cand_take_direct ]
  %best_idx_next = phi i64 [ %best_idx, %cand_body ], [ %best_idx, %cand_discard ], [ %cand_idx, %cand_take_direct ]
  %ci_next = add i64 %ci, 1
  br label %cand_loop

cand_done:
  %found = icmp ne ptr %best_thread, null
  br i1 %found, label %emit_spans, label %advance_one

advance_one:
  %p_next = add i64 %p, 1
  br label %pos_loop

emit_spans:
  %pe_ptr3 = getelementptr %PatternEntry, ptr %patterns, i64 %best_idx
  %gs_ptr3 = getelementptr %PatternEntry, ptr %pe_ptr3, i32 0, i32 1
  %gs_arr = load ptr, ptr %gs_ptr3
  %gsc_ptr3 = getelementptr %PatternEntry, ptr %pe_ptr3, i32 0, i32 2
  %gsc = load i64, ptr %gsc_ptr3
  br label %emit_loop

emit_loop:
  %gi = phi i64 [ 0, %emit_spans ], [ %gi_next, %emit_next ]
  %gi_done = icmp uge i64 %gi, %gsc
  br i1 %gi_done, label %emit_done, label %emit_body

emit_body:
  %gs_slot_ptr = getelementptr %GroupStyle, ptr %gs_arr, i64 %gi
  %g_idx_ptr = getelementptr %GroupStyle, ptr %gs_slot_ptr, i32 0, i32 0
  %g_idx = load i64, ptr %g_idx_ptr
  %g_style_ptr = getelementptr %GroupStyle, ptr %gs_slot_ptr, i32 0, i32 1
  %g_style = load i64, ptr %g_style_ptr

  %slot_start = mul i64 %g_idx, 2
  %slot_end_i = add i64 %slot_start, 1
  %g_start_local = call i64 @thread_get_save(ptr %best_thread, i64 %slot_start)
  %g_end_local = call i64 @thread_get_save(ptr %best_thread, i64 %slot_end_i)

  %g_participated_s = icmp sge i64 %g_start_local, 0
  %g_participated_e = icmp sge i64 %g_end_local, 0
  %g_participated = and i1 %g_participated_s, %g_participated_e
  br i1 %g_participated, label %do_emit, label %emit_next

do_emit:
  %g_start_global = add i64 %p, %g_start_local
  %g_len = sub i64 %g_end_local, %g_start_local
  call void @fmt_add_span(ptr %spans, i64 %g_start_global, i64 %g_len, i64 %g_style)
  br label %emit_next

emit_next:
  %gi_next = add i64 %gi, 1
  br label %emit_loop

emit_done:
  call void @thread_kill(ptr %best_thread)
  br label %after_match

after_match:
  br label %pos_loop

ret:
  ret void
}

; ================= fmt_cache_ensure =================
; Garantiza que [want_start, want_end) está cubierto. Si ya lo está, no
; hace nada. Si el rango pedido empieza ANTES de lo cubierto (o es
; disjunto), re-escanea todo desde cero. Si extiende hacia adelante,
; escanea solo el tramo nuevo (want_end tomando como piso lo ya cubierto).

define void @fmt_cache_ensure(ptr %cache, ptr %patterns, i64 %pattern_count, ptr %lut, ptr %text, i64 %text_len, i64 %want_start, i64 %want_end) {
entry:
  %s_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 0
  %spans = load ptr, ptr %s_ptr
  %cs_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 1
  %ce_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 2
  %hc_ptr = getelementptr %FormatCache, ptr %cache, i32 0, i32 3
  %hc = load i64, ptr %hc_ptr
  %has_cov = icmp ne i64 %hc, 0
  br i1 %has_cov, label %check_overlap, label %fresh_scan

check_overlap:
  %cs = load i64, ptr %cs_ptr
  %ce = load i64, ptr %ce_ptr
  %need_backward = icmp ult i64 %want_start, %cs
  %disjoint = icmp ugt i64 %want_start, %ce
  %need_reset = or i1 %need_backward, %disjoint
  br i1 %need_reset, label %fresh_scan, label %extend_right

fresh_scan:
  call void @fmt_clear(ptr %spans)
  call void @scan_range(ptr %spans, ptr %patterns, i64 %pattern_count, ptr %lut, ptr %text, i64 %text_len, i64 %want_start, i64 %want_end)
  store i64 %want_start, ptr %cs_ptr
  store i64 %want_end, ptr %ce_ptr
  store i64 1, ptr %hc_ptr
  ret void

extend_right:
  %ce2 = load i64, ptr %ce_ptr
  %already_covered = icmp ule i64 %want_end, %ce2
  br i1 %already_covered, label %ret_noop, label %do_extend

do_extend:
  call void @scan_range(ptr %spans, ptr %patterns, i64 %pattern_count, ptr %lut, ptr %text, i64 %text_len, i64 %ce2, i64 %want_end)
  store i64 %want_end, ptr %ce_ptr
  ret void

ret_noop:
  ret void
}
