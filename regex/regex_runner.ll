; core/regex_runner.ll — Fase 1, sub-módulo Runner (NFA -> match).
;
; Ejecuta el %RxProgram producido por regex_compiler.ll usando el algoritmo
; de Pike (Russ Cox) sobre las primitivas de thread de regex_thread.ll.
;
; Opcodes: 0=CHAR 1=SPLIT 2=JMP 3=SAVE 4=MATCH 5=CHAR_CLASS(arg1 = int
; del ptr al bitset, COPIA propiedad del programa -- el runner la usa pero
; NUNCA la libera: el dueño es rx_program_destroy) 6=BOL 7=EOL
; 8=WORDBOUNDARY(arg1: 0=\b pide boundary, 1=\B pide non-boundary).
; 5 es consumidor (inner loop, mismo lugar que CHAR); 6/7/8 son
; zero-width: no consumen byte, se resuelven en la clausura épsilon de
; rx_addthread (igual que JMP/SPLIT/SAVE), para lo cual rx_addthread
; recibe %text/%text_len. NOTA: 6/7/8 están DORMIDOS -- el compiler
; todavía no los emite y el parser sigue rechazando ^ $ \b \B. Este
; archivo aterriza el lado runner primero: la tabla de arriba es el
; contrato que el próximo incremento de parser+compiler debe emitir.
;
; Reglas ya cerradas (regex-spec.md / jotter-handoff.md):
;   - Dedup de threads por estado (gen[pc] == step actual) -- obligatorio,
;     si no (a*)* explota. Implementado en rx_addthread.
;   - Prioridad = orden de construcción de la clausura épsilon: en SPLIT
;     arg1 es la rama de mayor prioridad (se recorre y agota primero,
;     literalmente antes de tocar arg2), igual que en la emisión de
;     regex_compiler.ll (alternación/estrella siempre ponen la rama
;     "greedy" en arg1). El runner no reordena nada, solo respeta el
;     orden en que rx_addthread agrega threads a la lista.
;   - BOL/EOL son SIEMPRE multiline: '^' pasa si pos==0 o el byte previo
;     es '\n'; '$' pasa si pos==text_len o el byte actual es '\n'.
;     Decisión consciente para un editor de texto -- no hay modo
;     single-line, y conviene tenerla documentada antes de integrar
;     con find (ver abajo el punto de slices).
;   - 100% anclado: el thread inicial arranca en pc=0, pos=0, nunca se
;     prueban otras posiciones de arranque. No es "buscar en el texto",
;     es "matchea desde el principio" (equivalente a ^patrón, sin $ ;     salvo que el patrón mismo lo fuerce).
;   - Desacoplado de %TextBuffer: recibe ptr+len genérico (%text/%text_len),
;     igual que regex_compile ya recibe ptr+len para el patrón.
;   - Usa `switch` (rx_addthread y rx_run despachan por opcode) -> con
;     llc el target de Makefile necesita -relocation-model=pic; con clang
;     como frontend (estado actual del Makefile) sale PIC solo.
;
; %RxInst/%RxProgram redeclarados localmente con el mismo layout que
; regex_compiler.ll -- mismo patrón que document.ll redeclarando
; %TextBuffer, o regex_thread.ll con su propio %Thread/%SaveBuf.

declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @regex_compile(ptr, i64)      ; de regex_compiler.ll
declare void @rx_program_destroy(ptr)     ; de regex_compiler.ll
declare i1 @rx_charclass_test(ptr, i8)    ; de regex_parser.ll

declare ptr @thread_create(i64, i64)      ; de regex_thread.ll
declare ptr @thread_fork(ptr)
declare void @thread_save(ptr, i64, i64)
declare i64 @thread_get_save(ptr, i64)
declare i64 @thread_state(ptr)
declare void @thread_set_state(ptr, i64)
declare void @thread_kill(ptr)


; ---------------------------------------------------------------------
; rx_alloc_gen: array de dedup, uno por instrucción, todo en -1 (ningún
; step real vale -1, así que "no visitado todavía" nunca colisiona con
; el primer step real usado por rx_run, que arranca en 0).
; ---------------------------------------------------------------------
define internal ptr @rx_alloc_gen(i64 %ninst) {
entry:
  %bytes = mul i64 %ninst, 8
  %gen = call ptr @malloc(i64 %bytes)
  br label %check

check:
  %i = phi i64 [ 0, %entry ], [ %i_next, %body ]
  %cond = icmp slt i64 %i, %ninst
  br i1 %cond, label %body, label %end

body:
  %slot_ptr = getelementptr i64, ptr %gen, i64 %i
  store i64 -1, ptr %slot_ptr
  %i_next = add i64 %i, 1
  br label %check

end:
  ret ptr %gen
}

