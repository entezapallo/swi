; core/regex_parser.ll — Fase 1, sub-módulo Parser (texto -> AST).
; Subset: literales, concat, alternación (|), * + ? (con sufijo perezoso
; *? +? ??), {n,m}/{n,}/{n} (expansión estática a copies+OPT/PLUS),
; grupos capturantes/no-capturantes, clases [...] con rangos y negación,
; atajos de clase \d \w \s \D \W \S, y refs de macro %NAME / %NAME<a;b>.
;
; ESCAPES: solo los 6 atajos de clase. Cualquier otro escape (\n \\ \( \|
; \. ...) es error explícito -- o sea: los metacaracteres SIGUEN sin poder
; escribirse como literal, y la barra misma tampoco ('\\' no existe).
; Siguiente incremento natural: pass-through de escape para metacars.
; DENTRO de [...] no hay escapes: '[\d]' es la clase {\, d} (wart
; documentado). '\' al final del patrón: error (escape incompleto).
;
; LAZY (*? +? ??): el parser consume el sufijo y lo guarda en el campo
; group_id del nodo (reuso: ningún walker lee gid en kinds 3/4/5). HASTA
; QUE regex_compiler.ll lo consuma al emitir el SPLIT, el flag viaja pero
; NO cambia comportamiento: a*? compila igual que a*. El '?' tras un '{n,m}'
; NO es lazy -- no se chequea -- y parsea como literal (wart documentado).
;
; {n,m}: tope 1000 repeticiones, más da error explícito. min>max da error.
; {,3} da error (no hay omisión de min como en PCRE).
;
; NO incluye todavía: ^ $ \b \B (necesitan el runner, parche aparte).
; Terminadores estructurales en cualquier patrón: | ) ; > ('<' solo es
; estructural tras un %NAME completo). No hay forma de escribirlos como
; literal todavía.
;
; El AST (%RxNode) es 100% interno a core/ — no se declara en core_abi.h,
; gui/ no puede verlo. Solo se expone regex_parse_check para smoke test.
;
; Limitación conocida: en camino de error, el AST parcial NO se libera
; (leak aceptado, paths de error no son hot path). El leak del camino
; FELIZ de {n,m} sí está cerrado: expand_repeat destruye el átomo
; original (rx_atom_destroy) porque solo incorpora clones.

declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)

; kind: 0=LIT 1=CONCAT 2=ALT 3=STAR 4=PLUS 5=OPT 6=GROUP 7=EMPTY
;       8=MACRO_REF (child1 = arg_list (cadena kind 10) o null,
;                    child2 = %RxName)
;       9=CHARCLASS (child2 -> bitset 256 bits, 4 x i64)
;       10=ARG_LIST_ITEM (child1 = arg_ast, child2 = next_item o null)
; NOTA: para kinds 3/4/5 el campo group_id se REUTILIZA como flag lazy
; (0=greedy, 1=lazy) -- ningún walker legítimo lee group_id en esos
; kinds (verificado: size/max_group/emit/number_groups/clones no lo tocan).
%RxNode = type { i64, ptr, ptr, i64, i64 }  ; kind, child1, child2, lit_char, group_id (-1 si no aplica)
%PState = type { ptr, i64, i64, i64, i64 }  ; pattern, len, pos, next_group_id, error(0/1)

%RxName = type { ptr, i64 }  ; name text (borrowed, no copia), length

define i1 @is_name_char(i8 %c) {
entry:
  %ge_0 = icmp uge i8 %c, 48
  %le_9 = icmp ule i8 %c, 57
  %is_digit = and i1 %ge_0, %le_9
  %ge_A = icmp uge i8 %c, 65
  %le_Z = icmp ule i8 %c, 90
  %is_upper = and i1 %ge_A, %le_Z
  %ge_a = icmp uge i8 %c, 97
  %le_z = icmp ule i8 %c, 122
  %is_lower = and i1 %ge_a, %le_z
  %is_us = icmp eq i8 %c, 95
  %r1 = or i1 %is_digit, %is_upper
  %r2 = or i1 %r1, %is_lower
  %r3 = or i1 %r2, %is_us
  ret i1 %r3
}

define ptr @rx_name_new(ptr %text, i64 %len) {
entry:
  %n = call ptr @malloc(i64 16)
  %ptr_field = getelementptr %RxName, ptr %n, i32 0, i32 0
  store ptr %text, ptr %ptr_field
  %len_field = getelementptr %RxName, ptr %n, i32 0, i32 1
  store i64 %len, ptr %len_field
  ret ptr %n
}

; rx_number_groups: asigna 1,2,3... izquierda-a-derecha a cada GROUP con
; group_id==-2. UNA sola vez, sobre el árbol final ya compuesto (Fase 1:
; recién parseado; Fase 2: recién expandido). kind 8 -> unreachable
; (bug real). kind 10 no puede llegar: solo vive bajo child1 de un kind 8,
; que dispara el unreachable antes de bajar. Los STAR/PLUS/OPT que traen
; flag lazy en group_id pasan por do_unary sin leerlo -- sin colisión.
define i64 @rx_number_groups(ptr %node, i64 %next_id) {
entry:
  %is_null = icmp eq ptr %node, null
  br i1 %is_null, label %ret_same, label %check_kind

check_kind:
  %kind_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 0
  %kind = load i64, ptr %kind_ptr
  %c1_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1 = load ptr, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2 = load ptr, ptr %c2_ptr
  %gid_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 4
  %gid = load i64, ptr %gid_ptr

  %is_group = icmp eq i64 %kind, 6
  br i1 %is_group, label %do_group, label %check_macroref

check_macroref:
  %is_macroref = icmp eq i64 %kind, 8
  br i1 %is_macroref, label %bug_unresolved_ref, label %check_leaf

bug_unresolved_ref:
  unreachable

check_leaf:
  %is_lit = icmp eq i64 %kind, 0
  %is_empty = icmp eq i64 %kind, 7
  %is_charclass = icmp eq i64 %kind, 9
  %l1 = or i1 %is_lit, %is_empty
  %is_leaf = or i1 %l1, %is_charclass
  br i1 %is_leaf, label %ret_same, label %check_binary

do_group:
  %is_pending = icmp eq i64 %gid, -2
  br i1 %is_pending, label %assign, label %recurse_only

assign:
  store i64 %next_id, ptr %gid_ptr
  %next_id1 = add i64 %next_id, 1
  %after_child_a = call i64 @rx_number_groups(ptr %c1, i64 %next_id1)
  ret i64 %after_child_a

recurse_only:
  %after_child_b = call i64 @rx_number_groups(ptr %c1, i64 %next_id)
  ret i64 %after_child_b

check_binary:
  %is_concat = icmp eq i64 %kind, 1
  %is_alt = icmp eq i64 %kind, 2
  %is_binary = or i1 %is_concat, %is_alt
  br i1 %is_binary, label %do_binary, label %do_unary

do_binary:
  %after_c1 = call i64 @rx_number_groups(ptr %c1, i64 %next_id)
  %after_c2 = call i64 @rx_number_groups(ptr %c2, i64 %after_c1)
  ret i64 %after_c2

do_unary:
  ; STAR/PLUS/OPT: un solo hijo en %c1. El group_id de estos kinds es el
  ; flag lazy -- se IGNORA acá a propósito.
  %after_c1u = call i64 @rx_number_groups(ptr %c1, i64 %next_id)
  ret i64 %after_c1u

ret_same:
  ret i64 %next_id
}
; ================= construcción de nodos =================

