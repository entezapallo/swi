; fexl/report.ll — reporte de errores (antes src/report.c).

@stderr = external global ptr

@.on_line  = private constant [10 x i8] c" on line \00"
@.of       = private constant [5 x i8] c" of \00"
@.undef    = private constant [18 x i8] c"Undefined symbol \00"

declare void @fput(ptr, ptr)
declare void @fput_ulong(ptr, i64)
declare void @fnl(ptr)
declare void @die(ptr)

define private void @put_error_location(i64 %line, ptr %label) {
entry:
  %fp = load ptr, ptr @stderr
  call void @fput(ptr %fp, ptr @.on_line)
  call void @fput_ulong(ptr %fp, i64 %line)
  %first = load i8, ptr %label
  %nonempty = icmp ne i8 %first, 0
  br i1 %nonempty, label %of, label %nl
of:
  call void @fput(ptr %fp, ptr @.of)
  call void @fput(ptr %fp, ptr %label)
  br label %nl
nl:
  call void @fnl(ptr %fp)
  ret void
}

define void @fatal_error(ptr %code, i64 %line, ptr %label) {
entry:
  %fp = load ptr, ptr @stderr
  call void @fput(ptr %fp, ptr %code)
  call void @put_error_location(i64 %line, ptr %label)
  call void @die(ptr null)
  ret void
}

define void @undefined_symbol(ptr %name, i64 %line, ptr %label) {
entry:
  %fp = load ptr, ptr @stderr
  call void @fput(ptr %fp, ptr @.undef)
  call void @fput(ptr %fp, ptr %name)
  call void @put_error_location(i64 %line, ptr %label)
  ret void
}

define void @bad_name(ptr %msg, ptr %name) {
entry:
  %fp = load ptr, ptr @stderr
  call void @fput(ptr %fp, ptr %msg)
  call void @fput(ptr %fp, ptr %name)
  call void @fnl(ptr %fp)
  call void @die(ptr null)
  ret void
}
