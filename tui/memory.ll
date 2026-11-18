; memory.ll — modulo `memory` del motor de la TUI (spec seccion 2).
;
; Guarda, carga y maneja la sesion: ventanas abiertas con su ruta y cursor,
; macros, ultimo directorio. Pertenece a la TUI (usa al motor del editor via
; declare, nunca al reves).
;
;Estado EXPLICITO: un %Memory opaco se pasa a cada funcion, sin globals
; implicticos. No usa `switch` -> no necesita -relocation-model=pic.
;
; %MemEntry = { ptr path, i64 cursor, i64 top_line, i32 kind }  ; 32 bytes
;   kind: 'E'=editor window, 'M'=macro, 'D'=last_dir
; %Memory   = { ptr entries, i64 count, i64 cap, ptr last_dir, i64 last_dir_len }
;
; Formato de sesion en disco (lineas "K|cursor|top|path"):
;   E|0|0|/tmp/foo.txt
;   M|0|0|@digit::[0-9];
;   D|0|0|/home/user
; '|' dentro de un path/macro no se soporta (POC).

%MemEntry = type { ptr, i64, i64, i32 }
%Memory   = type { ptr, i64, i64, ptr, i64 }

declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i32 @memcmp(ptr, ptr, i64)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)
declare i32 @fsio_read_file(ptr, ptr, ptr)
declare i32 @fsio_write_file(ptr, ptr, i64)
declare void @fsio_free_buffer(ptr)

define ptr @memory_new() {
entry:
  %m = call ptr @malloc(i64 40)
  %n = icmp eq ptr %m, null
  br i1 %n, label %fail, label %init
fail:
  ret ptr null
init:
  %arr = call ptr @malloc(i64 256)    ; 8 entradas iniciales
  %an = icmp eq ptr %arr, null
  br i1 %an, label %fail_arr, label %setup
fail_arr:
  call void @free(ptr %m)
  ret ptr null
setup:
  %ap = getelementptr %Memory, ptr %m, i32 0, i32 0
  store ptr %arr, ptr %ap
  %cp = getelementptr %Memory, ptr %m, i32 0, i32 1
  store i64 0, ptr %cp
  %cap = getelementptr %Memory, ptr %m, i32 0, i32 2
  store i64 8, ptr %cap
  %ld = getelementptr %Memory, ptr %m, i32 0, i32 3
  store ptr null, ptr %ld
  %ldl = getelementptr %Memory, ptr %m, i32 0, i32 4
  store i64 0, ptr %ldl
  ret ptr %m
}

define void @memory_destroy(ptr %m) {
entry:
  ; liberar paths de las entradas
  %cp = getelementptr %Memory, ptr %m, i32 0, i32 1
  %count = load i64, ptr %cp
  %ap = getelementptr %Memory, ptr %m, i32 0, i32 0
  %arr = load ptr, ptr %ap
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %inext, %next ]
  %cont = icmp slt i64 %i, %count
  br i1 %cont, label %body, label %done
body:
  %ep = getelementptr %MemEntry, ptr %arr, i64 %i
  %pathp = getelementptr %MemEntry, ptr %ep, i32 0, i32 0
  %path = load ptr, ptr %pathp
  %notnull = icmp ne ptr %path, null
  br i1 %notnull, label %freepath, label %next
freepath:
  call void @free(ptr %path)
  br label %next
next:
  %inext = add i64 %i, 1
  br label %loop
done:
  call void @free(ptr %arr)
  %ld = getelementptr %Memory, ptr %m, i32 0, i32 3
  %ldv = load ptr, ptr %ld
  %ldnn = icmp ne ptr %ldv, null
  br i1 %ldnn, label %freeld, label %freem
freeld:
  call void @free(ptr %ldv)
  br label %freem
freem:
  call void @free(ptr %m)
  ret void
}

define void @memory_clear(ptr %m) {
entry:
  %cp = getelementptr %Memory, ptr %m, i32 0, i32 1
  %count = load i64, ptr %cp
  %ap = getelementptr %Memory, ptr %m, i32 0, i32 0
  %arr = load ptr, ptr %ap
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %inext, %next ]
  %cont = icmp slt i64 %i, %count
  br i1 %cont, label %body, label %done