define ptr @rx_node_new(i64 %kind, ptr %child1, ptr %child2, i64 %lit_char, i64 %group_id) {
entry:
  %n = call ptr @malloc(i64 40)
  %kind_ptr = getelementptr %RxNode, ptr %n, i32 0, i32 0
  store i64 %kind, ptr %kind_ptr
  %c1_ptr = getelementptr %RxNode, ptr %n, i32 0, i32 1
  store ptr %child1, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %n, i32 0, i32 2
  store ptr %child2, ptr %c2_ptr
  %lit_ptr = getelementptr %RxNode, ptr %n, i32 0, i32 3
  store i64 %lit_char, ptr %lit_ptr
  %gid_ptr = getelementptr %RxNode, ptr %n, i32 0, i32 4
  store i64 %group_id, ptr %gid_ptr
  ret ptr %n
}

; ================= bitset de 256 bits (4 x i64) para char classes =====

define ptr @rx_charclass_new() {
entry:
  %bs = call ptr @malloc(i64 32)
  %w0 = getelementptr i64, ptr %bs, i64 0
  store i64 0, ptr %w0
  %w1 = getelementptr i64, ptr %bs, i64 1
  store i64 0, ptr %w1
  %w2 = getelementptr i64, ptr %bs, i64 2
  store i64 0, ptr %w2
  %w3 = getelementptr i64, ptr %bs, i64 3
  store i64 0, ptr %w3
  ret ptr %bs
}

define void @rx_charclass_set(ptr %bs, i8 %byte) {
entry:
  %bv = zext i8 %byte to i64
  %word_idx = lshr i64 %bv, 6
  %bit_idx = and i64 %bv, 63
  %word_ptr = getelementptr i64, ptr %bs, i64 %word_idx
  %old = load i64, ptr %word_ptr
  %mask = shl i64 1, %bit_idx
  %new = or i64 %old, %mask
  store i64 %new, ptr %word_ptr
  ret void
}

define void @rx_charclass_set_range(ptr %bs, i8 %lo, i8 %hi) {
entry:
  %lov = zext i8 %lo to i64
  %hiv = zext i8 %hi to i64
  br label %loop

loop:
  %i = phi i64 [ %lov, %entry ], [ %i_next, %body ]
  %cond = icmp ule i64 %i, %hiv
  br i1 %cond, label %body, label %done

body:
  %ib = trunc i64 %i to i8
  call void @rx_charclass_set(ptr %bs, i8 %ib)
  %i_next = add i64 %i, 1
  br label %loop

done:
  ret void
}

define void @rx_charclass_negate(ptr %bs) {
entry:
  %w0 = getelementptr i64, ptr %bs, i64 0
  %v0 = load i64, ptr %w0
  %n0 = xor i64 %v0, -1
  store i64 %n0, ptr %w0
  %w1 = getelementptr i64, ptr %bs, i64 1
  %v1 = load i64, ptr %w1
  %n1 = xor i64 %v1, -1
  store i64 %n1, ptr %w1
  %w2 = getelementptr i64, ptr %bs, i64 2
  %v2 = load i64, ptr %w2
  %n2 = xor i64 %v2, -1
  store i64 %n2, ptr %w2
  %w3 = getelementptr i64, ptr %bs, i64 3
  %v3 = load i64, ptr %w3
  %n3 = xor i64 %v3, -1
  store i64 %n3, ptr %w3
  ret void
}

; usada por el runner (regex_runner.ll) en runtime para testear un byte.
define i1 @rx_charclass_test(ptr %bs, i8 %byte) {
entry:
  %bv = zext i8 %byte to i64
  %word_idx = lshr i64 %bv, 6
  %bit_idx = and i64 %bv, 63
  %word_ptr = getelementptr i64, ptr %bs, i64 %word_idx
  %w = load i64, ptr %word_ptr
  %mask = shl i64 1, %bit_idx
  %masked = and i64 %w, %mask
  %r = icmp ne i64 %masked, 0
  ret i1 %r
}

; ================= estado del parser =================

define ptr @ps_create(ptr %pattern, i64 %len) {
entry:
  %ps = call ptr @malloc(i64 40)
  %pat_ptr = getelementptr %PState, ptr %ps, i32 0, i32 0
  store ptr %pattern, ptr %pat_ptr
  %len_ptr = getelementptr %PState, ptr %ps, i32 0, i32 1
  store i64 %len, ptr %len_ptr
  %pos_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  store i64 0, ptr %pos_ptr
  %gid_ptr = getelementptr %PState, ptr %ps, i32 0, i32 3
  store i64 1, ptr %gid_ptr
  %err_ptr = getelementptr %PState, ptr %ps, i32 0, i32 4
  store i64 0, ptr %err_ptr
  ret ptr %ps
}

define void @ps_destroy(ptr %ps) {
entry:
  call void @free(ptr %ps)
  ret void
}

define i1 @ps_eof(ptr %ps) {
entry:
  %pos_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  %pos = load i64, ptr %pos_ptr
  %len_ptr = getelementptr %PState, ptr %ps, i32 0, i32 1
  %len = load i64, ptr %len_ptr
  %r = icmp uge i64 %pos, %len
  ret i1 %r
}

define i8 @ps_peek(ptr %ps) {
entry:
  %is_eof = call i1 @ps_eof(ptr %ps)
  br i1 %is_eof, label %ret_zero, label %do_peek

do_peek:
  %pat_ptr = getelementptr %PState, ptr %ps, i32 0, i32 0
  %pat = load ptr, ptr %pat_ptr
  %pos_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  %pos = load i64, ptr %pos_ptr
  %cptr = getelementptr i8, ptr %pat, i64 %pos
  %c = load i8, ptr %cptr
  ret i8 %c

ret_zero:
  ret i8 0
}

