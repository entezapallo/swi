; core/regex_compiler.ll — Fase 1, sub-módulo Compilador (AST -> NFA).
; Representación de NFA: array plano de instrucciones (estilo "Pike's VM" /
; Russ Cox), no grafo de nodos enlazados — evita backpatching, los tamaños
; se calculan a priori (rx_node_size) y se escribe directo a la posición
; final conocida. Cada instrucción: { opcode, arg1, arg2 }.
;
; opcode: 0=CHAR(arg1=char) 1=SPLIT(arg1=x,arg2=y) 2=JMP(arg1=x)
;         3=SAVE(arg1=slot) 4=MATCH 5=CHAR_CLASS(arg1=ptr a bitset de 256 bits)
;         6=BOL 7=EOL 8=WORDBOUNDARY(arg1: 0=\b pide boundary, 1=\B pide non)
; 6/7/8 corresponden a AST kinds 11/12/13 — DORMIDOS por ahora: el runner
; ya los ejecuta y este compilador ya los emite, pero el parser todavía
; rechaza ^ $ \b \B (siguen en reserved / escape desconocido). Aterrizaje
; compiler-first, espejo del runner-first del round anterior: la tabla de
; arriba es el contrato que el incremento de parser debe producir.
;
; LAZY (*? +? ??): el parser deja el flag en group_id de STAR/PLUS/OPT
; (reuso documentado — ningún otro walker lee gid en kinds 3/4/5). Acá se
; consume: el runner define prioridad por orden de construcción de la
; clausura y SPLIT arg1 es la rama de mayor prioridad; greedy pone el
; cuerpo en arg1, lazy swapea (la salida pasa a arg1). Mismo layout, mismo
; instruction count — solo cambia el orden de los args del SPLIT. El flag
; lazy de {n,m} expandido siempre es greedy (gid=0 en los OPT/PLUS que
; genera expand_repeat).
;
; Ownership de CHAR_CLASS: el bitset que queda en la instrucción es una COPIA
; privada del programa — el original es propiedad del AST y lo libera
; rx_ast_destroy (que regex_compile llama apenas compila). rx_program_destroy
; recorre las instrucciones y libera el arg1 de cada opcode 5.
;
; Grupo 0 (match completo) es implícito: rx_compile envuelve todo el
; programa en SAVE(0)/SAVE(1) — el parser numera los grupos de usuario
; empezando en 1 (ver fix de una línea en regex_parser.ll).

declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @regex_parse(ptr, i64)   ; de regex_parser.ll
declare i64 @rx_number_groups(ptr, i64)   ; de regex_parser.ll

; %RxNode debe tener el mismo layout que en regex_parser.ll — mismo patrón
; que document.ll redeclarando %TextBuffer localmente.
; kind 9=CHARCLASS: child2 apunta al bitset de 32 bytes (4 x i64) creado
; por el parser; el compilador lo COPIA al emitir, nunca lo aliasea.
; kind 11=BOL 12=EOL 13=WORDBOUNDARY: hojas (c1/c2 null); lit_char lleva
; 0=\b / 1=\B (solo kind 13 lo usa) — pendientes de que el parser los
; produzca.
; kinds 8 (MACRO_REF) y 10 (ARG_LIST_ITEM) -> unreachable en los tres
; walkers: rx_emit solo recibe árboles ya resueltos; si algo de eso
; aparece acá es bug de resolución, fail loud.
%RxNode = type { i64, ptr, ptr, i64, i64 }  ; kind, child1, child2, lit_char, group_id (-1 si no aplica)

%RxInst    = type { i64, i64, i64 }  ; opcode, arg1, arg2
%RxProgram = type { ptr, i64, i64 }  ; instructions, count, num_groups

; ================= helpers =================

define i64 @i64_max(i64 %a, i64 %b) {
entry:
  %gt = icmp sgt i64 %a, %b
  %r = select i1 %gt, i64 %a, i64 %b
  ret i64 %r
}

define void @rx_write_inst(ptr %instrs, i64 %idx, i64 %opcode, i64 %arg1, i64 %arg2) {
entry:
  %inst_ptr = getelementptr %RxInst, ptr %instrs, i64 %idx
  %op_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 0
  store i64 %opcode, ptr %op_ptr
  %a1_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  store i64 %arg1, ptr %a1_ptr
  %a2_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 2
  store i64 %arg2, ptr %a2_ptr
  ret void
}

; ================= tamaño y metadata del AST (pura, sin efectos) =================