body:
  %ep = getelementptr %MemEntry, ptr %arr, i64 %i
  %pathp = getelementptr %MemEntry, ptr %ep, i32 0, i32 0
  %path = load ptr, ptr %pathp
  %notnull = icmp ne ptr %path, null
  br i1 %notnull, label %freepath, label %next
freepath:
  call void @free(ptr %path)
  store ptr null, ptr %pathp
  br label %next
next:
  %inext = add i64 %i, 1
  br label %loop
done:
  store i64 0, ptr %cp
  ret void
}

; agrega una entrada. Devuelve 1 ok, 0 fail.
define i32 @memory_add(ptr %m, i32 %kind, ptr %path, i64 %len,
                        i64 %cursor, i64 %top) {
entry:
  %cp = getelementptr %Memory, ptr %m, i32 0, i32 1
  %count = load i64, ptr %cp
  %cap_p = getelementptr %Memory, ptr %m, i32 0, i32 2
  %cap = load i64, ptr %cap_p
  %need_grow = icmp sge i64 %count, %cap
  br i1 %need_grow, label %grow, label %have_room
grow:
  %newcap = mul i64 %cap, 2
  %newcap_bytes = mul i64 %newcap, 32
  %ap = getelementptr %Memory, ptr %m, i32 0, i32 0
  %arr = load ptr, ptr %ap
  %newarr = call ptr @realloc(ptr %arr, i64 %newcap_bytes)
  %nn = icmp eq ptr %newarr, null
  br i1 %nn, label %fail, label %grown
grown:
  store ptr %newarr, ptr %ap
  store i64 %newcap, ptr %cap_p
  br label %have_room
have_room:
  %alloclen = add i64 %len, 1
  %buf = call ptr @malloc(i64 %alloclen)
  %bn = icmp eq ptr %buf, null
  br i1 %bn, label %fail, label %copy
copy:
  %r = call ptr @memcpy(ptr %buf, ptr %path, i64 %len)
  %term = getelementptr i8, ptr %buf, i64 %len
  store i8 0, ptr %term
  %ap2 = getelementptr %Memory, ptr %m, i32 0, i32 0
  %arr2 = load ptr, ptr %ap2
  %ep = getelementptr %MemEntry, ptr %arr2, i64 %count
  %pp = getelementptr %MemEntry, ptr %ep, i32 0, i32 0
  store ptr %buf, ptr %pp
  %cup = getelementptr %MemEntry, ptr %ep, i32 0, i32 1
  store i64 %cursor, ptr %cup
  %topp = getelementptr %MemEntry, ptr %ep, i32 0, i32 2
  store i64 %top, ptr %topp
  %kp = getelementptr %MemEntry, ptr %ep, i32 0, i32 3
  store i32 %kind, ptr %kp
  %c1 = add i64 %count, 1
  store i64 %c1, ptr %cp
  ret i32 1
fail:
  ret i32 0
}

; busca una entrada por kind + path. Devuelve indice o -1.
define i64 @memory_find(ptr %m, i32 %kind, ptr %path, i64 %len) {
entry:
  %cp = getelementptr %Memory, ptr %m, i32 0, i32 1
  %count = load i64, ptr %cp
  %ap = getelementptr %Memory, ptr %m, i32 0, i32 0
  %arr = load ptr, ptr %ap
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %inext, %next ]
  %cont = icmp slt i64 %i, %count
  br i1 %cont, label %body, label %notfound
body:
  %ep = getelementptr %MemEntry, ptr %arr, i64 %i
  %kp = getelementptr %MemEntry, ptr %ep, i32 0, i32 3
  %k = load i32, ptr %kp
  %sam_kind = icmp eq i32 %k, %kind
  br i1 %sam_kind, label %cmp_path, label %next
cmp_path:
  %pp = getelementptr %MemEntry, ptr %ep, i32 0, i32 0
  %p = load ptr, ptr %pp
  %cmp = call i32 @memcmp(ptr %p, ptr %path, i64 %len)
  %same = icmp eq i32 %cmp, 0
  br i1 %same, label %found, label %next
found:
  ret i64 %i
next:
  %inext = add i64 %i, 1
  br label %loop
notfound:
  ret i64 -1
}

