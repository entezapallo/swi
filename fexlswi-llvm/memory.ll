; fexl/memory.ll — allocator contado del intérprete Fexl.
; Reemplaza fexlswi-llvm/src/memory.c. Expone las mismas globals y funciones C
; (cur_blocks, cur_bytes, new_memory, resize_memory, free_memory, end_memory)
; para que los módulos C que quedan sigan linkando sin cambios.

@cur_blocks = global i64 0
@cur_bytes = global i64 0

@stderr = external global ptr

@.OOM   = private constant [31 x i8] c"The program ran out of memory.\00"
@.NEW0  = private constant [5 x i8] c"NEW0\00"
@.NFREE = private constant [6 x i8] c"NFREE\00"
@.XFREE = private constant [6 x i8] c"XFREE\00"
@.LEAK  = private constant [5 x i8] c"LEAK\00"
@.sp    = private constant [2 x i8] c" \00"
@.empty = private constant [1 x i8] c"\00"

declare ptr  @malloc(i64)
declare ptr  @realloc(ptr, i64)
declare void @free(ptr)
declare void @die(ptr)
declare void @fput(ptr, ptr)
declare void @fput_ulong(ptr, i64)

define private void @out_of_memory() {
entry:
  call void @die(ptr @.OOM)
  unreachable
}

; Devuelve un bloque nuevo o muere. Cuenta bloques y bytes.
define ptr @new_memory(i64 %num_bytes) {
entry:
  %is0 = icmp eq i64 %num_bytes, 0
  br i1 %is0, label %zero, label %alloc
zero:
  call void @die(ptr @.NEW0)
  unreachable
alloc:
  %data = call ptr @malloc(i64 %num_bytes)
  %null = icmp eq ptr %data, null
  br i1 %null, label %oom, label %ok
oom:
  call void @out_of_memory()
  unreachable
ok:
  %b = load i64, ptr @cur_blocks
  %b1 = add i64 %b, 1
  store i64 %b1, ptr @cur_blocks
  %y = load i64, ptr @cur_bytes
  %y1 = add i64 %y, %num_bytes
  store i64 %y1, ptr @cur_bytes
  ret ptr %data
}

; Cambia el tamaño de un bloque. data == null cuenta un bloque nuevo.
define ptr @resize_memory(ptr %data, i64 %o_size, i64 %n_size) {
entry:
  %isnull = icmp eq ptr %data, null
  br i1 %isnull, label %bump, label %realloc
bump:
  %b = load i64, ptr @cur_blocks
  %b1 = add i64 %b, 1
  store i64 %b1, ptr @cur_blocks
  br label %realloc
realloc:
  %d = call ptr @realloc(ptr %data, i64 %n_size)
  %null = icmp eq ptr %d, null
  br i1 %null, label %oom, label %ok
oom:
  call void @out_of_memory()
  unreachable
ok:
  %y = load i64, ptr @cur_bytes
  %y1 = sub i64 %y, %o_size
  %y2 = add i64 %y1, %n_size
  store i64 %y2, ptr @cur_bytes
  ret ptr %d
}

; Libera un bloque y descuenta los contadores.
define void @free_memory(ptr %data, i64 %num_bytes) {
entry:
  %isnull = icmp eq ptr %data, null
  br i1 %isnull, label %die0, label %check
die0:
  call void @die(ptr @.NFREE)
  unreachable
check:
  %b = load i64, ptr @cur_blocks
  %b0 = icmp eq i64 %b, 0
  %y = load i64, ptr @cur_bytes
  %ylt = icmp ult i64 %y, %num_bytes
  %bad = or i1 %b0, %ylt
  br i1 %bad, label %die1, label %ok
die1:
  call void @die(ptr @.XFREE)
  unreachable
ok:
  call void @free(ptr %data)
  %b1 = sub i64 %b, 1
  store i64 %b1, ptr @cur_blocks
  %y1 = sub i64 %y, %num_bytes
  store i64 %y1, ptr @cur_bytes
  ret void
}

; Detecta fugas al final. Equivale a end_memory() de memory.c.
define void @end_memory() {
entry:
  %b = load i64, ptr @cur_blocks
  %y = load i64, ptr @cur_bytes
  %bne = icmp ne i64 %b, 0
  %yne = icmp ne i64 %y, 0
  %bad = or i1 %bne, %yne
  br i1 %bad, label %leak, label %done
leak:
  %fp = load ptr, ptr @stderr
  call void @fput(ptr %fp, ptr @.LEAK)
  call void @fput(ptr %fp, ptr @.sp)
  call void @fput_ulong(ptr %fp, i64 %b)
  call void @fput(ptr %fp, ptr @.sp)
  call void @fput_ulong(ptr %fp, i64 %y)
  call void @die(ptr @.empty)
  unreachable
done:
  ret void
}
