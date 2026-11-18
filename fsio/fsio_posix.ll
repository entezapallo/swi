; fsio/fsio_posix.ll — mecanismo de sistema puro (syscalls), Linux x86-64.
; No sabe qué es un "documento" ni un "buffer" — mueve i8*/i64 crudo, nada más.
; Contrato: blobs serializados (ptr + i64), liberación a cargo de quien allocó
; (fsio_free_buffer libera lo que fsio_read_file allocó).

declare i32 @open(ptr, i32, i32)
declare i64 @read(i32, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @close(i32)
declare i64 @lseek(i32, i64, i32)
declare ptr @mmap(ptr, i64, i32, i32, i32, i64)
declare i32 @munmap(ptr, i64)
declare ptr @malloc(i64)
declare void @free(ptr)

; ---- constantes POSIX (Linux x86-64) ----
; O_RDONLY = 0
; O_WRONLY | O_CREAT | O_TRUNC = 1 | 64 | 512 = 577
; SEEK_SET = 0, SEEK_END = 2
; modo de creación 0644 = 420 (octal 0644 = decimal 420)
; PROT_READ = 0x1, MAP_PRIVATE = 0x02, MAP_FAILED = (ptr)-1

; devuelve i32 (1=ok, 0=fail). out_data recibe ptr malloc'd (dueño: quien llama,
; liberar con fsio_free_buffer), out_len recibe el tamaño en bytes.
define i32 @fsio_read_file(ptr %path, ptr %out_data, ptr %out_len) {
entry:
  %fd = call i32 @open(ptr %path, i32 0, i32 0)
  %open_ok = icmp sge i32 %fd, 0
  br i1 %open_ok, label %get_size, label %fail_noclose

get_size:
  %size = call i64 @lseek(i32 %fd, i64 0, i32 2)
  %size_ok = icmp sge i64 %size, 0
  br i1 %size_ok, label %rewind, label %fail_close

rewind:
  %rewind_rc = call i64 @lseek(i32 %fd, i64 0, i32 0)
  %rewind_ok = icmp sge i64 %rewind_rc, 0
  br i1 %rewind_ok, label %alloc, label %fail_close

alloc:
  ; archivo vacío: no hace falta malloc(0), devolvemos data=null, len=0, éxito.
  %is_empty = icmp eq i64 %size, 0
  br i1 %is_empty, label %empty_ok, label %doalloc

doalloc:
  %buf = call ptr @malloc(i64 %size)
  br label %readloop_init

readloop_init:
  ; loop simple: read() puede devolver menos de lo pedido (short read),
  ; se repite hasta completar %size o hasta error/EOF.
  br label %readloop

readloop:
  %total_read = phi i64 [ 0, %readloop_init ], [ %new_total, %readloop_next ]
  %done = icmp uge i64 %total_read, %size
  br i1 %done, label %read_success, label %do_read

do_read:
  %remaining = sub i64 %size, %total_read
  %cur_off = getelementptr i8, ptr %buf, i64 %total_read
  %n = call i64 @read(i32 %fd, ptr %cur_off, i64 %remaining)
  %n_ok = icmp sgt i64 %n, 0
  br i1 %n_ok, label %readloop_next, label %fail_free

readloop_next:
  %new_total = add i64 %total_read, %n
  br label %readloop

read_success:
  %close_rc1 = call i32 @close(i32 %fd)
  store ptr %buf, ptr %out_data
  store i64 %size, ptr %out_len
  ret i32 1

empty_ok:
  %close_rc2 = call i32 @close(i32 %fd)
  store ptr null, ptr %out_data
  store i64 0, ptr %out_len
  ret i32 1

fail_free:
  call void @free(ptr %buf)
  %close_rc3 = call i32 @close(i32 %fd)
  ret i32 0

fail_close:
  %close_rc4 = call i32 @close(i32 %fd)
  ret i32 0

fail_noclose:
  ret i32 0
}