define i64 @rx_node_size(ptr %node) {
entry:
  %kind_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 0
  %kind = load i64, ptr %kind_ptr
  %c1_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1 = load ptr, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2 = load ptr, ptr %c2_ptr
  %gid_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 4
  %gid = load i64, ptr %gid_ptr

  switch i64 %kind, label %unknown [
    i64 0, label %k_lit
    i64 1, label %k_concat
    i64 2, label %k_alt
    i64 3, label %k_star
    i64 4, label %k_plus
    i64 5, label %k_opt
    i64 6, label %k_group
    i64 7, label %k_empty
    i64 9, label %k_charclass
    i64 11, label %k_bol
    i64 12, label %k_eol
    i64 13, label %k_wordboundary
  ]

k_lit:
  ret i64 1

k_charclass:
  ret i64 1

k_bol:
  ret i64 1

k_eol:
  ret i64 1

k_wordboundary:
  ret i64 1

k_empty:
  ret i64 0

k_concat:
  %s1c = call i64 @rx_node_size(ptr %c1)
  %s2c = call i64 @rx_node_size(ptr %c2)
  %rc = add i64 %s1c, %s2c
  ret i64 %rc

k_alt:
  %s1a = call i64 @rx_node_size(ptr %c1)
  %s2a = call i64 @rx_node_size(ptr %c2)
  %ra1 = add i64 %s1a, %s2a
  %ra2 = add i64 %ra1, 2
  ret i64 %ra2

k_star:
  %s1s = call i64 @rx_node_size(ptr %c1)
  %rs = add i64 %s1s, 2
  ret i64 %rs

k_plus:
  %s1p = call i64 @rx_node_size(ptr %c1)
  %rp = add i64 %s1p, 1
  ret i64 %rp

k_opt:
  %s1o = call i64 @rx_node_size(ptr %c1)
  %ro = add i64 %s1o, 1
  ret i64 %ro

k_group:
  %s1g = call i64 @rx_node_size(ptr %c1)
  %is_cap = icmp sge i64 %gid, 0
  br i1 %is_cap, label %g_cap, label %g_noncap

g_cap:
  %rg1 = add i64 %s1g, 2
  ret i64 %rg1

g_noncap:
  ret i64 %s1g

unknown:
  unreachable
}

; máximo group_id de usuario en el subárbol, o -1 si no hay ninguno.
define i64 @rx_node_max_group(ptr %node) {
entry:
  %kind_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 0
  %kind = load i64, ptr %kind_ptr
  %c1_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1 = load ptr, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2 = load ptr, ptr %c2_ptr
  %gid_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 4
  %gid = load i64, ptr %gid_ptr

  switch i64 %kind, label %unknown [
    i64 0, label %m_leaf
    i64 7, label %m_leaf
    i64 9, label %m_leaf
    i64 11, label %m_leaf
    i64 12, label %m_leaf
    i64 13, label %m_leaf
    i64 1, label %m_binary
    i64 2, label %m_binary
    i64 3, label %m_unary
    i64 4, label %m_unary
    i64 5, label %m_unary
    i64 6, label %m_group
  ]

m_leaf:
  ret i64 -1

m_group:
  %child_max_g = call i64 @rx_node_max_group(ptr %c1)
  %r_group = call i64 @i64_max(i64 %gid, i64 %child_max_g)
  ret i64 %r_group

m_unary:
  %r_unary = call i64 @rx_node_max_group(ptr %c1)
  ret i64 %r_unary

m_binary:
  %m1 = call i64 @rx_node_max_group(ptr %c1)
  %m2 = call i64 @rx_node_max_group(ptr %c2)
  %r_binary = call i64 @i64_max(i64 %m1, i64 %m2)
  ret i64 %r_binary

unknown:
  unreachable
}

; ================= emisión (Thompson construction) =================
; Recibe la posición de escritura actual, devuelve la posición después de
; escribir todo el subárbol. Los targets de SPLIT/JMP se calculan con
; rx_node_size antes de emitir, así que no hace falta backpatching.

define i64 @rx_emit(ptr %instrs, i64 %pos, ptr %node) {
entry:
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

  switch i64 %kind, label %unknown [
    i64 0, label %e_lit
    i64 1, label %e_concat
    i64 2, label %e_alt
    i64 3, label %e_star
    i64 4, label %e_plus
    i64 5, label %e_opt
    i64 6, label %e_group
    i64 7, label %e_empty
    i64 9, label %e_charclass
    i64 11, label %e_bol
    i64 12, label %e_eol
    i64 13, label %e_wordboundary
  ]

e_lit:
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 0, i64 %lit, i64 0)
  %pos_lit = add i64 %pos, 1
  ret i64 %pos_lit