; ---------------------------------------------------------------------
; rx_kill_range: mata threads[from..to) de una lista. Usado al encontrar
; un MATCH: todo lo que queda después en la lista tiene prioridad menor
; y no puede ganar, así que no tiene sentido seguir procesándolo -- pero
; sigue vivo (tiene un %SaveBuf con refcount) y hay que liberarlo.
; ---------------------------------------------------------------------
define internal void @rx_kill_range(ptr %list, i64 %from, i64 %to) {
entry:
  br label %check

check:
  %i = phi i64 [ %from, %entry ], [ %i_next, %body ]
  %cond = icmp slt i64 %i, %to
  br i1 %cond, label %body, label %end

body:
  %slot_ptr = getelementptr ptr, ptr %list, i64 %i
  %t = load ptr, ptr %slot_ptr
  call void @thread_kill(ptr %t)
  %i_next = add i64 %i, 1
  br label %check

end:
  ret void
}

; ---------------------------------------------------------------------
; rx_addthread: agrega %t a %list siguiendo la clausura épsilon (JMP,
; SPLIT, SAVE, BOL, EOL, WORDBOUNDARY no consumen input, se resuelven
; acá mismo por recursión; solo CHAR/CHAR_CLASS/MATCH son terminales y
; quedan efectivamente en la lista). Los zero-width de aserción (BOL/
; EOL/WB) evalúan contra %text/%text_len en la posición actual %pos --
; matar el thread si la aserción falla es lo correcto: esa rama de la
; clausura muere ahí, el resto del árbol sigue vivo por sus otros
; threads.
; Dedupea por gen[pc]==step ANTES de mirar el opcode -- así un SPLIT que
; vuelve a un pc ya visitado en este mismo step corta ahí, no importa en
; qué instrucción esté.
;
; Devuelve el nuevo listlen (threadeado por valor de retorno, mismo estilo
; que rx_emit en regex_compiler.ll con `pos`, no hay mutable state global).
; ---------------------------------------------------------------------
define internal i64 @rx_addthread(ptr %list, i64 %listlen, ptr %gen, i64 %step, ptr %instrs, ptr %t, i64 %pos, ptr %text, i64 %text_len) {
entry:
  %pc = call i64 @thread_state(ptr %t)
  %gen_ptr = getelementptr i64, ptr %gen, i64 %pc
  %g = load i64, ptr %gen_ptr
  %already = icmp eq i64 %g, %step
  br i1 %already, label %dedup, label %mark

dedup:
  call void @thread_kill(ptr %t)
  ret i64 %listlen

mark:
  store i64 %step, ptr %gen_ptr
  %inst_ptr = getelementptr %RxInst, ptr %instrs, i64 %pc
  %op_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 0
  %opcode = load i64, ptr %op_ptr
  switch i64 %opcode, label %append [
    i64 1, label %do_split
    i64 2, label %do_jmp
    i64 3, label %do_save
    i64 6, label %do_bol
    i64 7, label %do_eol
    i64 8, label %do_wordboundary
  ]

do_jmp:
  %a1j_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %a1j = load i64, ptr %a1j_ptr
  call void @thread_set_state(ptr %t, i64 %a1j)
  %r_jmp = call i64 @rx_addthread(ptr %list, i64 %listlen, ptr %gen, i64 %step, ptr %instrs, ptr %t, i64 %pos, ptr %text, i64 %text_len)
  ret i64 %r_jmp

do_split:
  %a1s_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %a1s = load i64, ptr %a1s_ptr
  %a2s_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 2
  %a2s = load i64, ptr %a2s_ptr
  %t2 = call ptr @thread_fork(ptr %t)
  call void @thread_set_state(ptr %t, i64 %a1s)
  %len1 = call i64 @rx_addthread(ptr %list, i64 %listlen, ptr %gen, i64 %step, ptr %instrs, ptr %t, i64 %pos, ptr %text, i64 %text_len)
  call void @thread_set_state(ptr %t2, i64 %a2s)
  %len2 = call i64 @rx_addthread(ptr %list, i64 %len1, ptr %gen, i64 %step, ptr %instrs, ptr %t2, i64 %pos, ptr %text, i64 %text_len)
  ret i64 %len2

do_save:
  %slot_ptr2 = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %slot = load i64, ptr %slot_ptr2
  call void @thread_save(ptr %t, i64 %slot, i64 %pos)
  %pc1 = add i64 %pc, 1
  call void @thread_set_state(ptr %t, i64 %pc1)
  %r_save = call i64 @rx_addthread(ptr %list, i64 %listlen, ptr %gen, i64 %step, ptr %instrs, ptr %t, i64 %pos, ptr %text, i64 %text_len)
  ret i64 %r_save

; ---- BOL (^): pos==0, o multiline: byte anterior=='\n' ----
; El GEP de prev solo se ejecuta con pos>=1 (is_start ya cubrió el 0).
do_bol:
  %is_start = icmp eq i64 %pos, 0
  br i1 %is_start, label %bol_pass, label %bol_check_nl

bol_check_nl:
  %prev_pos = sub i64 %pos, 1
  %prev_ptr = getelementptr i8, ptr %text, i64 %prev_pos
  %prev_b = load i8, ptr %prev_ptr
  %prev_is_nl = icmp eq i8 %prev_b, 10
  br i1 %prev_is_nl, label %bol_pass, label %bol_fail

bol_pass:
  %pc_bol = add i64 %pc, 1
  call void @thread_set_state(ptr %t, i64 %pc_bol)
  %r_bol = call i64 @rx_addthread(ptr %list, i64 %listlen, ptr %gen, i64 %step, ptr %instrs, ptr %t, i64 %pos, ptr %text, i64 %text_len)
  ret i64 %r_bol

bol_fail:
  call void @thread_kill(ptr %t)
  ret i64 %listlen

; ---- EOL ($): pos==text_len, o byte actual=='\n' ----
; El GEP de cur solo se ejecuta con pos<text_len (is_end ya cubrió el
; final). pos vive en [0, text_len]: el runner arranca en 0 y solo
; avanza consumiendo con has_char.
do_eol:
  %is_end = icmp eq i64 %pos, %text_len
  br i1 %is_end, label %eol_pass, label %eol_check_nl

eol_check_nl:
  %cur_ptr = getelementptr i8, ptr %text, i64 %pos
  %cur_b = load i8, ptr %cur_ptr
  %cur_is_nl = icmp eq i8 %cur_b, 10
  br i1 %cur_is_nl, label %eol_pass, label %eol_fail

eol_pass:
  %pc_eol = add i64 %pc, 1
  call void @thread_set_state(ptr %t, i64 %pc_eol)
  %r_eol = call i64 @rx_addthread(ptr %list, i64 %listlen, ptr %gen, i64 %step, ptr %instrs, ptr %t, i64 %pos, ptr %text, i64 %text_len)
  ret i64 %r_eol

eol_fail:
  call void @thread_kill(ptr %t)
  ret i64 %listlen

; ---- \b / \B: XOR entre "el byte de antes es de palabra" y "el de
; ahora lo es". arg1==0 pide boundary=true (\b), arg1==1 pide false (\B).
; Los bordes del texto cuentan como non-word: pos==0 hace wrap el prev
; (unsigned enorme -> rx_is_word_char da false por el rango) y
; pos==text_len falla el ult del after.
do_wordboundary:
  %a1w_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %a1w = load i64, ptr %a1w_ptr
  %pos_prev = sub i64 %pos, 1
  %before = call i1 @rx_is_word_char(ptr %text, i64 %text_len, i64 %pos_prev)
  %after = call i1 @rx_is_word_char(ptr %text, i64 %text_len, i64 %pos)
  %is_boundary = xor i1 %before, %after
  %want_boundary = icmp eq i64 %a1w, 0
  %condition_ok = icmp eq i1 %is_boundary, %want_boundary
  br i1 %condition_ok, label %wb_pass, label %wb_fail

wb_pass:
  %pc_wb = add i64 %pc, 1
  call void @thread_set_state(ptr %t, i64 %pc_wb)
  %r_wb = call i64 @rx_addthread(ptr %list, i64 %listlen, ptr %gen, i64 %step, ptr %instrs, ptr %t, i64 %pos, ptr %text, i64 %text_len)
  ret i64 %r_wb

wb_fail:
  call void @thread_kill(ptr %t)
  ret i64 %listlen

append:
  ; CHAR(0), CHAR_CLASS(5) o MATCH(4) -- terminales, entran a la lista.
  %slot_ptr3 = getelementptr ptr, ptr %list, i64 %listlen
  store ptr %t, ptr %slot_ptr3
  %newlen = add i64 %listlen, 1
  ret i64 %newlen
}

