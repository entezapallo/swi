; core/lineindex.ll — índice de offsets de línea sobre un TextBuffer.
; No sabe qué es Markdown ni interpreta el campo `flags` de cada línea —
; solo lo carga y lo devuelve. Ese campo es el endpoint abierto para que un
; parser externo (md_parser.ll, cuando exista) anote metadata por línea
; (heading level, blockquote, etc.) sin que lineindex.ll conozca esos conceptos.
;
; Recalcula el índice completo en cada rebuild (sin incrementalidad) — mismo
; criterio que el resto de core/: correcto por construcción, se optimiza
; solo si se mide que hace falta.

%LineEntry = type { i64, i64, i64 }   ; { offset, length (sin \n), flags }
%LineIndex = type { ptr, i64, i64, i64 } ; { entries, count, capacity, dirty (0=fresh, 1=rebuild pendiente) }

declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)

declare i64 @tb_length(ptr)
declare ptr @tb_data(ptr)

; ---- tamaño de %LineEntry en bytes: 3 x i64 = 24 ----

define ptr @li_create() {
entry:
  %li = call ptr @malloc(i64 32)   ; { ptr, i64, i64, i64 } = 8*4
  %entries_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 0
  store ptr null, ptr %entries_ptr
  %count_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 1
  store i64 0, ptr %count_ptr
  %cap_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 2
  store i64 0, ptr %cap_ptr
  %dirty_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 3
  store i64 0, ptr %dirty_ptr
  ret ptr %li
}

define void @li_destroy(ptr %li) {
entry:
  %entries_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %isnull = icmp eq ptr %entries, null
  br i1 %isnull, label %skip, label %dofree

dofree:
  call void @free(ptr %entries)
  br label %skip

skip:
  call void @free(ptr %li)
  ret void
}

define i64 @li_line_count(ptr %li) {
entry:
  %count_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  ret i64 %count
}

; sin chequeo de rango (%idx >= count es undefined behavior, responsabilidad
; de quien llama) — mismo criterio de "hot path sin overhead" que tb_data.
define i64 @li_line_offset(ptr %li, i64 %idx) {
entry:
  %entries_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %entry_ptr = getelementptr %LineEntry, ptr %entries, i64 %idx
  %off_ptr = getelementptr %LineEntry, ptr %entry_ptr, i32 0, i32 0
  %off = load i64, ptr %off_ptr
  ret i64 %off
}

define i64 @li_line_length(ptr %li, i64 %idx) {
entry:
  %entries_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %entry_ptr = getelementptr %LineEntry, ptr %entries, i64 %idx
  %len_ptr = getelementptr %LineEntry, ptr %entry_ptr, i32 0, i32 1
  %len = load i64, ptr %len_ptr
  ret i64 %len
}

; ---------------------------------------------------------------------------
; li_line_for_offset: dado un offset de byte en el TextBuffer, devuelve el
; INDICE DE LINEA (0-based) que lo contiene. Busqueda binaria O(log lineas)
; sobre el array de LineEntry.
;
; Una linea i cubre [offset_i, offset_i + length_i]. Para las lineas con '\n',
; offset_i + length_i es la posicion del '\n', que es compartida con el inicio
; de la siguiente como "fin de la anterior". Resolucion del empate: el '\n'
; pertenece a la linea que lo cierra (la anterior), no a la siguiente. Eso se
; logra comparando `pos > fin_de_la_linea_anterior` al decidir.
;
; Casos borde:
;   count == 0          -> 0  (buffer vacio, mismo criterio que ew_line_at)
;   pos < 0             -> se clamptea a 0
;   pos > fin del buffer-> ultima linea (count-1)
; ---------------------------------------------------------------------------
define i64 @li_line_for_offset(ptr %li, i64 %pos) {
entry:
  %cp = getelementptr %LineIndex, ptr %li, i32 0, i32 1
  %count = load i64, ptr %cp
  %empty = icmp eq i64 %count, 0
  br i1 %empty, label %ret0, label %clamp
ret0:
  ret i64 0
clamp:
  %neg = icmp slt i64 %pos, 0
  %p0 = select i1 %neg, i64 0, i64 %pos
  %last = sub i64 %count, 1
  br label %loop

loop:
  %lo = phi i64 [ 0, %clamp ], [ %lo_next, %go_right ], [ %lo, %go_left ]
  %hi = phi i64 [ %last, %clamp ], [ %hi, %go_right ], [ %hi_next, %go_left ]
  %cont = icmp sle i64 %lo, %hi
  br i1 %cont, label %mid_check, label %fallback

mid_check:
  %range = sub i64 %hi, %lo
  %half = sdiv i64 %range, 2
  %mid = add i64 %lo, %half
  %off = call i64 @li_line_offset(ptr %li, i64 %mid)
  %len = call i64 @li_line_length(ptr %li, i64 %mid)
  %end = add i64 %off, %len
  %in_this = icmp sle i64 %p0, %end
  br i1 %in_this, label %check_prev, label %go_right

check_prev:
  %mid_zero = icmp eq i64 %mid, 0
  br i1 %mid_zero, label %found, label %prev_end
prev_end:
  %pm1 = sub i64 %mid, 1
  %poff = call i64 @li_line_offset(ptr %li, i64 %pm1)
  %plen = call i64 @li_line_length(ptr %li, i64 %pm1)
  %pend = add i64 %poff, %plen
  %past_prev = icmp sgt i64 %p0, %pend
  br i1 %past_prev, label %found, label %go_left

go_right:
  %lo_next = add i64 %mid, 1
  br label %loop
go_left:
  %hi_next = sub i64 %mid, 1
  br label %loop

found:
  ret i64 %mid
fallback:
  ret i64 %last
}