; devuelve i32 (1=ok, 0=fail). No libera %data — eso es responsabilidad de quien
; lo allocó originalmente (regla del doc de arquitectura: mismo lado que allocó).
define i32 @fsio_write_file(ptr %path, ptr %data, i64 %len) {
entry:
  %fd = call i32 @open(ptr %path, i32 577, i32 420)
  %open_ok = icmp sge i32 %fd, 0
  br i1 %open_ok, label %writeloop_init, label %fail_noclose

writeloop_init:
  br label %writeloop

writeloop:
  %total_written = phi i64 [ 0, %writeloop_init ], [ %new_total, %writeloop_next ]
  %done = icmp uge i64 %total_written, %len
  br i1 %done, label %write_success, label %do_write

do_write:
  %remaining = sub i64 %len, %total_written
  %cur_off = getelementptr i8, ptr %data, i64 %total_written
  %n = call i64 @write(i32 %fd, ptr %cur_off, i64 %remaining)
  %n_ok = icmp sgt i64 %n, 0
  br i1 %n_ok, label %writeloop_next, label %fail_close

writeloop_next:
  %new_total = add i64 %total_written, %n
  br label %writeloop

write_success:
  %close_rc1 = call i32 @close(i32 %fd)
  ret i32 1

fail_close:
  %close_rc2 = call i32 @close(i32 %fd)
  ret i32 0

fail_noclose:
  ret i32 0
}

; libera un buffer devuelto por fsio_read_file. No-op seguro si %data es null
; (el caso de archivo vacío).
define void @fsio_free_buffer(ptr %data) {
entry:
  %isnull = icmp eq ptr %data, null
  br i1 %isnull, label %skip, label %dofree

dofree:
  call void @free(ptr %data)
  br label %skip

skip:
  ret void
}

; ---------------------------------------------------------------------------
; fsio_mmap: mapea %path en memoria de solo lectura, PRIVADA.
;
; Devuelve i32 (1=ok, 0=fail). %out_addr recibe el ptr al mapping y %out_len
; su tamaño en bytes. El mapping es MAP_PRIVATE: escribir en el no altera el
; archivo (el guardado del Document va a un archivo NUEVO, spec seccion 7).
;
; La propiedad es de quien llama: debe llamar fsio_munmap(addr, len) al
; terminar, igual que fsio_read_file -> fsio_free_buffer.
;
; El size se obtiene con lseek(SEEK_END), mismo criterio que fsio_read_file
; (evita fstat y su struct stat con layout complejo en IR). El fd se cierra
; despues del mmap: el mapping sobrevive al cierre (contraintuitivo pero POSIX).
; ---------------------------------------------------------------------------
define i32 @fsio_mmap(ptr %path, ptr %out_addr, ptr %out_len) {
entry:
  %fd = call i32 @open(ptr %path, i32 0, i32 0)
  %open_ok = icmp sge i32 %fd, 0
  br i1 %open_ok, label %get_size, label %fail_noclose

get_size:
  %size = call i64 @lseek(i32 %fd, i64 0, i32 2)
  %size_ok = icmp sge i64 %size, 0
  br i1 %size_ok, label %check_empty, label %fail_close

check_empty:
  ; mmap(len=0) da EINVAL: para archivo vacio devolvemos null/0, exito.
  %is_empty = icmp eq i64 %size, 0
  br i1 %is_empty, label %empty_ok, label %do_mmap

do_mmap:
  %addr = call ptr @mmap(ptr null, i64 %size, i32 1, i32 2, i32 %fd, i64 0)
  %map_failed = inttoptr i64 -1 to ptr
  %failed = icmp eq ptr %addr, %map_failed
  br i1 %failed, label %fail_close, label %success

empty_ok:
  %close1 = call i32 @close(i32 %fd)
  store ptr null, ptr %out_addr
  store i64 0, ptr %out_len
  ret i32 1

success:
  %close2 = call i32 @close(i32 %fd)
  store ptr %addr, ptr %out_addr
  store i64 %size, ptr %out_len
  ret i32 1

fail_close:
  %close3 = call i32 @close(i32 %fd)
  ret i32 0

fail_noclose:
  ret i32 0
}

; ---------------------------------------------------------------------------
; fsio_munmap: libera un mapping creado por fsio_mmap.
; Devuelve 1 si munmap devolvio 0, 0 si devolvio -1.
; NOTA: glibc devuelve EINVAL para munmap(null,0): el llamador no debe
; desmapear un mapping vacio (fsio_mmap de archivo vacio da addr=null).
; ---------------------------------------------------------------------------
define i32 @fsio_munmap(ptr %addr, i64 %len) {
entry:
  %rc = call i32 @munmap(ptr %addr, i64 %len)
  %ok = icmp eq i32 %rc, 0
  %res = zext i1 %ok to i32
  ret i32 %res
}