; ---------------------------------------------------------------------
; rx_is_word_char: [A-Za-z0-9_] en %pos, false si %pos está fuera de
; [0, text_len). %pos puede llegar "negativo" (wrap de i64 sin signo,
; ej. pos-1 cuando pos==0 desde do_wordboundary): un valor wrappeado es
; un unsigned enorme, nunca < text_len, así que el chequeo de rango ya
; lo cubre -- no hace falta chequear signo aparte.
; ---------------------------------------------------------------------
define internal i1 @rx_is_word_char(ptr %text, i64 %text_len, i64 %pos) {
entry:
  %in_range = icmp ult i64 %pos, %text_len
  br i1 %in_range, label %check_byte, label %ret_false

check_byte:
  %ptr = getelementptr i8, ptr %text, i64 %pos
  %b = load i8, ptr %ptr
  %ge_a = icmp uge i8 %b, 97
  %le_z = icmp ule i8 %b, 122
  %is_lower = and i1 %ge_a, %le_z
  %ge_A = icmp uge i8 %b, 65
  %le_Z = icmp ule i8 %b, 90
  %is_upper = and i1 %ge_A, %le_Z
  %ge_0 = icmp uge i8 %b, 48
  %le_9 = icmp ule i8 %b, 57
  %is_digit = and i1 %ge_0, %le_9
  %is_us = icmp eq i8 %b, 95
  %r1 = or i1 %is_lower, %is_upper
  %r2 = or i1 %r1, %is_digit
  %r3 = or i1 %r2, %is_us
  ret i1 %r3

ret_false:
  ret i1 false
}

