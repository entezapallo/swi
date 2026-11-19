; core/regex_thread.ll
;
; Capa de gestión de threads del NFA (Pike's algorithm), separada del runner
; (core/regex_runner.ll, todavía no escrito). El runner nunca gestiona
; memoria de `saves` directamente — pasa siempre por esta interfaz.
;
; Decisión de diseño (ver jotter-handoff.md, "pendiente inmediato" #2, que
; prevalece sobre la v1-copy-directo descripta en regex-spec.md):
;   COW + refcount desde el día 1, no copia simple diferida. Se determinó
;   que hace falta desde ya por cómo abregex va a componer macros con
;   conteos de grupos variables/grandes.
;
; Estrategia:
;   - fork() NO copia `saves` — comparte el puntero e incrementa refcount.
;   - save() chequea refcount antes de escribir: si >1, clona el buffer
;     (copy-on-write) y decrementa el refcount del buffer viejo; si ==1,
;     escribe directo (dueño exclusivo, no hay nadie más leyendo esa copia).
;   - kill() decrementa refcount; libera el buffer de saves solo cuando
;     refcount llega a 0. Libera el struct %Thread siempre (nunca es
;     compartido — solo `saves` lo es).
;
; No hay concurrencia real (threads del NFA = threads lógicos de Pike's,
; avance secuencial de a uno), así que el refcount no necesita ser atómico.
;
; No usa `switch` -> no necesita -relocation-model=pic en el target del
; Makefile.

declare ptr @malloc(i64)
declare void @free(ptr)

; %SaveBuf: buffer de captura compartido por COW.
;   i32       refcount  -- contador interno, no cruza a regex_compiler.ll,
;                          se deja en i32 a propósito (no hace falta i64)
;   [0 x i64] slots      -- flexible array, tamaño real = nsaves * i64.
;                           i64 para matchear el ancho de %RxInst (opcode/
;                           arg1/arg2 son i64 en regex_compiler.ll) y para
;                           poder guardar offsets de buffer grandes, igual
;                           que tb_length en textbuffer.ll.
; OJO: el layout real tiene padding de 4 bytes entre refcount (i32) y el
; array (i64, alineado a 8) -- por eso el tamaño de malloc se calcula con
; getelementptr sobre el offset real del campo, nunca a mano.
%SaveBuf = type { i32, [0 x i64] }

; %Thread: nunca compartido entre threads del NFA (cada fork produce un
; %Thread* propio); lo que se comparte es el %SaveBuf* que cuelga de él.
;   i64  state    -- pc actual en el NFA (índice en el array de %RxInst,
;                    i64 para matchear el ancho del array del compiler)
;   ptr  savebuf  -- %SaveBuf* (compartido, COW)
;   i64  nsaves   -- cantidad de slots de saves (2 * cantidad de grupos);
;                    fijo por programa, igual en todo fork de ese programa
%Thread = type { i64, ptr, i64 }

; ---------------------------------------------------------------------
; savebuf_alloc: aloca un %SaveBuf nuevo con refcount=1 y todos los slots
; en -1 (slot "sin escribir todavía", convención estándar de Pike's saves).
; Interna, no forma parte de la interfaz pública del módulo.
; ---------------------------------------------------------------------
define internal ptr @savebuf_alloc(i64 %nsaves) {
entry:
  ; tamaño real = offset del campo 'slots' (incluye el padding que el
  ; compilador inserte para alinear i64) + nsaves * 8. Nunca a mano.
  %off_ptr    = getelementptr %SaveBuf, ptr null, i32 0, i32 1
  %base_off   = ptrtoint ptr %off_ptr to i64
  %elems_size = mul i64 %nsaves, 8
  %size       = add i64 %base_off, %elems_size
  %buf        = call ptr @malloc(i64 %size)

  %refcount_ptr = getelementptr %SaveBuf, ptr %buf, i32 0, i32 0
  store i32 1, ptr %refcount_ptr

  br label %loop_check

loop_check:
  %i = phi i64 [ 0, %entry ], [ %i_next, %loop_body ]
  %cond = icmp slt i64 %i, %nsaves
  br i1 %cond, label %loop_body, label %loop_end

loop_body:
  %slot_ptr = getelementptr %SaveBuf, ptr %buf, i32 0, i32 1, i64 %i
  store i64 -1, ptr %slot_ptr
  %i_next = add i64 %i, 1
  br label %loop_check

loop_end:
  ret ptr %buf
}

; ---------------------------------------------------------------------
; savebuf_clone: copia profunda de un %SaveBuf existente, refcount=1 en
; la copia. Usada por thread_save cuando el buffer viejo está compartido
; (refcount > 1) y hay que dejar de compartirlo antes de escribir.
; ---------------------------------------------------------------------
define internal ptr @savebuf_clone(ptr %src, i64 %nsaves) {
entry:
  %new = call ptr @savebuf_alloc(i64 %nsaves)
  br label %loop_check

loop_check:
  %i = phi i64 [ 0, %entry ], [ %i_next, %loop_body ]
  %cond = icmp slt i64 %i, %nsaves
  br i1 %cond, label %loop_body, label %loop_end

loop_body:
  %src_slot_ptr = getelementptr %SaveBuf, ptr %src, i32 0, i32 1, i64 %i
  %val          = load i64, ptr %src_slot_ptr
  %new_slot_ptr = getelementptr %SaveBuf, ptr %new, i32 0, i32 1, i64 %i
  store i64 %val, ptr %new_slot_ptr
  %i_next = add i64 %i, 1
  br label %loop_check

loop_end:
  ret ptr %new
}

; ---------------------------------------------------------------------
; thread_create: crea un thread nuevo, dueño exclusivo de su propio
; %SaveBuf (refcount=1). Punto de entrada para el runner al arrancar
; el NFA (thread inicial) o al necesitar un thread desde cero.
; ---------------------------------------------------------------------
define ptr @thread_create(i64 %state, i64 %nsaves) {
entry:
  %tsize_ptr = getelementptr %Thread, ptr null, i32 1
  %tsize     = ptrtoint ptr %tsize_ptr to i64
  %t         = call ptr @malloc(i64 %tsize)

  %savebuf = call ptr @savebuf_alloc(i64 %nsaves)

  %state_ptr   = getelementptr %Thread, ptr %t, i32 0, i32 0
  %savebuf_ptr = getelementptr %Thread, ptr %t, i32 0, i32 1
  %nsaves_ptr  = getelementptr %Thread, ptr %t, i32 0, i32 2

  store i64 %state,   ptr %state_ptr
  store ptr %savebuf, ptr %savebuf_ptr
  store i64 %nsaves,  ptr %nsaves_ptr

  ret ptr %t
}

; ---------------------------------------------------------------------
; thread_fork: COW real. NO copia el %SaveBuf — comparte el puntero e
; incrementa su refcount. El %Thread* devuelto es siempre nuevo (nunca
; compartido), con el mismo `state` que el padre (el runner lo pisa
; después según a qué rama del Split corresponda cada fork).
; ---------------------------------------------------------------------
define ptr @thread_fork(ptr %parent) {
entry:
  %p_state_ptr   = getelementptr %Thread, ptr %parent, i32 0, i32 0
  %p_savebuf_ptr = getelementptr %Thread, ptr %parent, i32 0, i32 1
  %p_nsaves_ptr  = getelementptr %Thread, ptr %parent, i32 0, i32 2

  %state   = load i64, ptr %p_state_ptr
  %savebuf = load ptr, ptr %p_savebuf_ptr
  %nsaves  = load i64, ptr %p_nsaves_ptr

  ; incref del savebuf compartido
  %refcount_ptr = getelementptr %SaveBuf, ptr %savebuf, i32 0, i32 0
  %rc           = load i32, ptr %refcount_ptr
  %rc_inc       = add i32 %rc, 1
  store i32 %rc_inc, ptr %refcount_ptr

  %tsize_ptr = getelementptr %Thread, ptr null, i32 1
  %tsize     = ptrtoint ptr %tsize_ptr to i64
  %child     = call ptr @malloc(i64 %tsize)

  %c_state_ptr   = getelementptr %Thread, ptr %child, i32 0, i32 0
  %c_savebuf_ptr = getelementptr %Thread, ptr %child, i32 0, i32 1
  %c_nsaves_ptr  = getelementptr %Thread, ptr %child, i32 0, i32 2

  store i64 %state,   ptr %c_state_ptr
  store ptr %savebuf, ptr %c_savebuf_ptr
  store i64 %nsaves,  ptr %c_nsaves_ptr

  ret ptr %child
}

; ---------------------------------------------------------------------
; thread_save: escribe %pos en el slot %slot de los saves de %t.
; Si el savebuf está compartido (refcount > 1): clona, decrementa el
; refcount del viejo (este thread deja de referenciarlo), engancha el
; clon (refcount=1) al %Thread, y escribe en el clon.
; Si no está compartido (refcount == 1): escribe directo, sin clonar.
; ---------------------------------------------------------------------
define void @thread_save(ptr %t, i64 %slot, i64 %pos) {
entry:
  %savebuf_ptr = getelementptr %Thread, ptr %t, i32 0, i32 1
  %nsaves_ptr  = getelementptr %Thread, ptr %t, i32 0, i32 2
  %savebuf     = load ptr, ptr %savebuf_ptr
  %nsaves      = load i64, ptr %nsaves_ptr

  %refcount_ptr = getelementptr %SaveBuf, ptr %savebuf, i32 0, i32 0
  %rc           = load i32, ptr %refcount_ptr
  %shared       = icmp sgt i32 %rc, 1
  br i1 %shared, label %do_cow, label %write_direct

do_cow:
  %clone = call ptr @savebuf_clone(ptr %savebuf, i64 %nsaves)

  ; este thread deja de apuntar al buffer viejo -> decref
  %rc_dec = sub i32 %rc, 1
  store i32 %rc_dec, ptr %refcount_ptr

  ; el clon es dueño exclusivo (refcount=1, ya seteado por savebuf_alloc)
  store ptr %clone, ptr %savebuf_ptr

  %clone_slot_ptr = getelementptr %SaveBuf, ptr %clone, i32 0, i32 1, i64 %slot
  store i64 %pos, ptr %clone_slot_ptr
  br label %done

write_direct:
  %direct_slot_ptr = getelementptr %SaveBuf, ptr %savebuf, i32 0, i32 1, i64 %slot
  store i64 %pos, ptr %direct_slot_ptr
  br label %done

done:
  ret void
}

; ---------------------------------------------------------------------
; thread_get_save: lectura de un slot. No participa de COW (lectura no
; muta), no hace falta chequear refcount.
; ---------------------------------------------------------------------
define i64 @thread_get_save(ptr %t, i64 %slot) {
entry:
  %savebuf_ptr = getelementptr %Thread, ptr %t, i32 0, i32 1
  %savebuf     = load ptr, ptr %savebuf_ptr
  %slot_ptr    = getelementptr %SaveBuf, ptr %savebuf, i32 0, i32 1, i64 %slot
  %val         = load i64, ptr %slot_ptr
  ret i64 %val
}

; ---------------------------------------------------------------------
; thread_state / thread_set_state: el runner necesita leer el pc para
; despachar sobre la instrucción del NFA, y pisarlo en cada fork antes
; de avanzar cada rama del Split (fork() clona el `state` del padre;
; el runner lo actualiza a la rama que corresponda).
; ---------------------------------------------------------------------
define i64 @thread_state(ptr %t) {
entry:
  %state_ptr = getelementptr %Thread, ptr %t, i32 0, i32 0
  %state     = load i64, ptr %state_ptr
  ret i64 %state
}

define void @thread_set_state(ptr %t, i64 %state) {
entry:
  %state_ptr = getelementptr %Thread, ptr %t, i32 0, i32 0
  store i64 %state, ptr %state_ptr
  ret void
}

; ---------------------------------------------------------------------
; thread_kill: decref del savebuf compartido; lo libera solo si llega a
; 0. El %Thread en sí nunca es compartido -> siempre se libera.
; ---------------------------------------------------------------------
define void @thread_kill(ptr %t) {
entry:
  %savebuf_ptr = getelementptr %Thread, ptr %t, i32 0, i32 1
  %savebuf     = load ptr, ptr %savebuf_ptr

  %refcount_ptr = getelementptr %SaveBuf, ptr %savebuf, i32 0, i32 0
  %rc           = load i32, ptr %refcount_ptr
  %rc_dec       = sub i32 %rc, 1
  store i32 %rc_dec, ptr %refcount_ptr

  %should_free = icmp eq i32 %rc_dec, 0
  br i1 %should_free, label %free_savebuf, label %skip_free

free_savebuf:
  call void @free(ptr %savebuf)
  br label %skip_free

skip_free:
  call void @free(ptr %t)
  ret void
}
