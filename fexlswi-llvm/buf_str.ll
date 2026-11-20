; fexl/buf_str.ll — puente buffer <-> string (antes src/buf_str.c).

%Buffer = type { i64, i64, ptr }

declare void @buf_addn(ptr, ptr, i64)
declare void @buf_discard(ptr)
declare ptr  @str_new(i64)
declare ptr  @memcpy(ptr, ptr, i64)

define void @buf_put(ptr %buf, ptr %str) {
entry:
  %lp = getelementptr i8, ptr %str, i64 0
  %len = load i64, ptr %lp
  %dp = getelementptr i8, ptr %str, i64 8
  call void @buf_addn(ptr %buf, ptr %dp, i64 %len)
  ret void
}

define ptr @buf_clear(ptr %buf) {
entry:
  %blp = getelementptr %Buffer, ptr %buf, i32 0, i32 0
  %len = load i64, ptr %blp
  %result = call ptr @str_new(i64 %len)
  %bdp = getelementptr %Buffer, ptr %buf, i32 0, i32 2
  %data = load ptr, ptr %bdp
  %rdp = getelementptr i8, ptr %result, i64 8
  %r = call ptr @memcpy(ptr %rdp, ptr %data, i64 %len)
  call void @buf_discard(ptr %buf)
  ret ptr %result
}
