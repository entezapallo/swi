; fexl/file_str.ll — salida de strings (antes src/file_str.c).

@stdout = external global ptr

declare void @fputd(ptr, ptr, i64)

define void @fput_str(ptr %fh, ptr %x) {
entry:
  %lp = getelementptr i8, ptr %x, i64 0
  %len = load i64, ptr %lp
  %dp = getelementptr i8, ptr %x, i64 8
  call void @fputd(ptr %fh, ptr %dp, i64 %len)
  ret void
}

define void @put_str(ptr %x) {
entry:
  %out = load ptr, ptr @stdout
  call void @fput_str(ptr %out, ptr %x)
  ret void
}