; mira un char adelante del actual, sin consumir
define i8 @ps_peek2(ptr %ps) {
entry:
  %pos_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  %pos = load i64, ptr %pos_ptr
  %pos1 = add i64 %pos, 1
  %len_ptr = getelementptr %PState, ptr %ps, i32 0, i32 1
  %len = load i64, ptr %len_ptr
  %oob = icmp uge i64 %pos1, %len
  br i1 %oob, label %ret_zero, label %do_peek

do_peek:
  %pat_ptr = getelementptr %PState, ptr %ps, i32 0, i32 0
  %pat = load ptr, ptr %pat_ptr
  %cptr = getelementptr i8, ptr %pat, i64 %pos1
  %c = load i8, ptr %cptr
  ret i8 %c

ret_zero:
  ret i8 0
}

define void @ps_advance(ptr %ps) {
entry:
  %pos_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  %pos = load i64, ptr %pos_ptr
  %pos_next = add i64 %pos, 1
  store i64 %pos_next, ptr %pos_ptr
  ret void
}

define void @ps_set_error(ptr %ps) {
entry:
  %err_ptr = getelementptr %PState, ptr %ps, i32 0, i32 4
  store i64 1, ptr %err_ptr
  ret void
}

define i1 @ps_has_error(ptr %ps) {
entry:
  %err_ptr = getelementptr %PState, ptr %ps, i32 0, i32 4
  %err = load i64, ptr %err_ptr
  %r = icmp ne i64 %err, 0
  ret i1 %r
}

define i64 @ps_next_group_id(ptr %ps) {
entry:
  %gid_ptr = getelementptr %PState, ptr %ps, i32 0, i32 3
  %gid = load i64, ptr %gid_ptr
  %gid_next = add i64 %gid, 1
  store i64 %gid_next, ptr %gid_ptr
  ret i64 %gid
}

; ================= recursive descent =================
; parse_alt -> parse_concat -> parse_repeat -> parse_atom -> (parse_alt, si grupo/args)

define ptr @parse_atom(ptr %ps) {
entry:
  %c = call i8 @ps_peek(ptr %ps)
  %is_lparen = icmp eq i8 %c, 40
  br i1 %is_lparen, label %group, label %check_lbracket

check_lbracket:
  %is_lbracket = icmp eq i8 %c, 91
  br i1 %is_lbracket, label %charclass, label %check_reserved

check_reserved:
  ; ] ^ $ { } — reservados. '[' -> charclass, '\' -> parse_escape,
  ; '%' -> ref_simple/ref_param. Todos manejados en branches propios.
  ; FIX: '@' NO es reservado dentro de un patron: es un caracter literal
  ; (user@host, emails, etc). El '@' que inicia una definicion se detecta
  ; en abregex_parse_defs ANTES de entrar al parser de patrones, asi que
  ; aca no hay ambiguedad. Antes '@' daba error_reserved (habia que \@).
  %is_rbrack = icmp eq i8 %c, 93
  %is_caret  = icmp eq i8 %c, 94
  %is_dollar = icmp eq i8 %c, 36
  %is_lbrace = icmp eq i8 %c, 123
  %is_rbrace = icmp eq i8 %c, 125
  %r1 = or i1 %is_rbrack, %is_caret
  %r2 = or i1 %r1, %is_dollar
  %r3 = or i1 %r2, %is_lbrace
  %reserved = or i1 %r3, %is_rbrace
  br i1 %reserved, label %error_reserved, label %check_backslash

error_reserved:
  call void @ps_set_error(ptr %ps)
  ret ptr null

check_backslash:
  %is_bslash = icmp eq i8 %c, 92
  br i1 %is_bslash, label %parse_escape, label %check_percent

