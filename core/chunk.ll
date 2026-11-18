; core/chunk.ll — capa de chunks reales (Etapa B del modelo de Document sobre
; mmap). Un Chunk envuelve un TextBuffer* con el rango ORIGINAL que ocupa en
; el archivo mapeado; el TextBuffer puede crecer/encoger con ediciones y su
; diferencia de tamano se guarda en %delta.
;
; Los offsets que ve el usuario son OFFSETS ACTUALES (sobre la concatenacion
; de los TextBuffer de los chunks). Los offsets del mmap son ORIGINALES. Esta
; traduccion es el corazon del modulo:
;
;   orig -> actual:  suma de deltas de los chunks anteriormente + (o - start)
;   actual -> orig:  inverso
;
; Este modulo NO sabe de mmap ni de archivos (no llama a fsio_*): solo
; gestiona la lista de chunks y la traduccion. El mmap y la carga viven en
; fsio_posix.ll (Etapa A) y la orquestacion en document.ll (Etapa C).
;
; No usa `switch` -> no necesita -relocation-model=pic.
;
; %Chunk = { ptr tb, i64 orig_start, i64 orig_len, i64 delta,
;            i32 dirty, ptr next }   ; 48 bytes (6 campos, alineado)

%Chunk = type { ptr, i64, i64, i64, i32, ptr }

declare ptr @malloc(i64)
declare void @free(ptr)

;tamano real del chunk (orig_len + delta)
define internal i64 @chunk_current_len(ptr %c) {
entry:
  %lp = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 2
  %orig = load i64, ptr %lp
  %dp = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 3
  %delta = load i64, ptr %dp
  %cur = add i64 %orig, %delta
  ret i64 %cur
}

define ptr @chunk_new(ptr %tb, i64 %orig_start, i64 %orig_len) {
entry:
  %c = call ptr @malloc(i64 48)
  %n = icmp eq ptr %c, null
  br i1 %n, label %fail, label %init
fail:
  ret ptr null
init:
  %tb_p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 0
  store ptr %tb, ptr %tb_p
  %s_p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 1
  store i64 %orig_start, ptr %s_p
  %l_p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 2
  store i64 %orig_len, ptr %l_p
  %d_p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 3
  store i64 0, ptr %d_p
  %di_p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 4
  store i32 0, ptr %di_p
  %nx_p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 5
  store ptr null, ptr %nx_p
  ret ptr %c
}

define void @chunk_destroy(ptr %c) {
entry:
  call void @free(ptr %c)
  ret void
}

; --- getters / setters ---

define ptr @chunk_tb(ptr %c) {
entry:
  %p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 0
  %v = load ptr, ptr %p
  ret ptr %v
}

