; fexl/file.ll — salida de bajo nivel (antes src/file.c).

@stdout = external global ptr

@.nl = private constant [2 x i8] c"\0a\00"

declare i64  @fwrite(ptr, i64, i64, ptr)
declare i64  @strlen(ptr)
declare ptr  @format_long(i64)
declare ptr  @format_ulong(i64)
declare ptr  @format_double(double)

define void @fputd(ptr %fh, ptr %data, i64 %len) {
entry:
  %n = call i64 @fwrite(ptr %data, i64 1, i64 %len, ptr %fh)
  ret void
}

define void @fput(ptr %fh, ptr %data) {
entry:
  %len = call i64 @strlen(ptr %data)
  call void @fputd(ptr %fh, ptr %data, i64 %len)
  ret void
}

define void @fput_ch(ptr %fh, i8 %ch) {
entry:
  %p = alloca i8, align 1
  store i8 %ch, ptr %p, align 1
  call void @fputd(ptr %fh, ptr %p, i64 1)
  ret void
}

define void @fput_long(ptr %fh, i64 %x) {
entry:
  %s = call ptr @format_long(i64 %x)
  call void @fput(ptr %fh, ptr %s)
  ret void
}

define void @fput_ulong(ptr %fh, i64 %x) {
entry:
  %s = call ptr @format_ulong(i64 %x)
  call void @fput(ptr %fh, ptr %s)
  ret void
}

define void @fput_double(ptr %fh, double %x) {
entry:
  %s = call ptr @format_double(double %x)
  call void @fput(ptr %fh, ptr %s)
  ret void
}

define void @fnl(ptr %fh) {
entry:
  call void @fput_ch(ptr %fh, i8 10)
  ret void
}

define void @put(ptr %data) {
entry:
  %out = load ptr, ptr @stdout
  call void @fput(ptr %out, ptr %data)
  ret void
}

define void @put_ch(i8 %ch) {
entry:
  %out = load ptr, ptr @stdout
  call void @fput_ch(ptr %out, i8 %ch)
  ret void
}

define void @put_long(i64 %x) {
entry:
  %out = load ptr, ptr @stdout
  call void @fput_long(ptr %out, i64 %x)
  ret void
}

define void @put_ulong(i64 %x) {
entry:
  %out = load ptr, ptr @stdout
  call void @fput_ulong(ptr %out, i64 %x)
  ret void
}

define void @put_double(double %x) {
entry:
  %out = load ptr, ptr @stdout
  call void @fput_double(ptr %out, double %x)
  ret void
}

define void @nl() {
entry:
  %out = load ptr, ptr @stdout
  call void @fnl(ptr %out)
  ret void
}