e_charclass:
  ; %c2 = bitset de 32 bytes, PROPIEDAD DEL AST (rx_ast_destroy lo libera).
  ; El programa NO puede aliasearlo: regex_compile destruye el AST apenas
  ; termina rx_emit, y las instrucciones viven después. Se emite una COPIA
  ; privada; rx_program_destroy la libera (opcode 5 -> free(arg1)).
  %cc_copy = call ptr @malloc(i64 32)
  %cc_s0 = getelementptr i64, ptr %c2, i64 0
  %cc_v0 = load i64, ptr %cc_s0
  %cc_d0 = getelementptr i64, ptr %cc_copy, i64 0
  store i64 %cc_v0, ptr %cc_d0
  %cc_s1 = getelementptr i64, ptr %c2, i64 1
  %cc_v1 = load i64, ptr %cc_s1
  %cc_d1 = getelementptr i64, ptr %cc_copy, i64 1
  store i64 %cc_v1, ptr %cc_d1
  %cc_s2 = getelementptr i64, ptr %c2, i64 2
  %cc_v2 = load i64, ptr %cc_s2
  %cc_d2 = getelementptr i64, ptr %cc_copy, i64 2
  store i64 %cc_v2, ptr %cc_d2
  %cc_s3 = getelementptr i64, ptr %c2, i64 3
  %cc_v3 = load i64, ptr %cc_s3
  %cc_d3 = getelementptr i64, ptr %cc_copy, i64 3
  store i64 %cc_v3, ptr %cc_d3
  %cc_intptr = ptrtoint ptr %cc_copy to i64
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 5, i64 %cc_intptr, i64 0)
  %pos_cc = add i64 %pos, 1
  ret i64 %pos_cc

e_bol:
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 6, i64 0, i64 0)
  %pos_bol = add i64 %pos, 1
  ret i64 %pos_bol

e_eol:
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 7, i64 0, i64 0)
  %pos_eol = add i64 %pos, 1
  ret i64 %pos_eol

e_wordboundary:
  ; %lit trae 0=\b / 1=\B, escrito por el parser en lit_char.
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 8, i64 %lit, i64 0)
  %pos_wb = add i64 %pos, 1
  ret i64 %pos_wb

e_empty:
  ret i64 %pos

e_concat:
  %pos_c1 = call i64 @rx_emit(ptr %instrs, i64 %pos, ptr %c1)
  %pos_c2 = call i64 @rx_emit(ptr %instrs, i64 %pos_c1, ptr %c2)
  ret i64 %pos_c2

; L1: SPLIT L2,L4 ; L2: <a> ; JMP L3 ; L4: <b> ; L3: ...
e_alt:
  %size_a = call i64 @rx_node_size(ptr %c1)
  %L2 = add i64 %pos, 1
  %jmp_idx = add i64 %L2, %size_a
  %L4 = add i64 %jmp_idx, 1
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 1, i64 %L2, i64 %L4)
  %pos_after_a = call i64 @rx_emit(ptr %instrs, i64 %L2, ptr %c1)
  %size_b = call i64 @rx_node_size(ptr %c2)
  %L3 = add i64 %L4, %size_b
  call void @rx_write_inst(ptr %instrs, i64 %pos_after_a, i64 2, i64 %L3, i64 0)
  %pos_after_b = call i64 @rx_emit(ptr %instrs, i64 %L4, ptr %c2)
  ret i64 %pos_after_b

; L1: SPLIT L2,L3 ; L2: <a> ; JMP L1 ; L3: ...
; greedy: SPLIT L2(body),L3(exit). lazy: SPLIT L3,L2 — la salida pasa a
; arg1 (mayor prioridad) y el MATCH vacío gana antes que consumir.
e_star:
  %size_s = call i64 @rx_node_size(ptr %c1)
  %L2_s = add i64 %pos, 1
  %jmp_idx_s = add i64 %L2_s, %size_s
  %L3_s = add i64 %jmp_idx_s, 1
  %is_lazy_s = icmp eq i64 %gid, 1
  %split_a1_s = select i1 %is_lazy_s, i64 %L3_s, i64 %L2_s
  %split_a2_s = select i1 %is_lazy_s, i64 %L2_s, i64 %L3_s
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 1, i64 %split_a1_s, i64 %split_a2_s)
  %pos_after_body_s = call i64 @rx_emit(ptr %instrs, i64 %L2_s, ptr %c1)
  call void @rx_write_inst(ptr %instrs, i64 %pos_after_body_s, i64 2, i64 %pos, i64 0)
  ret i64 %L3_s