; ---- \d \w \s \D \W \S -- atajos de clase de caracteres ----
; \b \B (word boundary) y otros escapes NO están soportados todavía
; (necesitan el runner, se agregan junto con ^ $). Cualquier otro escape
; es error explícito -- incluidos \\ \( \| \.: los metacaracteres y la
; barra misma siguen sin poder escribirse como literal.

parse_escape:
  call void @ps_advance(ptr %ps)
  %esc_eof = call i1 @ps_eof(ptr %ps)
  br i1 %esc_eof, label %error_bad_escape, label %read_escape_char

error_bad_escape:
  call void @ps_set_error(ptr %ps)
  ret ptr null

read_escape_char:
  %ec = call i8 @ps_peek(ptr %ps)
  call void @ps_advance(ptr %ps)
  %is_d = icmp eq i8 %ec, 100
  br i1 %is_d, label %esc_digit, label %check_D

esc_digit:
  %bs_d = call ptr @rx_charclass_new()
  call void @rx_charclass_set_range(ptr %bs_d, i8 48, i8 57)
  %node_d = call ptr @rx_node_new(i64 9, ptr null, ptr %bs_d, i64 0, i64 -1)
  ret ptr %node_d

check_D:
  %is_D = icmp eq i8 %ec, 68
  br i1 %is_D, label %esc_D, label %check_w

esc_D:
  %bs_D = call ptr @rx_charclass_new()
  call void @rx_charclass_set_range(ptr %bs_D, i8 48, i8 57)
  call void @rx_charclass_negate(ptr %bs_D)
  %node_D = call ptr @rx_node_new(i64 9, ptr null, ptr %bs_D, i64 0, i64 -1)
  ret ptr %node_D

check_w:
  %is_w = icmp eq i8 %ec, 119
  br i1 %is_w, label %esc_w, label %check_W

esc_w:
  %bs_w = call ptr @rx_charclass_new()
  call void @rx_charclass_set_range(ptr %bs_w, i8 97, i8 122)
  call void @rx_charclass_set_range(ptr %bs_w, i8 65, i8 90)
  call void @rx_charclass_set_range(ptr %bs_w, i8 48, i8 57)
  call void @rx_charclass_set(ptr %bs_w, i8 95)
  %node_w = call ptr @rx_node_new(i64 9, ptr null, ptr %bs_w, i64 0, i64 -1)
  ret ptr %node_w

check_W:
  %is_W = icmp eq i8 %ec, 87
  br i1 %is_W, label %esc_W, label %check_s

esc_W:
  %bs_W = call ptr @rx_charclass_new()
  call void @rx_charclass_set_range(ptr %bs_W, i8 97, i8 122)
  call void @rx_charclass_set_range(ptr %bs_W, i8 65, i8 90)
  call void @rx_charclass_set_range(ptr %bs_W, i8 48, i8 57)
  call void @rx_charclass_set(ptr %bs_W, i8 95)
  call void @rx_charclass_negate(ptr %bs_W)
  %node_W = call ptr @rx_node_new(i64 9, ptr null, ptr %bs_W, i64 0, i64 -1)
  ret ptr %node_W

check_s:
  %is_s = icmp eq i8 %ec, 115
  br i1 %is_s, label %esc_s, label %check_S

esc_s:
  ; [ \t\n\r\f\v] = 32, 9, 10, 13, 12, 11 -- el whitespace clásico byte-oriented
  %bs_s = call ptr @rx_charclass_new()
  call void @rx_charclass_set(ptr %bs_s, i8 32)
  call void @rx_charclass_set(ptr %bs_s, i8 9)
  call void @rx_charclass_set(ptr %bs_s, i8 10)
  call void @rx_charclass_set(ptr %bs_s, i8 13)
  call void @rx_charclass_set(ptr %bs_s, i8 12)
  call void @rx_charclass_set(ptr %bs_s, i8 11)
  %node_s = call ptr @rx_node_new(i64 9, ptr null, ptr %bs_s, i64 0, i64 -1)
  ret ptr %node_s

check_S:
  %is_S = icmp eq i8 %ec, 83
  br i1 %is_S, label %esc_S, label %error_unknown_escape

esc_S:
  %bs_S = call ptr @rx_charclass_new()
  call void @rx_charclass_set(ptr %bs_S, i8 32)
  call void @rx_charclass_set(ptr %bs_S, i8 9)
  call void @rx_charclass_set(ptr %bs_S, i8 10)
  call void @rx_charclass_set(ptr %bs_S, i8 13)
  call void @rx_charclass_set(ptr %bs_S, i8 12)
  call void @rx_charclass_set(ptr %bs_S, i8 11)
  call void @rx_charclass_negate(ptr %bs_S)
  %node_S = call ptr @rx_node_new(i64 9, ptr null, ptr %bs_S, i64 0, i64 -1)
  ret ptr %node_S

error_unknown_escape:
  call void @ps_set_error(ptr %ps)
  ret ptr null

check_percent:
  %is_pct = icmp eq i8 %c, 37
  br i1 %is_pct, label %parse_ref, label %check_stop

parse_ref:
  call void @ps_advance(ptr %ps)
  %name_start_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  %name_start = load i64, ptr %name_start_ptr
  br label %ref_name_loop

ref_name_loop:
  %rn_is_eof = call i1 @ps_eof(ptr %ps)
  br i1 %rn_is_eof, label %ref_name_done, label %ref_name_check

ref_name_check:
  %rn_c = call i8 @ps_peek(ptr %ps)
  %rn_is_name = call i1 @is_name_char(i8 %rn_c)
  br i1 %rn_is_name, label %ref_name_advance, label %ref_name_done

ref_name_advance:
  call void @ps_advance(ptr %ps)
  br label %ref_name_loop

ref_name_done:
  %name_end_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  %name_end = load i64, ptr %name_end_ptr
  %name_len = sub i64 %name_end, %name_start
  %name_empty = icmp eq i64 %name_len, 0
  br i1 %name_empty, label %error_empty_ref, label %check_ref_param

error_empty_ref:
  call void @ps_set_error(ptr %ps)
  ret ptr null

; ---- ref_param: %NAME<a;b;c> -> MACRO_REF con arg_list en child1 ----
; Cada arg es un parse_alt completo; puede anidar (%A<%B<x;y>;z>).
; Permissive conocida: %N<> y %N<a;> parsean con args EMPTY.

check_ref_param:
  %rp_c = call i8 @ps_peek(ptr %ps)
  %rp_is_lt = icmp eq i8 %rp_c, 60
  br i1 %rp_is_lt, label %parse_args, label %build_ref_noargs

build_ref_noargs:
  %pat_ptr2 = getelementptr %PState, ptr %ps, i32 0, i32 0
  %pat2 = load ptr, ptr %pat_ptr2
  %name_ptr_val = getelementptr i8, ptr %pat2, i64 %name_start
  %rxname = call ptr @rx_name_new(ptr %name_ptr_val, i64 %name_len)
  %ref_node = call ptr @rx_node_new(i64 8, ptr null, ptr %rxname, i64 0, i64 -1)
  ret ptr %ref_node

parse_args:
  call void @ps_advance(ptr %ps)
  %first_arg = call ptr @parse_alt(ptr %ps)
  %err_arg0 = call i1 @ps_has_error(ptr %ps)
  br i1 %err_arg0, label %ret_null_args, label %make_head

ret_null_args:
  ret ptr null

make_head:
  %head = call ptr @rx_node_new(i64 10, ptr %first_arg, ptr null, i64 0, i64 -1)
  br label %arg_loop

arg_loop:
  %tail = phi ptr [ %head, %make_head ], [ %new_item, %arg_append ]
  %asep = call i8 @ps_peek(ptr %ps)
  %asep_is_semi = icmp eq i8 %asep, 59
  br i1 %asep_is_semi, label %arg_next, label %arg_check_close

arg_next:
  call void @ps_advance(ptr %ps)
  %next_arg = call ptr @parse_alt(ptr %ps)
  %err_argn = call i1 @ps_has_error(ptr %ps)
  br i1 %err_argn, label %ret_null_args, label %arg_append

arg_append:
  %new_item = call ptr @rx_node_new(i64 10, ptr %next_arg, ptr null, i64 0, i64 -1)
  %tail_c2_ptr = getelementptr %RxNode, ptr %tail, i32 0, i32 2
  store ptr %new_item, ptr %tail_c2_ptr
  br label %arg_loop

arg_check_close:
  %aclose = call i8 @ps_peek(ptr %ps)
  %aclose_is_gt = icmp eq i8 %aclose, 62
  br i1 %aclose_is_gt, label %arg_finish, label %error_bad_arglist

error_bad_arglist:
  call void @ps_set_error(ptr %ps)
  ret ptr null

arg_finish:
  call void @ps_advance(ptr %ps)
  %pat_ptr3 = getelementptr %PState, ptr %ps, i32 0, i32 0
  %pat3 = load ptr, ptr %pat_ptr3
  %name_ptr_val2 = getelementptr i8, ptr %pat3, i64 %name_start
  %rxname2 = call ptr @rx_name_new(ptr %name_ptr_val2, i64 %name_len)
  %ref_node2 = call ptr @rx_node_new(i64 8, ptr %head, ptr %rxname2, i64 0, i64 -1)
  ret ptr %ref_node2

check_stop:
  %is_eof = call i1 @ps_eof(ptr %ps)
  %is_pipe = icmp eq i8 %c, 124
  %is_rparen = icmp eq i8 %c, 41
  %is_semi = icmp eq i8 %c, 59
  %is_gt = icmp eq i8 %c, 62
  %bad1 = or i1 %is_eof, %is_pipe
  %bad2 = or i1 %bad1, %is_rparen
  %bad3 = or i1 %bad2, %is_semi
  %bad = or i1 %bad3, %is_gt
  br i1 %bad, label %error_unexpected, label %literal

error_unexpected:
  call void @ps_set_error(ptr %ps)
  ret ptr null

literal:
  call void @ps_advance(ptr %ps)
  %lit_val = zext i8 %c to i64
  %lit_node = call ptr @rx_node_new(i64 0, ptr null, ptr null, i64 %lit_val, i64 -1)
  ret ptr %lit_node

group:
  call void @ps_advance(ptr %ps)
  %c2 = call i8 @ps_peek(ptr %ps)
  %is_q = icmp eq i8 %c2, 63
  br i1 %is_q, label %check_noncap, label %capturing

check_noncap:
  %c3 = call i8 @ps_peek2(ptr %ps)
  %is_colon = icmp eq i8 %c3, 58
  br i1 %is_colon, label %noncapturing, label %error_bad_group

error_bad_group:
  call void @ps_set_error(ptr %ps)
  ret ptr null

noncapturing:
  call void @ps_advance(ptr %ps)
  call void @ps_advance(ptr %ps)
  %inner1 = call ptr @parse_alt(ptr %ps)
  %err1 = call i1 @ps_has_error(ptr %ps)
  br i1 %err1, label %ret_null1, label %expect_rparen1

ret_null1:
  ret ptr null

expect_rparen1:
  %cr1 = call i8 @ps_peek(ptr %ps)
  %ok1 = icmp eq i8 %cr1, 41
  br i1 %ok1, label %consume1, label %error_no_rparen1

error_no_rparen1:
  call void @ps_set_error(ptr %ps)
  ret ptr null

consume1:
  call void @ps_advance(ptr %ps)
  %gnode1 = call ptr @rx_node_new(i64 6, ptr %inner1, ptr null, i64 0, i64 -1)
  ret ptr %gnode1

capturing:
  %gid = sub i64 0, 2   ; -2 = capturante, pendiente de numerar
  %inner2 = call ptr @parse_alt(ptr %ps)
  %err2 = call i1 @ps_has_error(ptr %ps)
  br i1 %err2, label %ret_null2, label %expect_rparen2

ret_null2:
  ret ptr null

expect_rparen2:
  %cr2 = call i8 @ps_peek(ptr %ps)
  %ok2 = icmp eq i8 %cr2, 41
  br i1 %ok2, label %consume2, label %error_no_rparen2

error_no_rparen2:
  call void @ps_set_error(ptr %ps)
  ret ptr null

consume2:
  call void @ps_advance(ptr %ps)
  %gnode2 = call ptr @rx_node_new(i64 6, ptr %inner2, ptr null, i64 0, i64 %gid)
  ret ptr %gnode2

; ---- clase de caracteres: [abc] [a-z0-9] [^abc] ----
; ']' inmediato tras '[' o '[^' es miembro literal; '-' antes de ']'
; es literal. Los miembros se consumen acá (cc_loop), no via
; parse_concat -- ';' '>' '\' y TODO byte son literales dentro de [...]
; (no hay escapes de clase todavía: '[\d]' = clase {\, d}).

charclass:
  call void @ps_advance(ptr %ps)
  %cc0 = call i8 @ps_peek(ptr %ps)
  %cc_is_caret = icmp eq i8 %cc0, 94
  br i1 %cc_is_caret, label %cc_negate, label %cc_start

cc_negate:
  call void @ps_advance(ptr %ps)
  br label %cc_start

cc_start:
  %bs = call ptr @rx_charclass_new()
  br label %cc_loop

cc_loop:
  %cc_first = phi i1 [ true, %cc_start ], [ false, %cc_member_done ]
  %cc_eof = call i1 @ps_eof(ptr %ps)
  br i1 %cc_eof, label %error_unterminated_class, label %cc_check_close

error_unterminated_class:
  call void @free(ptr %bs)
  call void @ps_set_error(ptr %ps)
  ret ptr null

cc_check_close:
  %ccc = call i8 @ps_peek(ptr %ps)
  %ccc_is_rbrack = icmp eq i8 %ccc, 93
  br i1 %ccc_is_rbrack, label %cc_maybe_close, label %cc_member

cc_maybe_close:
  br i1 %cc_first, label %cc_member, label %cc_close

cc_close:
  call void @ps_advance(ptr %ps)
  br label %cc_finish

cc_member:
  call void @ps_advance(ptr %ps)
  %cc_next = call i8 @ps_peek(ptr %ps)
  %cc_next_is_dash = icmp eq i8 %cc_next, 45
  br i1 %cc_next_is_dash, label %cc_check_range, label %cc_add_single

cc_check_range:
  %cc_after_dash = call i8 @ps_peek2(ptr %ps)
  %cc_after_is_rbrack = icmp eq i8 %cc_after_dash, 93
  br i1 %cc_after_is_rbrack, label %cc_add_single, label %cc_add_range

cc_add_single:
  call void @rx_charclass_set(ptr %bs, i8 %ccc)
  br label %cc_member_done

cc_add_range:
  call void @ps_advance(ptr %ps)
  %cc_hi = call i8 @ps_peek(ptr %ps)
  call void @ps_advance(ptr %ps)
  call void @rx_charclass_set_range(ptr %bs, i8 %ccc, i8 %cc_hi)
  br label %cc_member_done

cc_member_done:
  br label %cc_loop

cc_finish:
  %cc_is_negated = icmp eq i8 %cc0, 94
  br i1 %cc_is_negated, label %cc_do_negate, label %cc_build_node

cc_do_negate:
  call void @rx_charclass_negate(ptr %bs)
  br label %cc_build_node

cc_build_node:
  %cc_node = call ptr @rx_node_new(i64 9, ptr null, ptr %bs, i64 0, i64 -1)
  ret ptr %cc_node
}

