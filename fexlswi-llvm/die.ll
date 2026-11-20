; fexl/die.ll — terminacion con mensaje (antes src/die.c).

@stderr = external global ptr

declare void @fput(ptr, ptr)
declare void @fnl(ptr)
declare void @exit(i32)

define void @die(ptr %msg) {
entry:
  %null = icmp eq ptr %msg, null
  br i1 %null, label %exitit, label %print
print:
  %fp = load ptr, ptr @stderr
  call void @fput(ptr %fp, ptr %msg)
  call void @fnl(ptr %fp)
  br label %exitit
exitit:
  call void @exit(i32 1)
  ret void
}
