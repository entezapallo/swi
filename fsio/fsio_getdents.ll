; fsio_getdents.ll — musl no exporta getdents64 como simbolo de libc.
; fsio_list_dir.ll lo declara extern; aca lo resolvemos con syscall(2)
; directo (SYS_getdents64 = 217 en x86_64).

declare i64 @syscall(i64, ...)

define i64 @getdents64(i32 %fd, ptr %buf, i64 %n) {
entry:
  %fd64 = sext i32 %fd to i64
  %r = call i64 (i64, ...) @syscall(i64 217, i64 %fd64, ptr %buf, i64 %n)
  ret i64 %r
}