; ---------------------------------------------------------------------
; rx_run: el loop principal de Pike's VM. Dos listas ping-pong (bufA/bufB,
; se turnan el rol de "actual"/"siguiente" vía phi -- mismo patrón que un
; swap de punteros en C, expresado en SSA), tamaño fijo = ninst (cota
; superior real: el dedup por gen[] garantiza que nunca hay más de un
; thread vivo por instrucción).
;
; Devuelve el %Thread* ganador (mayor prioridad que llegó a MATCH) o null
; si no matcheó nada. El caller es dueño del %Thread* devuelto: tiene que
; thread_kill() para liberar su %SaveBuf, este runner no lo hace.
;
; No exportada como "internal" a propósito: los entry points públicos de
; este archivo pasan siempre por rx_match_and_get, pero dejar rx_run
; visible permite testear el motor del NFA por separado, con un
; %RxProgram armado a mano, sin pasar por el parser.
; ---------------------------------------------------------------------
define ptr @rx_run(ptr %prog, ptr %text, i64 %text_len) {
entry:
  %instrs_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 0
  %instrs = load ptr, ptr %instrs_ptr
  %count_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 1
  %ninst = load i64, ptr %count_ptr
  %ng_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 2
  %num_groups = load i64, ptr %ng_ptr
  %nsaves = mul i64 %num_groups, 2

  %gen = call ptr @rx_alloc_gen(i64 %ninst)
  %buf_bytes = mul i64 %ninst, 8
  %bufA = call ptr @malloc(i64 %buf_bytes)
  %bufB = call ptr @malloc(i64 %buf_bytes)

  %t0 = call ptr @thread_create(i64 0, i64 %nsaves)
  %clist_len0 = call i64 @rx_addthread(ptr %bufA, i64 0, ptr %gen, i64 0, ptr %instrs, ptr %t0, i64 0, ptr %text, i64 %text_len)

  br label %outer_check

outer_check:
  %cur_buf = phi ptr [ %bufA, %entry ], [ %nxt_buf, %outer_latch ]
  %nxt_buf = phi ptr [ %bufB, %entry ], [ %cur_buf, %outer_latch ]
  %cur_len = phi i64 [ %clist_len0, %entry ], [ %nxt_len_final, %outer_latch ]
  %step    = phi i64 [ 1, %entry ], [ %step2, %outer_latch ]
  %matched = phi ptr [ null, %entry ], [ %matched_final_step, %outer_latch ]
  %pos     = phi i64 [ 0, %entry ], [ %pos2, %outer_latch ]

  %is_empty = icmp eq i64 %cur_len, 0
  br i1 %is_empty, label %outer_end, label %outer_body

outer_body:
  %has_char = icmp slt i64 %pos, %text_len
  br i1 %has_char, label %load_char, label %skip_char

load_char:
  %char_ptr = getelementptr i8, ptr %text, i64 %pos
  %char_i8 = load i8, ptr %char_ptr
  %char_ext = zext i8 %char_i8 to i64
  br label %inner_check

skip_char:
  br label %inner_check

inner_check:
  %c = phi i64 [ %char_ext, %load_char ], [ 0, %skip_char ]
  br label %inner_loop_check

inner_loop_check:
  %i = phi i64 [ 0, %inner_check ], [ %i_next, %inner_loop_latch ]
  %nxt_len = phi i64 [ 0, %inner_check ], [ %nxt_len_merged, %inner_loop_latch ]
  %matched_i = phi ptr [ %matched, %inner_check ], [ %matched_i, %inner_loop_latch ]
  %i_lt = icmp slt i64 %i, %cur_len
  br i1 %i_lt, label %inner_body, label %inner_loop_end

inner_body:
  %t_ptr = getelementptr ptr, ptr %cur_buf, i64 %i
  %t = load ptr, ptr %t_ptr
  %pc = call i64 @thread_state(ptr %t)
  %inst_ptr = getelementptr %RxInst, ptr %instrs, i64 %pc
  %op_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 0
  %opcode = load i64, ptr %op_ptr
  switch i64 %opcode, label %op_default [
    i64 0, label %op_char
    i64 4, label %op_match
    i64 5, label %op_charclass
  ]

op_char:
  %a1_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %arg1 = load i64, ptr %a1_ptr
  %char_matches = icmp eq i64 %arg1, %c
  %can_consume = and i1 %has_char, %char_matches
  br i1 %can_consume, label %char_advance, label %char_kill

op_charclass:
  ; opcode 5: CHAR_CLASS. arg1 = int del ptr al bitset (copia que hizo
  ; e_charclass en regex_compiler.ll; dueño = el programa -> NO liberar
  ; acá, rx_program_destroy se encarga). Consumidor como CHAR, pero el
  ; test es de bitset. Nota: %c es 0 cuando no hay byte -- cc_can exige
  ; has_char, así que a fin de texto nunca consume (una clase que
  ; contenga el byte 0 no matchea el "final").
  %a1cc_ptr = getelementptr %RxInst, ptr %inst_ptr, i32 0, i32 1
  %arg1cc = load i64, ptr %a1cc_ptr
  %bs_cc = inttoptr i64 %arg1cc to ptr
  %c_cc_i8 = trunc i64 %c to i8
  %cc_hit = call i1 @rx_charclass_test(ptr %bs_cc, i8 %c_cc_i8)
  %cc_can = and i1 %has_char, %cc_hit
  br i1 %cc_can, label %char_advance, label %char_kill

char_advance:
  %pc1 = add i64 %pc, 1
  call void @thread_set_state(ptr %t, i64 %pc1)
  %pos1 = add i64 %pos, 1
  %nxt_len1 = call i64 @rx_addthread(ptr %nxt_buf, i64 %nxt_len, ptr %gen, i64 %step, ptr %instrs, ptr %t, i64 %pos1, ptr %text, i64 %text_len)
  br label %inner_continue

char_kill:
  call void @thread_kill(ptr %t)
  br label %inner_continue

op_match:
  %has_prev_match = icmp ne ptr %matched_i, null
  br i1 %has_prev_match, label %kill_prev_match, label %set_match

kill_prev_match:
  call void @thread_kill(ptr %matched_i)
  br label %set_match

set_match:
  ; todo lo que queda en cur_buf después de %i tiene prioridad menor que
  ; este MATCH -- no puede ganar, se mata y se corta el inner loop acá.
  %kill_from = add i64 %i, 1
  call void @rx_kill_range(ptr %cur_buf, i64 %kill_from, i64 %cur_len)
  br label %inner_loop_stopped

op_default:
  ; JMP/SPLIT/SAVE/BOL/EOL/WB nunca deberían llegar a una lista --
  ; rx_addthread los resuelve por clausura épsilon antes de anexar nada.
  ; Defensivo: si pasara (bug en otro lado), no queremos trapear el
  ; proceso entero por un thread individual corrupto, así que se lo mata
  ; y se sigue.
  call void @thread_kill(ptr %t)
  br label %inner_continue

inner_continue:
  %nxt_len_merged = phi i64 [ %nxt_len1, %char_advance ], [ %nxt_len, %char_kill ], [ %nxt_len, %op_default ]
  %i_next = add i64 %i, 1
  br label %inner_loop_latch

inner_loop_latch:
  br label %inner_loop_check

inner_loop_end:
  br label %inner_merge

inner_loop_stopped:
  br label %inner_merge

inner_merge:
  %nxt_len_final = phi i64 [ %nxt_len, %inner_loop_end ], [ %nxt_len, %inner_loop_stopped ]
  %matched_final_step = phi ptr [ %matched_i, %inner_loop_end ], [ %t, %inner_loop_stopped ]
  %step2 = add i64 %step, 1
  %pos2 = add i64 %pos, 1
  %continue_cond = icmp sle i64 %pos2, %text_len
  br i1 %continue_cond, label %outer_latch, label %outer_end2

outer_latch:
  br label %outer_check

outer_end2:
  br label %outer_end

outer_end:
  %final_matched = phi ptr [ %matched, %outer_check ], [ %matched_final_step, %outer_end2 ]
  call void @free(ptr %gen)
  call void @free(ptr %bufA)
  call void @free(ptr %bufB)
  ret ptr %final_matched
}