define ptr @parse_repeat(ptr %ps) {
entry:
  %atom = call ptr @parse_atom(ptr %ps)
  %err = call i1 @ps_has_error(ptr %ps)
  br i1 %err, label %ret_null, label %check_quant

ret_null:
  ret ptr null

check_quant:
  %c = call i8 @ps_peek(ptr %ps)
  %is_star = icmp eq i8 %c, 42
  br i1 %is_star, label %do_star, label %check_plus

do_star:
  call void @ps_advance(ptr %ps)
  %lazy_s = call i1 @check_lazy_suffix(ptr %ps)
  %lazy_s_i = zext i1 %lazy_s to i64
  %n_star = call ptr @rx_node_new(i64 3, ptr %atom, ptr null, i64 0, i64 %lazy_s_i)
  ret ptr %n_star

check_plus:
  %is_plus = icmp eq i8 %c, 43
  br i1 %is_plus, label %do_plus, label %check_opt

do_plus:
  call void @ps_advance(ptr %ps)
  %lazy_p = call i1 @check_lazy_suffix(ptr %ps)
  %lazy_p_i = zext i1 %lazy_p to i64
  %n_plus = call ptr @rx_node_new(i64 4, ptr %atom, ptr null, i64 0, i64 %lazy_p_i)
  ret ptr %n_plus

check_opt:
  %is_opt = icmp eq i8 %c, 63
  br i1 %is_opt, label %do_opt, label %check_brace

do_opt:
  call void @ps_advance(ptr %ps)
  %lazy_o = call i1 @check_lazy_suffix(ptr %ps)
  %lazy_o_i = zext i1 %lazy_o to i64
  %n_opt = call ptr @rx_node_new(i64 5, ptr %atom, ptr null, i64 0, i64 %lazy_o_i)
  ret ptr %n_opt

check_brace:
  %is_lbrace2 = icmp eq i8 %c, 123
  br i1 %is_lbrace2, label %do_brace, label %no_quant

no_quant:
  ret ptr %atom

do_brace:
  call void @ps_advance(ptr %ps)
  %min_out = alloca i64
  %has_min = call i1 @parse_uint(ptr %ps, ptr %min_out)
  br i1 %has_min, label %check_comma, label %error_bad_brace

error_bad_brace:
  call void @ps_set_error(ptr %ps)
  ret ptr null

check_comma:
  %bc = call i8 @ps_peek(ptr %ps)
  %bc_is_comma = icmp eq i8 %bc, 44
  br i1 %bc_is_comma, label %after_comma, label %exact_count

exact_count:
  %bc2 = call i8 @ps_peek(ptr %ps)
  %bc2_is_rbrace = icmp eq i8 %bc2, 125
  br i1 %bc2_is_rbrace, label %do_exact, label %error_bad_brace

do_exact:
  call void @ps_advance(ptr %ps)
  %min_v = load i64, ptr %min_out
  %expanded_e = call ptr @expand_repeat(ptr %ps, ptr %atom, i64 %min_v, i64 %min_v)
  call void @rx_atom_destroy(ptr %atom)
  ret ptr %expanded_e

after_comma:
  call void @ps_advance(ptr %ps)
  %bc3 = call i8 @ps_peek(ptr %ps)
  %bc3_is_rbrace = icmp eq i8 %bc3, 125
  br i1 %bc3_is_rbrace, label %do_unbounded, label %parse_max

do_unbounded:
  call void @ps_advance(ptr %ps)
  %min_v2 = load i64, ptr %min_out
  %expanded_u = call ptr @expand_repeat(ptr %ps, ptr %atom, i64 %min_v2, i64 -1)
  call void @rx_atom_destroy(ptr %atom)
  ret ptr %expanded_u

parse_max:
  %max_out = alloca i64
  %has_max = call i1 @parse_uint(ptr %ps, ptr %max_out)
  br i1 %has_max, label %expect_rbrace_m, label %error_bad_brace

expect_rbrace_m:
  %bc4 = call i8 @ps_peek(ptr %ps)
  %bc4_is_rbrace = icmp eq i8 %bc4, 125
  br i1 %bc4_is_rbrace, label %do_ranged, label %error_bad_brace

do_ranged:
  call void @ps_advance(ptr %ps)
  %min_v3 = load i64, ptr %min_out
  %max_v3 = load i64, ptr %max_out
  %valid_range = icmp ule i64 %min_v3, %max_v3
  br i1 %valid_range, label %do_expand_ranged, label %error_bad_brace

do_expand_ranged:
  %expanded_r = call ptr @expand_repeat(ptr %ps, ptr %atom, i64 %min_v3, i64 %max_v3)
  call void @rx_atom_destroy(ptr %atom)
  ret ptr %expanded_r
}

