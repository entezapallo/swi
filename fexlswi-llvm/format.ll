; fexl/format.ll — formateo numerico (antes src/format.c).

@buf = internal global [100 x i8] zeroinitializer

@.fmt_long   = private constant [4 x i8] c"%ld\00"
@.fmt_ulong  = private constant [4 x i8] c"%lu\00"
@.fmt_double = private constant [6 x i8] c"%.15g\00"

declare i32 @snprintf(ptr, i64, ptr, ...)

define ptr @format_long(i64 %x) {
entry:
  %r = call i32 (ptr, i64, ptr, ...) @snprintf(ptr @buf, i64 100, ptr @.fmt_long, i64 %x)
  ret ptr @buf
}

define ptr @format_ulong(i64 %x) {
entry:
  %r = call i32 (ptr, i64, ptr, ...) @snprintf(ptr @buf, i64 100, ptr @.fmt_ulong, i64 %x)
  ret ptr @buf
}

define ptr @format_uint64_t(i64 %x) {
entry:
  %r = call i32 (ptr, i64, ptr, ...) @snprintf(ptr @buf, i64 100, ptr @.fmt_ulong, i64 %x)
  ret ptr @buf
}

define ptr @format_double(double %x) {
entry:
  %r = call i32 (ptr, i64, ptr, ...) @snprintf(ptr @buf, i64 100, ptr @.fmt_double, double %x)
  ret ptr @buf
}