; ---------------------------------------------------------------------
; rx_match_and_get: compila el patrón, corre el NFA, extrae UN slot de
; saves del thread ganador, libera todo. -1 si no matchea (mismo
; sentinel que regex_compile_instruction_count/group_count).
;
; Recompila el patrón en cada llamada, igual que ya hacen
; regex_compile_instruction_count/group_count en regex_compiler.ll --
; mismo trade-off ya aceptado en ese archivo (simplicidad > performance
; en este estadio, no hay todavía un %RxProgram* persistente cacheable).
; ---------------------------------------------------------------------
define internal i64 @rx_match_and_get(ptr %pattern, i64 %plen, ptr %text, i64 %tlen, i64 %slot) {
entry:
  %prog = call ptr @regex_compile(ptr %pattern, i64 %plen)
  %is_null = icmp eq ptr %prog, null
  br i1 %is_null, label %ret_neg1, label %do_run

do_run:
  %matched = call ptr @rx_run(ptr %prog, ptr %text, i64 %tlen)
  %no_match = icmp eq ptr %matched, null
  br i1 %no_match, label %cleanup_nomatch, label %cleanup_match

cleanup_nomatch:
  call void @rx_program_destroy(ptr %prog)
  ret i64 -1

cleanup_match:
  %val = call i64 @thread_get_save(ptr %matched, i64 %slot)
  call void @thread_kill(ptr %matched)
  call void @rx_program_destroy(ptr %prog)
  ret i64 %val

ret_neg1:
  ret i64 -1
}