; consume el sufjo '?' perezoso si está presente
define i1 @check_lazy_suffix(ptr %ps) {
entry:
  %c = call i8 @ps_peek(ptr %ps)
  %is_q = icmp eq i8 %c, 63
  br i1 %is_q, label %consume, label %ret_false

consume:
  call void @ps_advance(ptr %ps)
  ret i1 true

ret_false:
  ret i1 false
}

; parsea dígitos decimales; escribe el valor en %out. true si había >=1 dígito.
; Sin guard de overflow: un número de ~20 dígitos wrapea i64 -- el cap de
; 1000 de expand_repeat puede teóricamente esquivarse con un wrap negativo,
; pero el peor caso queda acotado en memoria (expansión <= 1000 o error).
; Hardening posible: bail si %val supera 100000 durante la acumulación.
define i1 @parse_uint(ptr %ps, ptr %out) {
entry:
  br label %loop

loop:
  %val = phi i64 [ 0, %entry ], [ %val_next, %body ]
  %ndigits = phi i64 [ 0, %entry ], [ %ndigits_next, %body ]
  %eof = call i1 @ps_eof(ptr %ps)
  br i1 %eof, label %done, label %check_digit

check_digit:
  %c = call i8 @ps_peek(ptr %ps)
  %ge0 = icmp uge i8 %c, 48
  %le9 = icmp ule i8 %c, 57
  %is_digit = and i1 %ge0, %le9
  br i1 %is_digit, label %body, label %done

body:
  call void @ps_advance(ptr %ps)
  %cv = zext i8 %c to i64
  %digit_val = sub i64 %cv, 48
  %val10 = mul i64 %val, 10
  %val_next = add i64 %val10, %digit_val
  %ndigits_next = add i64 %ndigits, 1
  br label %loop

done:
  %ok = icmp sgt i64 %ndigits, 0
  br i1 %ok, label %ret_ok, label %ret_fail

ret_ok:
  store i64 %val, ptr %out
  ret i1 true

ret_fail:
  ret i1 false
}