; L1: <a> ; SPLIT L1,L2 ; L2: ...
; greedy: SPLIT L1(loop),L2(exit). lazy: SPLIT L2,L1 — salir primero.
e_plus:
  %pos_after_body_p = call i64 @rx_emit(ptr %instrs, i64 %pos, ptr %c1)
  %L2_p = add i64 %pos_after_body_p, 1
  %is_lazy_p = icmp eq i64 %gid, 1
  %split_a1_p = select i1 %is_lazy_p, i64 %L2_p, i64 %pos
  %split_a2_p = select i1 %is_lazy_p, i64 %pos, i64 %L2_p
  call void @rx_write_inst(ptr %instrs, i64 %pos_after_body_p, i64 1, i64 %split_a1_p, i64 %split_a2_p)
  ret i64 %L2_p

; SPLIT L1,L2 ; L1: <a> ; L2: ...
; greedy: SPLIT L1(body),L2(skip). lazy: SPLIT L2,L1 — saltar primero.
e_opt:
  %size_o = call i64 @rx_node_size(ptr %c1)
  %L1_o = add i64 %pos, 1
  %L2_o = add i64 %L1_o, %size_o
  %is_lazy_o = icmp eq i64 %gid, 1
  %split_a1_o = select i1 %is_lazy_o, i64 %L2_o, i64 %L1_o
  %split_a2_o = select i1 %is_lazy_o, i64 %L1_o, i64 %L2_o
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 1, i64 %split_a1_o, i64 %split_a2_o)
  %pos_after_body_o = call i64 @rx_emit(ptr %instrs, i64 %L1_o, ptr %c1)
  ret i64 %pos_after_body_o

e_group:
  %is_cap_g = icmp sge i64 %gid, 0
  br i1 %is_cap_g, label %g_do_cap, label %g_do_noncap

g_do_cap:
  %slot_open = mul i64 %gid, 2
  call void @rx_write_inst(ptr %instrs, i64 %pos, i64 3, i64 %slot_open, i64 0)
  %pos1_g = add i64 %pos, 1
  %pos_after_child_g = call i64 @rx_emit(ptr %instrs, i64 %pos1_g, ptr %c1)
  %slot_close = add i64 %slot_open, 1
  call void @rx_write_inst(ptr %instrs, i64 %pos_after_child_g, i64 3, i64 %slot_close, i64 0)
  %pos_final_g = add i64 %pos_after_child_g, 1
  ret i64 %pos_final_g

g_do_noncap:
  %pos_noncap = call i64 @rx_emit(ptr %instrs, i64 %pos, ptr %c1)
  ret i64 %pos_noncap

unknown:
  unreachable
}

; ================= entry points =================

; rx_compile: envuelve todo el AST con el grupo implícito 0 (SAVE 0 / SAVE 1)
; y agrega el MATCH final. num_groups incluye el grupo 0 (siempre >= 1).
define ptr @rx_compile(ptr %ast) {
entry:
  %dummy_numbered = call i64 @rx_number_groups(ptr %ast, i64 1)
  %size = call i64 @rx_node_size(ptr %ast)
  %total = add i64 %size, 3   ; SAVE(0) + <ast> + SAVE(1) + MATCH

  %bytes = mul i64 %total, 24
  %instrs = call ptr @malloc(i64 %bytes)

  call void @rx_write_inst(ptr %instrs, i64 0, i64 3, i64 0, i64 0)      ; SAVE 0
  %pos_after_ast = call i64 @rx_emit(ptr %instrs, i64 1, ptr %ast)
  call void @rx_write_inst(ptr %instrs, i64 %pos_after_ast, i64 3, i64 1, i64 0)  ; SAVE 1
  %match_idx = add i64 %pos_after_ast, 1
  call void @rx_write_inst(ptr %instrs, i64 %match_idx, i64 4, i64 0, i64 0)      ; MATCH

  %max_gid = call i64 @rx_node_max_group(ptr %ast)
  %clamped = call i64 @i64_max(i64 %max_gid, i64 0)
  %num_groups = add i64 %clamped, 1

  %prog = call ptr @malloc(i64 24)
  %instrs_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 0
  store ptr %instrs, ptr %instrs_ptr
  %count_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 1
  store i64 %total, ptr %count_ptr
  %ng_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 2
  store i64 %num_groups, ptr %ng_ptr
  ret ptr %prog
}