; --- endpoint abierto para markdown / cualquier consumidor futuro ---
; lineindex.ll no interpreta este valor, solo lo guarda y lo devuelve.

define i64 @li_line_flags(ptr %li, i64 %idx) {
entry:
  %entries_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %entry_ptr = getelementptr %LineEntry, ptr %entries, i64 %idx
  %flags_ptr = getelementptr %LineEntry, ptr %entry_ptr, i32 0, i32 2
  %flags = load i64, ptr %flags_ptr
  ret i64 %flags
}

define void @li_set_line_flags(ptr %li, i64 %idx, i64 %flags) {
entry:
  %entries_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %entry_ptr = getelementptr %LineEntry, ptr %entries, i64 %idx
  %flags_ptr = getelementptr %LineEntry, ptr %entry_ptr, i32 0, i32 2
  store i64 %flags, ptr %flags_ptr
  ret void
}

; li_rebuild: recalcula el índice completo escaneando %tb de punta a punta.
; Los flags de cada línea se resetean a 0 en cada rebuild — un consumidor
; (ej. md_parser) que necesite flags persistentes entre rebuilds tiene que
; recalcularlos también, li_rebuild no los preserva (evita estado inconsistente
; si cambia el número de líneas o su orden).
; Devuelve i32 (1=ok, 0=fail por allocación).

; li_clear_dirty: marca el indice como al dia tras un rebuild.
define internal void @li_clear_dirty(ptr %li) {
entry:
  %p = getelementptr %LineIndex, ptr %li, i32 0, i32 3
  store i64 0, ptr %p
  ret void
}

define i32 @li_rebuild(ptr %li, ptr %tb) {
entry:
  %tblen = call i64 @tb_length(ptr %tb)
  %tbdata = call ptr @tb_data(ptr %tb)
  %ok = call i32 @li_rebuild_buf(ptr %li, ptr %tbdata, i64 %tblen)
  ret i32 %ok
}

; ---------------------------------------------------------------------------
; li_rebuild_doc: reconstruye el índice leyendo el contenido del Document via
; doc_read() (la interfaz de contenido multi-chunk). Migracion de la Etapa D:
; lineindex ya NO depende de tb_data del Document, solo de su API de lectura.
; Nota: hoy se materializa un buffer temporal; el escaneo por bloques (sin
; copia completa) es una optimizacion posterior. Lo importante es que el
; consumidor pasa por doc_read, igual que win_editor.
; ---------------------------------------------------------------------------
declare i64 @doc_read(ptr, i64, i64, ptr)
declare i64 @doc_length(ptr)

; helper: devuelve el byte en %pos leyendo bloques de 4096 via doc_read.
; %buf es un buffer de 4096 provisto por el llamador; %win_start/%win_len
; guardan el bloque actualmente cargado (se recarga solo cuando %pos sale).
define internal i8 @li_read_byte(ptr %doc, i64 %pos, ptr %buf,
                                  ptr %win_start, ptr %win_len) {
entry:
  %ws = load i64, ptr %win_start
  %wl = load i64, ptr %win_len
  %rel = sub i64 %pos, %ws
  %in_block = icmp uge i64 %rel, %wl
  br i1 %in_block, label %reload, label %get
reload:
  %got = call i64 @doc_read(ptr %doc, i64 %pos, i64 4096, ptr %buf)
  store i64 %pos, ptr %win_start
  store i64 %got, ptr %win_len
  br label %get
get:
  %ws2 = load i64, ptr %win_start
  %r2 = sub i64 %pos, %ws2
  %p = getelementptr i8, ptr %buf, i64 %r2
  %b = load i8, ptr %p
  ret i8 %b
}