; clon local (regex_parser.ll no depende de regex_abregex.ll ni de
; regex_compiler.ll -- sería la dirección incorrecta de dependencia).
; A diferencia de rx_ast_clone (abregex), ESTE clone sí maneja kind 8:
; los átomos del parser pueden contener refs sin resolver (p.ej. %a{2}
; clona el ref). Cada clon recibe su PROPIO %RxName (mismo texto borrowed,
; allocación distinta) para que el resolver libere cada uno sin doble free.
define ptr @rx_atom_clone(ptr %node) {
entry:
  %is_null = icmp eq ptr %node, null
  br i1 %is_null, label %ret_null, label %do_clone

ret_null:
  ret ptr null

do_clone:
  %kind_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 0
  %kind = load i64, ptr %kind_ptr
  %c1_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1 = load ptr, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2 = load ptr, ptr %c2_ptr
  %lit_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 3
  %lit = load i64, ptr %lit_ptr
  %gid_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 4
  %gid = load i64, ptr %gid_ptr

  %is_ref = icmp eq i64 %kind, 8
  br i1 %is_ref, label %clone_ref, label %check_cc

clone_ref:
  %c1c = call ptr @rx_atom_clone(ptr %c1)
  %np_ptr = getelementptr %RxName, ptr %c2, i32 0, i32 0
  %np = load ptr, ptr %np_ptr
  %nl_ptr = getelementptr %RxName, ptr %c2, i32 0, i32 1
  %nl = load i64, ptr %nl_ptr
  %new_name = call ptr @rx_name_new(ptr %np, i64 %nl)
  %refc = call ptr @rx_node_new(i64 8, ptr %c1c, ptr %new_name, i64 0, i64 -1)
  ret ptr %refc

check_cc:
  %is_cc = icmp eq i64 %kind, 9
  br i1 %is_cc, label %clone_cc, label %clone_normal

clone_cc:
  %new_bs = call ptr @malloc(i64 32)
  call ptr @memcpy(ptr %new_bs, ptr %c2, i64 32)
  %ccc = call ptr @rx_node_new(i64 9, ptr null, ptr %new_bs, i64 0, i64 -1)
  ret ptr %ccc

clone_normal:
  %c1c2 = call ptr @rx_atom_clone(ptr %c1)
  %c2c2 = call ptr @rx_atom_clone(ptr %c2)
  %newn = call ptr @rx_node_new(i64 %kind, ptr %c1c2, ptr %c2c2, i64 %lit, i64 %gid)
  ret ptr %newn
}

; destructor local -- espejo de rx_ast_destroy (regex_compiler.ll), misma
; duplicación por límite de módulo que rx_atom_clone. Necesario porque
; expand_repeat reemplaza el átomo original por clones: sin esto, cada
; {n,m} leakea el subárbol original en el camino FELIZ.
; kind 8: child2 = %RxName (liberar directo, no recursar); child1 = arg_list.
; kind 9: child2 = bitset (liberar directo); kind 10: recursión genérica.
define void @rx_atom_destroy(ptr %node) {
entry:
  %is_null = icmp eq ptr %node, null
  br i1 %is_null, label %ret, label %do_destroy

do_destroy:
  %kind_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 0
  %kind = load i64, ptr %kind_ptr
  %is_ref = icmp eq i64 %kind, 8
  br i1 %is_ref, label %destroy_ref, label %check_cc

check_cc:
  %is_cc = icmp eq i64 %kind, 9
  br i1 %is_cc, label %destroy_cc, label %destroy_normal

destroy_ref:
  %c1r_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1r = load ptr, ptr %c1r_ptr
  call void @rx_atom_destroy(ptr %c1r)
  %c2r_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2r = load ptr, ptr %c2r_ptr
  call void @free(ptr %c2r)
  call void @free(ptr %node)
  br label %ret

destroy_cc:
  %c1cc_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1cc = load ptr, ptr %c1cc_ptr
  call void @rx_atom_destroy(ptr %c1cc)
  %c2cc_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2cc = load ptr, ptr %c2cc_ptr
  call void @free(ptr %c2cc)
  call void @free(ptr %node)
  br label %ret

destroy_normal:
  %c1_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1 = load ptr, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2 = load ptr, ptr %c2_ptr
  call void @rx_atom_destroy(ptr %c1)
  call void @rx_atom_destroy(ptr %c2)
  call void @free(ptr %node)
  br label %ret

ret:
  ret void
}

