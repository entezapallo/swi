; core/chunk_plan.ll — traduce el esquema de chunking ya fijado en el
; handoff de GUI (60 líneas por chunk: 10 overlap atrás + 40 núcleo + 10
; overlap adelante, bordes de 50 líneas) a offsets de bytes vía
; LineIndex. Vive en core/ porque necesita li_line_offset/li_line_count --
; regex/ no puede conocer qué es una "línea" (regla fijada esta sesión:
; regex/ nunca depende de core/).
;
; Reusable tanto para find (scroll-con-prefetch) como para replace_all
; (barrido completo por chunks) -- mismo esquema, mismo código, un solo
; lugar donde vive la constante "40 núcleo / 10 overlap".

declare i64 @li_line_count(ptr)
declare i64 @li_line_offset(ptr, i64)
declare i64 @li_line_length(ptr, i64)

; dado un %chunk_index (0, 1, 2...) y el %li de un documento, calcula las
; 4 fronteras en OFFSETS DE BYTES (no líneas):
;   out_core_start/out_core_end   -- el rango "comiteable" (40 líneas)
;   out_scan_start/out_scan_end   -- el rango de búsqueda (60 líneas,
;                                     incluye el overlap de 10 a cada lado)
; out_done: 1 si %chunk_index ya pasó el final del documento (no hay más
; chunks, el caller debe parar el loop).
;
; Primer/último chunk: el overlap que caería fuera del documento
; simplemente se recorta (no hay línea -10 antes del inicio, ni +10
; después del final) -- el borde de 50 líneas mencionado en el handoff es
; la consecuencia natural de recortar un lado del overlap, no un caso
; especial aparte.
define void @chunk_plan(ptr %li, i64 %chunk_index,
                         ptr %out_core_start, ptr %out_core_end,
                         ptr %out_scan_start, ptr %out_scan_end,
                         ptr %out_done) {
entry:
  %total_lines = call i64 @li_line_count(ptr %li)

  ; núcleo de 40 líneas por chunk: el chunk N cubre las líneas
  ; [N*40, N*40+40) como su rango "comiteable"
  %core_line_start = mul i64 %chunk_index, 40
  %past_end = icmp sge i64 %core_line_start, %total_lines
  br i1 %past_end, label %done, label %compute

compute:
  %core_line_end_raw = add i64 %core_line_start, 40
  %core_overflow = icmp sgt i64 %core_line_end_raw, %total_lines
  %core_line_end = select i1 %core_overflow, i64 %total_lines, i64 %core_line_end_raw

  ; overlap de 10 líneas atrás, recortado en el borde izquierdo
  %scan_line_start_raw = sub i64 %core_line_start, 10
  %underflow = icmp slt i64 %scan_line_start_raw, 0
  %scan_line_start = select i1 %underflow, i64 0, i64 %scan_line_start_raw

  ; overlap de 10 líneas adelante, recortado en el borde derecho
  %scan_line_end_raw = add i64 %core_line_end, 10
  %scan_overflow = icmp sgt i64 %scan_line_end_raw, %total_lines
  %scan_line_end = select i1 %scan_overflow, i64 %total_lines, i64 %scan_line_end_raw

  ; traducir las 4 fronteras de línea a offset de byte
  %core_start_byte = call i64 @li_line_offset(ptr %li, i64 %core_line_start)
  %core_end_byte = call i64 @line_end_offset(ptr %li, i64 %core_line_end, i64 %total_lines)
  %scan_start_byte = call i64 @li_line_offset(ptr %li, i64 %scan_line_start)
  %scan_end_byte = call i64 @line_end_offset(ptr %li, i64 %scan_line_end, i64 %total_lines)

  store i64 %core_start_byte, ptr %out_core_start
  store i64 %core_end_byte, ptr %out_core_end
  store i64 %scan_start_byte, ptr %out_scan_start
  store i64 %scan_end_byte, ptr %out_scan_end
  store i64 0, ptr %out_done
  ret void

done:
  store i64 0, ptr %out_core_start
  store i64 0, ptr %out_core_end
  store i64 0, ptr %out_scan_start
  store i64 0, ptr %out_scan_end
  store i64 1, ptr %out_done
  ret void
}

; li_line_offset(li, N) da el INICIO de la línea N -- pero NO tiene
; bounds-checking (confirmado leyendo lineindex.ll): llamarlo con
; N == total_lines lee memoria fuera del array de entries. Cuando un
; chunk llega justo al final del documento, %line_idx acá ES total_lines
; -- hay que resolver ese caso sin tocar li_line_offset en ese borde:
; el final del documento es offset_de_la_última_línea + largo_de_esa_línea.
define internal i64 @line_end_offset(ptr %li, i64 %line_idx, i64 %total_lines) {
entry:
  %is_past_end = icmp uge i64 %line_idx, %total_lines
  br i1 %is_past_end, label %end_of_doc, label %normal

normal:
  %off = call i64 @li_line_offset(ptr %li, i64 %line_idx)
  ret i64 %off

end_of_doc:
  %has_lines = icmp sgt i64 %total_lines, 0
  br i1 %has_lines, label %from_last_line, label %empty_doc

from_last_line:
  %last_idx = sub i64 %total_lines, 1
  %last_off = call i64 @li_line_offset(ptr %li, i64 %last_idx)
  %last_len = call i64 @li_line_length(ptr %li, i64 %last_idx)
  %end = add i64 %last_off, %last_len
  ret i64 %end

empty_doc:
  ret i64 0
}