; li_rebuild_doc por bloques: NO materializa el archivo completo. Mantiene
; un buffer de 4096 y relena via li_read_byte. Dos pasadas (contar / llenar)
; identicas a li_rebuild_buf pero leyendo byte a byte del Document.
define i32 @li_rebuild_doc(ptr %li, ptr %doc) {
entry:
  %len = call i64 @doc_length(ptr %doc)
  %buf = alloca [4096 x i8]
  %bufp = getelementptr [4096 x i8], ptr %buf, i32 0, i32 0
  %ws = alloca i64
  store i64 -1, ptr %ws
  %wl = alloca i64
  store i64 0, ptr %wl
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %set_empty, label %count_init

set_empty:
  %cpe = getelementptr %LineIndex, ptr %li, i32 0, i32 1
  store i64 0, ptr %cpe
  call void @li_clear_dirty(ptr %li)
  ret i32 1

count_init:
  br label %count_loop
count_loop:
  %cpos = phi i64 [ 0, %count_init ], [ %cpn, %count_next ]
  %ccount = phi i64 [ 1, %count_init ], [ %ccn, %count_next ]
  %cdone = icmp uge i64 %cpos, %len
  br i1 %cdone, label %alloc_entries, label %count_body
count_body:
  %cb = call i8 @li_read_byte(ptr %doc, i64 %cpos, ptr %bufp, ptr %ws, ptr %wl)
  %is_nl = icmp eq i8 %cb, 10
  br i1 %is_nl, label %count_incr, label %count_next
count_incr:
  %cci = add i64 %ccount, 1
  br label %count_next
count_next:
  %ccn = phi i64 [ %cci, %count_incr ], [ %ccount, %count_body ]
  %cpn = add i64 %cpos, 1
  br label %count_loop

alloc_entries:
  %final_count = phi i64 [ %ccount, %count_loop ]
  %bytes = mul i64 %final_count, 24
  %entries_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 0
  %old = load ptr, ptr %entries_ptr
  %new = call ptr @realloc(ptr %old, i64 %bytes)
  %ok = icmp ne ptr %new, null
  br i1 %ok, label %store_entries, label %fail
store_entries:
  store ptr %new, ptr %entries_ptr
  %cp2 = getelementptr %LineIndex, ptr %li, i32 0, i32 1
  store i64 %final_count, ptr %cp2
  %cap2 = getelementptr %LineIndex, ptr %li, i32 0, i32 2
  store i64 %final_count, ptr %cap2
  br label %fill_init

fill_init:
  br label %fill_loop
fill_loop:
  %fpos = phi i64 [ 0, %fill_init ], [ %fpos_next, %fill_merge ]
  %fidx = phi i64 [ 0, %fill_init ], [ %fidx_next, %fill_merge ]
  %fstart = phi i64 [ 0, %fill_init ], [ %fstart_next, %fill_merge ]
  %fdone = icmp uge i64 %fpos, %len
  br i1 %fdone, label %fill_last, label %fill_body
fill_body:
  %fb = call i8 @li_read_byte(ptr %doc, i64 %fpos, ptr %bufp, ptr %ws, ptr %wl)
  %fis_nl = icmp eq i8 %fb, 10
  br i1 %fis_nl, label %fill_nl, label %fill_plain
fill_nl:
  %flen = sub i64 %fpos, %fstart
  call void @li_write_entry(ptr %new, i64 %fidx, i64 %fstart, i64 %flen)
  %fi1 = add i64 %fidx, 1
  %fp1 = add i64 %fpos, 1
  %fs1 = add i64 %fpos, 1
  br label %fill_merge
fill_plain:
  %fpp = add i64 %fpos, 1
  br label %fill_merge
fill_merge:
  %fpos_next = phi i64 [ %fp1, %fill_nl ], [ %fpp, %fill_plain ]
  %fidx_next = phi i64 [ %fi1, %fill_nl ], [ %fidx, %fill_plain ]
  %fstart_next = phi i64 [ %fs1, %fill_nl ], [ %fstart, %fill_plain ]
  br label %fill_loop
fill_last:
  %lastlen = sub i64 %len, %fstart
  call void @li_write_entry(ptr %new, i64 %fidx, i64 %fstart, i64 %lastlen)
  call void @li_clear_dirty(ptr %li)
  ret i32 1
fail:
  ret i32 0
}