define void @rx_ast_destroy(ptr %node) {
entry:
  %is_null = icmp eq ptr %node, null
  br i1 %is_null, label %ret, label %do_destroy

do_destroy:
  %kind_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 0
  %kind = load i64, ptr %kind_ptr
  %is_macro_ref = icmp eq i64 %kind, 8
  br i1 %is_macro_ref, label %destroy_macro_ref, label %check_charclass

check_charclass:
  %is_charclass = icmp eq i64 %kind, 9
  br i1 %is_charclass, label %destroy_charclass, label %destroy_normal

destroy_macro_ref:
  ; child2 = %RxName* -- NUNCA se recorre como %RxNode, se libera directo.
  ; child1 = arg_list (kinds 10 encadenados) -- sí se recurre.
  %c1m_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1m = load ptr, ptr %c1m_ptr
  call void @rx_ast_destroy(ptr %c1m)
  %c2m_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2m = load ptr, ptr %c2m_ptr
  call void @free(ptr %c2m)
  call void @free(ptr %node)
  br label %ret

destroy_charclass:
  ; child2 = bitset de 32 bytes -- tampoco es un %RxNode, se libera directo.
  ; child1 siempre null para CHAR_CLASS, pero igual pasa por rx_ast_destroy
  ; (null-safe) por si en algún incremento futuro deja de serlo.
  %c1cc_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1cc = load ptr, ptr %c1cc_ptr
  call void @rx_ast_destroy(ptr %c1cc)
  %c2cc_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2cc = load ptr, ptr %c2cc_ptr
  call void @free(ptr %c2cc)
  call void @free(ptr %node)
  br label %ret

destroy_normal:
  ; kinds 0-7, 10, 11, 12, 13 -- 11/12/13 son hojas (c1/c2 null), caen acá
  ; sin daño: la recursión null-safe termina inmediata.
  %c1_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1 = load ptr, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2 = load ptr, ptr %c2_ptr
  call void @rx_ast_destroy(ptr %c1)
  call void @rx_ast_destroy(ptr %c2)
  call void @free(ptr %node)
  br label %ret

ret:
  ret void
}

; libera el programa Y los bitsets propios de las instrucciones CHAR_CLASS
; (opcode 5, arg1 = ptr): viven fuera del array plano, sin este recorrido
; habría leak. Los bitsets del AST ya los liberó rx_ast_destroy -- estos son
; las copias que hizo e_charclass, dueño único = el programa.
define void @rx_program_destroy(ptr %prog) {
entry:
  %instrs_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 0
  %instrs = load ptr, ptr %instrs_ptr
  %count_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %next ]
  %in_range = icmp ult i64 %i, %count
  br i1 %in_range, label %body, label %done

body:
  %inst_ptr = getelementptr %RxInst, ptr %instrs, i64 %i
  %op_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 0
  %op = load i64, ptr %op_ptr
  %is_cc = icmp eq i64 %op, 5
  br i1 %is_cc, label %free_cc, label %next

free_cc:
  %a1_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %a1 = load i64, ptr %a1_ptr
  %bs_ptr = inttoptr i64 %a1 to ptr
  call void @free(ptr %bs_ptr)
  br label %next

next:
  %i_next = add i64 %i, 1
  br label %loop

done:
  call void @free(ptr %instrs)
  call void @free(ptr %prog)
  ret void
}

; regex_compile: parse + compile + libera el AST intermedio. Devuelve
; %RxProgram* o null si el patrón no parseó.
define ptr @regex_compile(ptr %pattern, i64 %len) {
entry:
  %ast = call ptr @regex_parse(ptr %pattern, i64 %len)
  %is_null = icmp eq ptr %ast, null
  br i1 %is_null, label %ret_null, label %do_compile

do_compile:
  %prog = call ptr @rx_compile(ptr %ast)
  call void @rx_ast_destroy(ptr %ast)
  ret ptr %prog

ret_null:
  ret ptr null
}

; --- smoke test endpoints: no exponen %RxProgram, solo metadata para
; verificar contra conteos calculados a mano. ---

define i64 @regex_compile_instruction_count(ptr %pattern, i64 %len) {
entry:
  %prog = call ptr @regex_compile(ptr %pattern, i64 %len)
  %is_null = icmp eq ptr %prog, null
  br i1 %is_null, label %ret_neg1, label %do_count

do_count:
  %count_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  call void @rx_program_destroy(ptr %prog)
  ret i64 %count

ret_neg1:
  ret i64 -1
}

define i64 @regex_compile_group_count(ptr %pattern, i64 %len) {
entry:
  %prog = call ptr @regex_compile(ptr %pattern, i64 %len)
  %is_null = icmp eq ptr %prog, null
  br i1 %is_null, label %ret_neg1, label %do_count

do_count:
  %ng_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 2
  %ng = load i64, ptr %ng_ptr
  call void @rx_program_destroy(ptr %prog)
  ret i64 %ng

ret_neg1:
  ret i64 -1
}