define i64 @chunk_orig_start(ptr %c) {
entry:
  %p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 1
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @chunk_orig_len(ptr %c) {
entry:
  %p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 2
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @chunk_delta(ptr %c) {
entry:
  %p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 3
  %v = load i64, ptr %p
  ret i64 %v
}

define i32 @chunk_is_dirty(ptr %c) {
entry:
  %p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 4
  %v = load i32, ptr %p
  ret i32 %v
}

define ptr @chunk_next(ptr %c) {
entry:
  %p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 5
  %v = load ptr, ptr %p
  ret ptr %v
}

; fija el tamano actual del chunk: delta = len - orig_len, y marca sucio.
define void @chunk_set_len(ptr %c, i64 %len) {
entry:
  %lp = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 2
  %orig = load i64, ptr %lp
  %d = sub i64 %len, %orig
  %dp = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 3
  store i64 %d, ptr %dp
  %dip = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 4
  store i32 1, ptr %dip
  ret void
}

define void @chunk_set_next(ptr %c, ptr %next) {
entry:
  %p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 5
  store ptr %next, ptr %p
  ret void
}

; total de bytes actuales de la lista (suma de orig_len + delta)
define i64 @chunk_total(ptr %head) {
entry:
  %acc = alloca i64
  store i64 0, ptr %acc
  %cur = alloca ptr
  store ptr %head, ptr %cur
  br label %loop
loop:
  %c = load ptr, ptr %cur
  %nul = icmp eq ptr %c, null
  br i1 %nul, label %done, label %body
body:
  %clen = call i64 @chunk_current_len(ptr %c)
  %a = load i64, ptr %acc
  %a2 = add i64 %a, %clen
  store i64 %a2, ptr %acc
  %nx = call ptr @chunk_next(ptr %c)
  store ptr %nx, ptr %cur
  br label %loop
done:
  %r = load i64, ptr %acc
  ret i64 %r
}

; ---------------------------------------------------------------------------
; chunk_to_actual: offset ORIGINAL -> offset ACTUAL (en la concatenacion de
; los TextBuffer). Recorre la lista sumando current_len de los chunks que
; quedan antes del que contiene %orig_off.
;
; El chunk que contiene %orig_off es el primero con
;   orig_start <= orig_off <= orig_start + orig_len
; (el '<=' del final incluye el '\n' compartido con el siguiente, mismo
; criterio que li_line_for_offset). Si %orig_off esta mas alla del final,
; devuelve el total actual.
; ---------------------------------------------------------------------------
define i64 @chunk_to_actual(ptr %head, i64 %orig_off) {
entry:
  %acc = alloca i64
  store i64 0, ptr %acc
  %cur = alloca ptr
  store ptr %head, ptr %cur
  br label %loop
loop:
  %c = load ptr, ptr %cur
  %nul = icmp eq ptr %c, null
  br i1 %nul, label %done, label %body
body:
  %start = call i64 @chunk_orig_start(ptr %c)
  %olen = call i64 @chunk_orig_len(ptr %c)
  %end = add i64 %start, %olen
  %nx2 = call ptr @chunk_next(ptr %c)
  %is_last = icmp eq ptr %nx2, null
  %ge = icmp uge i64 %orig_off, %start
  %lt = icmp ult i64 %orig_off, %end
  %in_body = and i1 %ge, %lt
  %at_end = icmp eq i64 %orig_off, %end
  %end_ok = and i1 %at_end, %is_last
  %inside = or i1 %in_body, %end_ok
  br i1 %inside, label %found, label %advance
advance:
  %clen = call i64 @chunk_current_len(ptr %c)
  %a = load i64, ptr %acc
  %a2 = add i64 %a, %clen
  store i64 %a2, ptr %acc
  %nx = call ptr @chunk_next(ptr %c)
  store ptr %nx, ptr %cur
  br label %loop
found:
  %a3 = load i64, ptr %acc
  %rel = sub i64 %orig_off, %start
  %res = add i64 %a3, %rel
  ret i64 %res
done:
  %r = load i64, ptr %acc
  ret i64 %r
}

; ---------------------------------------------------------------------------
; chunk_from_actual: offset ACTUAL -> offset ORIGINAL (inverso de arriba).
; Devuelve -1 si %actual_off esta mas alla del total.
; ---------------------------------------------------------------------------
define i64 @chunk_from_actual(ptr %head, i64 %actual_off) {
entry:
  %acc = alloca i64        ; offset original acumulado
  store i64 0, ptr %acc
  %cur = alloca ptr
  store ptr %head, ptr %cur
  br label %loop
loop:
  %c = load ptr, ptr %cur
  %nul = icmp eq ptr %c, null
  br i1 %nul, label %done, label %body
body:
  %start = call i64 @chunk_orig_start(ptr %c)
  %olen = call i64 @chunk_orig_len(ptr %c)
  %d_p = getelementptr inbounds %Chunk, ptr %c, i32 0, i32 3
  %delta = load i64, ptr %d_p
  %clen = call i64 @chunk_current_len(ptr %c)
  %a = load i64, ptr %acc
  %cur_end = add i64 %a, %clen
  %nx2 = call ptr @chunk_next(ptr %c)
  %is_last = icmp eq ptr %nx2, null
  %ge = icmp uge i64 %actual_off, %a
  %lt = icmp ult i64 %actual_off, %cur_end
  %in_body = and i1 %ge, %lt
  %at_end = icmp eq i64 %actual_off, %cur_end
  %end_ok = and i1 %at_end, %is_last
  %inside = or i1 %in_body, %end_ok
  br i1 %inside, label %found, label %advance
advance:
  ; %acc es un offset ACTUAL: avanza con current_len, no con orig_len.
  %a2 = add i64 %a, %clen
  store i64 %a2, ptr %acc
  %nx3 = call ptr @chunk_next(ptr %c)
  store ptr %nx3, ptr %cur
  br label %loop
found:
  ; %rel es desplazamiento dentro del chunk (actual). Los offsets originales
  ; dentro del chunk se mapean 1:1 hasta orig_len (el contenido insertado
  ; al final del chunk no tiene offset original correspondiente). El delta
  ; del chunk solo desplaza a los chunks SIGUIENTES, ya incluido en %acc.
  %rel = sub i64 %actual_off, %a
  %clamp = icmp sgt i64 %rel, %olen
  %d = select i1 %clamp, i64 %olen, i64 %rel
  %res = add i64 %start, %d
  ret i64 %res
done:
  ret i64 -1
}