; helper real: escanea un buffer contiguo (ptr, len). Lo usan li_rebuild
; (TextBuffer) y li_rebuild_doc (contenido leido via doc_read).
define internal i32 @li_rebuild_buf(ptr %li, ptr %tbdata, i64 %tblen) {
entry:
  ; primera pasada: contar líneas (contar '\n' + 1, salvo buffer vacío -> 0 líneas)
  %is_empty = icmp eq i64 %tblen, 0
  br i1 %is_empty, label %set_empty, label %count_init

count_init:
  br label %count_loop

count_loop:
  %cpos = phi i64 [ 0, %count_init ], [ %cpos_next, %count_next ]
  %ccount = phi i64 [ 1, %count_init ], [ %ccount_next, %count_next ]
  %cdone = icmp uge i64 %cpos, %tblen
  br i1 %cdone, label %alloc_entries, label %count_check

count_check:
  %cptr = getelementptr i8, ptr %tbdata, i64 %cpos
  %cbyte = load i8, ptr %cptr
  %is_nl = icmp eq i8 %cbyte, 10   ; '\n' = 10
  br i1 %is_nl, label %count_incr, label %count_next

count_incr:
  %ccount_incr = add i64 %ccount, 1
  br label %count_next

count_next:
  %ccount_next = phi i64 [ %ccount_incr, %count_incr ], [ %ccount, %count_check ]
  %cpos_next = add i64 %cpos, 1
  br label %count_loop

alloc_entries:
  %final_count = phi i64 [ %ccount, %count_loop ]
  %needed_bytes = mul i64 %final_count, 24
  %entries_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 0
  %old_entries = load ptr, ptr %entries_ptr
  %new_entries = call ptr @realloc(ptr %old_entries, i64 %needed_bytes)
  %alloc_ok = icmp ne ptr %new_entries, null
  br i1 %alloc_ok, label %store_entries, label %fail

store_entries:
  store ptr %new_entries, ptr %entries_ptr
  %count_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 1
  store i64 %final_count, ptr %count_ptr
  %cap_ptr = getelementptr %LineIndex, ptr %li, i32 0, i32 2
  store i64 %final_count, ptr %cap_ptr
  br label %fill_init

fill_init:
  br label %fill_loop

; segunda pasada: recorrer de nuevo, esta vez escribiendo offset/length/flags=0
; por cada línea encontrada.
fill_loop:
  %fpos = phi i64 [ 0, %fill_init ], [ %fpos_next, %fill_merge ]
  %fline_idx = phi i64 [ 0, %fill_init ], [ %fline_idx_next, %fill_merge ]
  %fline_start = phi i64 [ 0, %fill_init ], [ %fline_start_next, %fill_merge ]
  %fdone = icmp uge i64 %fpos, %tblen
  br i1 %fdone, label %fill_last, label %fill_check

fill_check:
  %fptr = getelementptr i8, ptr %tbdata, i64 %fpos
  %fbyte = load i8, ptr %fptr
  %fis_nl = icmp eq i8 %fbyte, 10
  br i1 %fis_nl, label %fill_newline, label %fill_plain

fill_newline:
  %flinelen = sub i64 %fpos, %fline_start
  call void @li_write_entry(ptr %new_entries, i64 %fline_idx, i64 %fline_start, i64 %flinelen)
  %fline_idx_nl = add i64 %fline_idx, 1
  %fpos_nl = add i64 %fpos, 1
  %fline_start_nl = add i64 %fpos, 1
  br label %fill_merge

fill_plain:
  %fpos_plain = add i64 %fpos, 1
  br label %fill_merge

fill_merge:
  %fpos_next = phi i64 [ %fpos_nl, %fill_newline ], [ %fpos_plain, %fill_plain ]
  %fline_idx_next = phi i64 [ %fline_idx_nl, %fill_newline ], [ %fline_idx, %fill_plain ]
  %fline_start_next = phi i64 [ %fline_start_nl, %fill_newline ], [ %fline_start, %fill_plain ]
  br label %fill_loop

fill_last:
  ; última línea: desde %fline_start hasta %tblen (sin '\n' final, o buffer sin '\n' final)
  %flastlen = sub i64 %tblen, %fline_start
  call void @li_write_entry(ptr %new_entries, i64 %fline_idx, i64 %fline_start, i64 %flastlen)
  call void @li_clear_dirty(ptr %li)
  ret i32 1

set_empty:
  %count_ptr2 = getelementptr %LineIndex, ptr %li, i32 0, i32 1
  store i64 0, ptr %count_ptr2
  call void @li_clear_dirty(ptr %li)
  ret i32 1

fail:
  ret i32 0
}

; helper interno: escribe offset/length en la entrada %idx y resetea flags=0.
define void @li_write_entry(ptr %entries, i64 %idx, i64 %offset, i64 %length) {
entry:
  %entry_ptr = getelementptr %LineEntry, ptr %entries, i64 %idx
  %off_ptr = getelementptr %LineEntry, ptr %entry_ptr, i32 0, i32 0
  store i64 %offset, ptr %off_ptr
  %len_ptr = getelementptr %LineEntry, ptr %entry_ptr, i32 0, i32 1
  store i64 %length, ptr %len_ptr
  %flags_ptr = getelementptr %LineEntry, ptr %entry_ptr, i32 0, i32 2
  store i64 0, ptr %flags_ptr
  ret void
}