define i64 @memory_count(ptr %m, i32 %kind) {
entry:
  %cp = getelementptr %Memory, ptr %m, i32 0, i32 1
  %count = load i64, ptr %cp
  %ap = getelementptr %Memory, ptr %m, i32 0, i32 0
  %arr = load ptr, ptr %ap
  %n = alloca i64
  store i64 0, ptr %n
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %inext, %next ]
  %cont = icmp slt i64 %i, %count
  br i1 %cont, label %body, label %done
body:
  %ep = getelementptr %MemEntry, ptr %arr, i64 %i
  %kp = getelementptr %MemEntry, ptr %ep, i32 0, i32 3
  %k = load i32, ptr %kp
  %match = icmp eq i32 %k, %kind
  br i1 %match, label %inc, label %next
inc:
  %nv = load i64, ptr %n
  %nv1 = add i64 %nv, 1
  store i64 %nv1, ptr %n
  br label %next
next:
  %inext = add i64 %i, 1
  br label %loop
done:
  %r = load i64, ptr %n
  ret i64 %r
}

; obtiene una entrada por indice. Devuelve 1 ok, 0 fuera de rango.
define i32 @memory_get(ptr %m, i64 %idx, ptr %out_path, ptr %out_cursor,
                        ptr %out_top, ptr %out_kind) {
entry:
  %cp = getelementptr %Memory, ptr %m, i32 0, i32 1
  %count = load i64, ptr %cp
  %in = icmp slt i64 %idx, %count
  %ge = icmp sge i64 %idx, 0
  %ok = and i1 %in, %ge
  br i1 %ok, label %get, label %fail
get:
  %ap = getelementptr %Memory, ptr %m, i32 0, i32 0
  %arr = load ptr, ptr %ap
  %ep = getelementptr %MemEntry, ptr %arr, i64 %idx
  %pp = getelementptr %MemEntry, ptr %ep, i32 0, i32 0
  %p = load ptr, ptr %pp
  store ptr %p, ptr %out_path
  %cup = getelementptr %MemEntry, ptr %ep, i32 0, i32 1
  %cu = load i64, ptr %cup
  store i64 %cu, ptr %out_cursor
  %topp = getelementptr %MemEntry, ptr %ep, i32 0, i32 2
  %top = load i64, ptr %topp
  store i64 %top, ptr %out_top
  %kp = getelementptr %MemEntry, ptr %ep, i32 0, i32 3
  %k = load i32, ptr %kp
  store i32 %k, ptr %out_kind
  ret i32 1
fail:
  ret i32 0
}

define void @memory_set_last_dir(ptr %m, ptr %dir, i64 %len) {
entry:
  %ldp = getelementptr %Memory, ptr %m, i32 0, i32 3
  %old = load ptr, ptr %ldp
  %nn = icmp ne ptr %old, null
  br i1 %nn, label %freeold, label %alloc
freeold:
  call void @free(ptr %old)
  br label %alloc
alloc:
  %alloclen = add i64 %len, 1
  %buf = call ptr @malloc(i64 %alloclen)
  %r = call ptr @memcpy(ptr %buf, ptr %dir, i64 %len)
  %term = getelementptr i8, ptr %buf, i64 %len
  store i8 0, ptr %term
  store ptr %buf, ptr %ldp
  %ldl = getelementptr %Memory, ptr %m, i32 0, i32 4
  store i64 %len, ptr %ldl
  ret void
}

define ptr @memory_last_dir(ptr %m, ptr %out_len) {
entry:
  %ldp = getelementptr %Memory, ptr %m, i32 0, i32 3
  %p = load ptr, ptr %ldp
  %ldl = getelementptr %Memory, ptr %m, i32 0, i32 4
  %l = load i64, ptr %ldl
  store i64 %l, ptr %out_len
  ret ptr %p
}

