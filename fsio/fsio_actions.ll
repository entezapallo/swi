; fsio/fsio_actions.ll — utilidades genéricas de filesystem, sin saber nada
; de macros/regex/lo que sea. Mismo estilo que fsio_posix.ll: mueve i8*/i64
; crudo, dueño de lo malloc'd es quien llama.

declare i32 @unlink(ptr)
declare ptr @__errno_location()
declare i64 @strlen(ptr)
declare ptr @malloc(i64)
declare void @free(ptr)

; concatena %dir + "/" + %name en un string malloc'd nuevo, NUL-terminado.
; No valida que %dir termine o no en "/" — asume que NO termina en "/"
; (convención: los paths de directorio que entran acá vienen sin barra
; final, como devuelve fsio_list_dir/lo que arma el caller).
define ptr @fsio_path_join(ptr %dir, ptr %name) {
entry:
  %dir_len = call i64 @strlen(ptr %dir)
  %name_len = call i64 @strlen(ptr %name)
  %total = add i64 %dir_len, %name_len
  %total1 = add i64 %total, 2     ; '/' + NUL
  %buf = call ptr @malloc(i64 %total1)

  br label %copy_dir

copy_dir:
  %di = phi i64 [ 0, %entry ], [ %di_next, %copy_dir_byte ]
  %di_done = icmp uge i64 %di, %dir_len
  br i1 %di_done, label %put_slash, label %copy_dir_byte

copy_dir_byte:
  %dsrc = getelementptr i8, ptr %dir, i64 %di
  %ddst = getelementptr i8, ptr %buf, i64 %di
  %dv = load i8, ptr %dsrc
  store i8 %dv, ptr %ddst
  %di_next = add i64 %di, 1
  br label %copy_dir

put_slash:
  %slash_ptr = getelementptr i8, ptr %buf, i64 %dir_len
  store i8 47, ptr %slash_ptr    ; '/'
  %name_start = add i64 %dir_len, 1
  br label %copy_name

copy_name:
  %ni = phi i64 [ 0, %put_slash ], [ %ni_next, %copy_name_byte ]
  %ni_done = icmp uge i64 %ni, %name_len
  br i1 %ni_done, label %put_nul, label %copy_name_byte

copy_name_byte:
  %nsrc = getelementptr i8, ptr %name, i64 %ni
  %ndst_off = add i64 %name_start, %ni
  %ndst = getelementptr i8, ptr %buf, i64 %ndst_off
  %nv = load i8, ptr %nsrc
  store i8 %nv, ptr %ndst
  %ni_next = add i64 %ni, 1
  br label %copy_name

put_nul:
  %nul_off = add i64 %name_start, %name_len
  %nul_ptr = getelementptr i8, ptr %buf, i64 %nul_off
  store i8 0, ptr %nul_ptr
  ret ptr %buf
}

; 1 si %name termina en %ext (ambos NUL-terminados), 0 si no. Comparación
; exacta de sufijo, sin normalizar mayúsculas/minúsculas.
define i32 @fsio_has_suffix(ptr %name, ptr %ext) {
entry:
  %name_len = call i64 @strlen(ptr %name)
  %ext_len = call i64 @strlen(ptr %ext)
  %long_enough = icmp uge i64 %name_len, %ext_len
  br i1 %long_enough, label %cmp_init, label %no

cmp_init:
  %off = sub i64 %name_len, %ext_len
  br label %cmp_loop

cmp_loop:
  %i = phi i64 [ 0, %cmp_init ], [ %i_next, %cmp_next ]
  %done = icmp uge i64 %i, %ext_len
  br i1 %done, label %yes, label %cmp_byte

cmp_byte:
  %name_off = add i64 %off, %i
  %np = getelementptr i8, ptr %name, i64 %name_off
  %ep = getelementptr i8, ptr %ext, i64 %i
  %nv = load i8, ptr %np
  %ev = load i8, ptr %ep
  %eq = icmp eq i8 %nv, %ev
  br i1 %eq, label %cmp_next, label %no

cmp_next:
  %i_next = add i64 %i, 1
  br label %cmp_loop

yes:
  ret i32 1
no:
  ret i32 0
}

; filtra %names (array de %count ptr) dejando solo los que terminan en %ext.
; out_names recibe array malloc'd NUEVO (mismos punteros que %names, no se
; clonan strings — ojo, quien libere después tiene que liberar los strings
; originales de %names completo, no los de out_names, para no double-free;
; liberar solo el array out_names en sí con free() normal, no
; fsio_free_dir_list). out_count recibe la cantidad filtrada.
define void @fsio_filter_by_ext(ptr %names, i64 %count, ptr %ext, ptr %out_names, ptr %out_count) {
entry:
  %arr_bytes = mul i64 %count, 8
  %arr2 = call ptr @malloc(i64 %arr_bytes)
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %next ]
  %idx = phi i64 [ 0, %entry ], [ %idx_next, %next ]
  %done = icmp uge i64 %i, %count
  br i1 %done, label %finish, label %check

check:
  %slot = getelementptr ptr, ptr %names, i64 %i
  %name = load ptr, ptr %slot
  %matches = call i32 @fsio_has_suffix(ptr %name, ptr %ext)
  %matches_b = icmp eq i32 %matches, 1
  br i1 %matches_b, label %keep, label %next

keep:
  %out_slot = getelementptr ptr, ptr %arr2, i64 %idx
  store ptr %name, ptr %out_slot
  %idx_inc = add i64 %idx, 1
  br label %next

next:
  %idx_next = phi i64 [ %idx, %check ], [ %idx_inc, %keep ]
  %i_next = add i64 %i, 1
  br label %loop

finish:
  store ptr %arr2, ptr %out_names
  store i64 %idx, ptr %out_count
  ret void
}

; borra un archivo. Devuelve 1 si terminó borrado (éxito real, o ya no
; existía — idempotente), 0 si falló por otra razón (permisos, etc.).
define i32 @fsio_delete_file(ptr %path) {
entry:
  %rc = call i32 @unlink(ptr %path)
  %ok = icmp eq i32 %rc, 0
  br i1 %ok, label %success, label %check_enoent

check_enoent:
  %errno_ptr = call ptr @__errno_location()
  %errno_val = load i32, ptr %errno_ptr
  %is_enoent = icmp eq i32 %errno_val, 2     ; ENOENT
  br i1 %is_enoent, label %success, label %fail

success:
  ret i32 1
fail:
  ret i32 0
}