; ================= entry points públicos =================

; regex_match_end: -1 si "pattern" no matchea desde el inicio de "text";
; si matchea, la posición donde termina el match (equivalente a la
; longitud, porque el match siempre arranca en 0 -- 100% anclado).
define i64 @regex_match_end(ptr %pattern, i64 %plen, ptr %text, i64 %tlen) {
entry:
  %r = call i64 @rx_match_and_get(ptr %pattern, i64 %plen, ptr %text, i64 %tlen, i64 1)
  ret i64 %r
}

; regex_match_group_start / _end: arranque/fin del grupo %group (0 = grupo
; implícito, todo el match; 1+ = grupos de usuario). -1 si no matcheó, o
; si el grupo nunca se ejecutó (ej. rama no tomada de una alternación).
define i64 @regex_match_group_start(ptr %pattern, i64 %plen, ptr %text, i64 %tlen, i64 %group) {
entry:
  %slot = mul i64 %group, 2
  %r = call i64 @rx_match_and_get(ptr %pattern, i64 %plen, ptr %text, i64 %tlen, i64 %slot)
  ret i64 %r
}

define i64 @regex_match_group_end(ptr %pattern, i64 %plen, ptr %text, i64 %tlen, i64 %group) {
entry:
  %slot0 = mul i64 %group, 2
  %slot = add i64 %slot0, 1
  %r = call i64 @rx_match_and_get(ptr %pattern, i64 %plen, ptr %text, i64 %tlen, i64 %slot)
  ret i64 %r
}