; ---------------------------------------------------------------------------
; save/load: formato de lineas "K|cursor|top|path". path se copia hasta el
; final de la linea. '|' dentro del path no se soporta (POC).
; ---------------------------------------------------------------------------
define i32 @memory_save(ptr %m, ptr %path) {
entry:
  %cp = getelementptr %Memory, ptr %m, i32 0, i32 1
  %count = load i64, ptr %cp
  %ap = getelementptr %Memory, ptr %m, i32 0, i32 0
  %arr = load ptr, ptr %ap
  ; buffer generoso: 4096 por entrada
  %per = mul i64 %count, 4096
  %size = add i64 %per, 64
  %buf = call ptr @malloc(i64 %size)
  %bn = icmp eq ptr %buf, null
  br i1 %bn, label %fail, label %loop_init
loop_init:
  %off = alloca i64
  store i64 0, ptr %off
  br label %loop
loop:
  %i = phi i64 [ 0, %loop_init ], [ %inext, %path_done ]
  %cont = icmp slt i64 %i, %count
  br i1 %cont, label %body, label %finish
body:
  %ep = getelementptr %MemEntry, ptr %arr, i64 %i
  %kp = getelementptr %MemEntry, ptr %ep, i32 0, i32 3
  %k = load i32, ptr %kp
  %ch = trunc i32 %k to i8
  %o = load i64, ptr %off
  %d0 = getelementptr i8, ptr %buf, i64 %o
  store i8 %ch, ptr %d0
  %bar1 = getelementptr i8, ptr %buf, i64 %o
  %o1 = add i64 %o, 1
  %pb1 = getelementptr i8, ptr %buf, i64 %o1
  store i8 124, ptr %pb1
  ; cursor (decimal) -- simplificado: se guarda como 8 bytes binarios
  %o2 = add i64 %o1, 1
  %cup = getelementptr %MemEntry, ptr %ep, i32 0, i32 1
  %cu = load i64, ptr %cup
  %dstcu = getelementptr i8, ptr %buf, i64 %o2
  store i64 %cu, ptr %dstcu
  %o3 = add i64 %o2, 8
  %topp = getelementptr %MemEntry, ptr %ep, i32 0, i32 2
  %top = load i64, ptr %topp
  %dsttop = getelementptr i8, ptr %buf, i64 %o3
  store i64 %top, ptr %dsttop
  %o4 = add i64 %o3, 8
  %pp = getelementptr %MemEntry, ptr %ep, i32 0, i32 0
  %p = load ptr, ptr %pp
  %dstp = getelementptr i8, ptr %buf, i64 %o4
  %pr = call ptr @memcpy(ptr %dstp, ptr %p, i64 0)
  ; path: se escribe byte a byte hasta '\0'
  %pathloop = alloca i64
  store i64 0, ptr %pathloop
  br label %path_copy
path_copy:
  %j = load i64, ptr %pathloop
  %pc = getelementptr i8, ptr %p, i64 %j
  %b = load i8, ptr %pc
  %isend = icmp eq i8 %b, 0
  br i1 %isend, label %path_done, label %path_byte
path_byte:
  %dest = getelementptr i8, ptr %buf, i64 %o4
  %destj = getelementptr i8, ptr %dest, i64 %j
  store i8 %b, ptr %destj
  %j1 = add i64 %j, 1
  store i64 %j1, ptr %pathloop
  br label %path_copy
path_done:
  %jend = load i64, ptr %pathloop
  %onew = add i64 %o4, %jend
  %nlpos = getelementptr i8, ptr %buf, i64 %onew
  store i8 10, ptr %nlpos
  %onew2 = add i64 %onew, 1
  store i64 %onew2, ptr %off
  %inext = add i64 %i, 1
  br label %loop
finish:
  ; ultima entrada D (last_dir)
  %finaloff = load i64, ptr %off
  %d0b = getelementptr i8, ptr %buf, i64 %finaloff
  store i8 68, ptr %d0b
  %final1 = add i64 %finaloff, 1
  %b1b = getelementptr i8, ptr %buf, i64 %final1
  store i8 124, ptr %b1b
  %final2 = add i64 %final1, 1
  ; D tambien lleva 16 bytes de cursor/top (0) para cuadrar con el parser
  %zeros = getelementptr i8, ptr %buf, i64 %final2
  call void @llvm.memset.p0.i64(ptr %zeros, i8 0, i64 16, i1 false)
  %final2b = add i64 %final2, 16
  %ldp2 = getelementptr %Memory, ptr %m, i32 0, i32 3
  %ldv = load ptr, ptr %ldp2
  %ldl2 = getelementptr %Memory, ptr %m, i32 0, i32 4
  %ldlen = load i64, ptr %ldl2
  %hasld = icmp ne ptr %ldv, null
  br i1 %hasld, label %copyld, label %checkld_br
checkld_br:
  br label %write
copyld:
  %dstld = getelementptr i8, ptr %buf, i64 %final2b
  %lr = call ptr @memcpy(ptr %dstld, ptr %ldv, i64 %ldlen)
  %final3 = add i64 %final2b, %ldlen
  %nl2 = getelementptr i8, ptr %buf, i64 %final3
  store i8 10, ptr %nl2
  %final4 = add i64 %final3, 1
  br label %copyld2
copyld2:
  br label %write
write:
  %written = phi i64 [ %final2b, %checkld_br ], [ %final4, %copyld2 ]
  %ok = call i32 @fsio_write_file(ptr %path, ptr %buf, i64 %written)
  call void @free(ptr %buf)
  ret i32 %ok
fail:
  ret i32 0
}