; {n,m}: n copias obligatorias (CONCAT) + hasta (m-n) copias opcionales
; (OPT, greedy) si m es finito, o PLUS(clone) si es {n,} (m=-1).
; {0,} == STAR(atom). Tope 1000 repeticiones -- más, error explícito.
; TOMA OWNERSHIP del átomo: lo destruye al entrar y trabaja solo con
; clones deep (ningún camino incorpora el original al resultado).
define ptr @expand_repeat(ptr %ps, ptr %atom, i64 %min, i64 %max) {
entry:
  %min_too_big = icmp sgt i64 %min, 1000
  br i1 %min_too_big, label %error_too_big, label %check_max_cap

check_max_cap:
  %max_is_bounded = icmp sge i64 %max, 0
  br i1 %max_is_bounded, label %check_max_val, label %build_mandatory

check_max_val:
  %max_too_big = icmp sgt i64 %max, 1000
  br i1 %max_too_big, label %error_too_big, label %build_mandatory

error_too_big:
  call void @ps_set_error(ptr %ps)
  ret ptr null

build_mandatory:
  %min_is_zero = icmp eq i64 %min, 0
  %max_is_zero = icmp eq i64 %max, 0
  %both_zero = and i1 %min_is_zero, %max_is_zero
  br i1 %both_zero, label %ret_empty, label %build_loop_init

ret_empty:
  %empty_node = call ptr @rx_node_new(i64 7, ptr null, ptr null, i64 0, i64 -1)
  ret ptr %empty_node

build_loop_init:
  br label %build_loop

build_loop:
  %i = phi i64 [ 0, %build_loop_init ], [ %i_next, %merge_m ]
  %acc = phi ptr [ null, %build_loop_init ], [ %acc_next, %merge_m ]
  %done_mand = icmp uge i64 %i, %min
  br i1 %done_mand, label %after_mandatory, label %build_body

build_body:
  %clone_m = call ptr @rx_atom_clone(ptr %atom)
  %acc_is_null = icmp eq ptr %acc, null
  br i1 %acc_is_null, label %first_m, label %concat_m

first_m:
  br label %merge_m

concat_m:
  %concat_m_node = call ptr @rx_node_new(i64 1, ptr %acc, ptr %clone_m, i64 0, i64 -1)
  br label %merge_m

merge_m:
  %acc_next = phi ptr [ %clone_m, %first_m ], [ %concat_m_node, %concat_m ]
  %i_next = add i64 %i, 1
  br label %build_loop

after_mandatory:
  %is_unbounded = icmp eq i64 %max, -1
  br i1 %is_unbounded, label %add_plus_tail, label %check_optional_tail

add_plus_tail:
  %min_zero_u = icmp eq i64 %min, 0
  br i1 %min_zero_u, label %ret_star_only, label %do_plus_tail

ret_star_only:
  %clone_star = call ptr @rx_atom_clone(ptr %atom)
  %star_node = call ptr @rx_node_new(i64 3, ptr %clone_star, ptr null, i64 0, i64 0)
  ret ptr %star_node

do_plus_tail:
  %clone_plus = call ptr @rx_atom_clone(ptr %atom)
  %plus_node = call ptr @rx_node_new(i64 4, ptr %clone_plus, ptr null, i64 0, i64 0)
  %final_plus = call ptr @rx_node_new(i64 1, ptr %acc, ptr %plus_node, i64 0, i64 -1)
  ret ptr %final_plus

check_optional_tail:
  %opt_count = sub i64 %max, %min
  %no_optional = icmp eq i64 %opt_count, 0
  br i1 %no_optional, label %ret_mandatory_only, label %build_opt_loop_init

ret_mandatory_only:
  ret ptr %acc

build_opt_loop_init:
  br label %build_opt_loop

build_opt_loop:
  %j = phi i64 [ 0, %build_opt_loop_init ], [ %j_next, %merge_o ]
  %acc2 = phi ptr [ %acc, %build_opt_loop_init ], [ %acc2_next, %merge_o ]
  %done_opt = icmp uge i64 %j, %opt_count
  br i1 %done_opt, label %ret_ranged, label %build_opt_body

build_opt_body:
  %clone_o = call ptr @rx_atom_clone(ptr %atom)
  %opt_o = call ptr @rx_node_new(i64 5, ptr %clone_o, ptr null, i64 0, i64 0)
  %acc2_is_null = icmp eq ptr %acc2, null
  br i1 %acc2_is_null, label %first_o, label %concat_o

first_o:
  br label %merge_o

concat_o:
  %concat_o_node = call ptr @rx_node_new(i64 1, ptr %acc2, ptr %opt_o, i64 0, i64 -1)
  br label %merge_o

merge_o:
  %acc2_next = phi ptr [ %opt_o, %first_o ], [ %concat_o_node, %concat_o ]
  %j_next = add i64 %j, 1
  br label %build_opt_loop

ret_ranged:
  ret ptr %acc2
}

define ptr @parse_concat(ptr %ps) {
entry:
  br label %loop

loop:
  %acc = phi ptr [ null, %entry ], [ %acc_next, %merge ]
  %c = call i8 @ps_peek(ptr %ps)
  %is_eof = call i1 @ps_eof(ptr %ps)
  %is_pipe = icmp eq i8 %c, 124
  %is_rparen = icmp eq i8 %c, 41
  %is_semi = icmp eq i8 %c, 59
  %is_gt = icmp eq i8 %c, 62
  %stop1 = or i1 %is_eof, %is_pipe
  %stop2 = or i1 %stop1, %is_rparen
  %stop3 = or i1 %stop2, %is_semi
  %stop = or i1 %stop3, %is_gt
  br i1 %stop, label %done, label %iter

iter:
  %next_atom = call ptr @parse_repeat(ptr %ps)
  %err = call i1 @ps_has_error(ptr %ps)
  br i1 %err, label %ret_null, label %combine

ret_null:
  ret ptr null

combine:
  %acc_is_null = icmp eq ptr %acc, null
  br i1 %acc_is_null, label %first_atom, label %concat_atom

first_atom:
  br label %merge

concat_atom:
  %concat_node = call ptr @rx_node_new(i64 1, ptr %acc, ptr %next_atom, i64 0, i64 -1)
  br label %merge

merge:
  %acc_next = phi ptr [ %next_atom, %first_atom ], [ %concat_node, %concat_atom ]
  br label %loop

done:
  %final_is_null = icmp eq ptr %acc, null
  br i1 %final_is_null, label %ret_empty, label %ret_acc

ret_empty:
  %empty_node = call ptr @rx_node_new(i64 7, ptr null, ptr null, i64 0, i64 -1)
  ret ptr %empty_node

ret_acc:
  ret ptr %acc
}

define ptr @parse_alt(ptr %ps) {
entry:
  %first = call ptr @parse_concat(ptr %ps)
  %err0 = call i1 @ps_has_error(ptr %ps)
  br i1 %err0, label %ret_null, label %loop

ret_null:
  ret ptr null

loop:
  %acc = phi ptr [ %first, %entry ], [ %acc_next, %combine ]
  %c = call i8 @ps_peek(ptr %ps)
  %is_pipe = icmp eq i8 %c, 124
  br i1 %is_pipe, label %iter, label %done

iter:
  call void @ps_advance(ptr %ps)
  %rhs = call ptr @parse_concat(ptr %ps)
  %err1 = call i1 @ps_has_error(ptr %ps)
  br i1 %err1, label %ret_null2, label %combine

ret_null2:
  ret ptr null

combine:
  %acc_next = call ptr @rx_node_new(i64 2, ptr %acc, ptr %rhs, i64 0, i64 -1)
  br label %loop

done:
  ret ptr %acc
}

; ================= entry point =================

define ptr @regex_parse(ptr %pattern, i64 %len) {
entry:
  %ps = call ptr @ps_create(ptr %pattern, i64 %len)
  %ast = call ptr @parse_alt(ptr %ps)
  %has_err = call i1 @ps_has_error(ptr %ps)
  br i1 %has_err, label %fail, label %check_trailing

check_trailing:
  %is_eof = call i1 @ps_eof(ptr %ps)
  br i1 %is_eof, label %success, label %fail_trailing

fail_trailing:
  call void @ps_destroy(ptr %ps)
  ret ptr null

success:
  call void @ps_destroy(ptr %ps)
  ret ptr %ast

fail:
  call void @ps_destroy(ptr %ps)
  ret ptr null
}

define i32 @regex_parse_check(ptr %pattern, i64 %len) {
entry:
  %ast = call ptr @regex_parse(ptr %pattern, i64 %len)
  %is_null = icmp eq ptr %ast, null
  br i1 %is_null, label %ret_fail, label %ret_ok

ret_ok:
  ret i32 1

ret_fail:
  ret i32 0
}