; carga una sesion. Devuelve 1 si el archivo existe y se leyo, 0 si no.
define i32 @memory_load(ptr %m, ptr %path) {
entry:
  %ds = alloca ptr
  %dl = alloca i64
  %ok = call i32 @fsio_read_file(ptr %path, ptr %ds, ptr %dl)
  %okb = icmp eq i32 %ok, 1
  br i1 %okb, label %parse, label %fail
parse:
  %data = load ptr, ptr %ds
  %len = load i64, ptr %dl
  %pos = alloca i64
  store i64 0, ptr %pos
  br label %line_loop
line_loop:
  %p0 = load i64, ptr %pos
  %atend = icmp sge i64 %p0, %len
  br i1 %atend, label %done, label %parse_line
parse_line:
  %kptr = getelementptr i8, ptr %data, i64 %p0
  %kind = load i8, ptr %kptr
  %p1 = add i64 %p0, 1
  %bar = getelementptr i8, ptr %data, i64 %p1
  %p2 = add i64 %p0, 2
  %curp = getelementptr i8, ptr %data, i64 %p2
  %cursor = load i64, ptr %curp
  %p3 = add i64 %p2, 8
  %topp2 = getelementptr i8, ptr %data, i64 %p3
  %top = load i64, ptr %topp2
  %p4 = add i64 %p3, 8
  ; path hasta '\n'
  %scan = alloca i64
  store i64 %p4, ptr %scan
  br label %scan_loop
scan_loop:
  %sp = load i64, ptr %scan
  %done_scan = icmp sge i64 %sp, %len
  br i1 %done_scan, label %line_end, label %scan_byte
scan_byte:
  %bp = getelementptr i8, ptr %data, i64 %sp
  %b = load i8, ptr %bp
  %isnl = icmp eq i8 %b, 10
  br i1 %isnl, label %line_end, label %scan_next
scan_next:
  %sp1 = add i64 %sp, 1
  store i64 %sp1, ptr %scan
  br label %scan_loop
line_end:
  %pathstart = add i64 %p0, 18
  %pathend = load i64, ptr %scan
  %pathlen = sub i64 %pathend, %pathstart
  %pathsrc = getelementptr i8, ptr %data, i64 %pathstart
  %iskindE = icmp eq i8 %kind, 69
  %iskindM = icmp eq i8 %kind, 77
  %iskindD = icmp eq i8 %kind, 68
  br i1 %iskindE, label %addE, label %checkM
addE:
  %re = call i32 @memory_add(ptr %m, i32 69, ptr %pathsrc, i64 %pathlen, i64 %cursor, i64 %top)
  br label %advance
checkM:
  br i1 %iskindM, label %addM, label %checkD
addM:
  %rm = call i32 @memory_add(ptr %m, i32 77, ptr %pathsrc, i64 %pathlen, i64 %cursor, i64 %top)
  br label %advance
checkD:
  br i1 %iskindD, label %setD, label %advance
setD:
  call void @memory_set_last_dir(ptr %m, ptr %pathsrc, i64 %pathlen)
  br label %advance
advance:
  %nextpos = add i64 %pathend, 1
  store i64 %nextpos, ptr %pos
  br label %line_loop
done:
  call void @fsio_free_buffer(ptr %data)
  ret i32 1
fail:
  ret i32 0
}
