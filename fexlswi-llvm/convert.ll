; fexl/convert.ll — conversion string -> double (antes src/convert.c).

declare i32    @isdigit(i32)
declare double @strtod(ptr, ptr)

; Valida el prefijo antes de strtod para no aceptar inf/nan como numeros.
define i32 @str0_double(ptr %str, ptr %val) {
entry:
  %isnull = icmp eq ptr %str, null
  br i1 %isnull, label %no, label %first
first:
  %c0 = load i8, ptr %str
  %c0i = sext i8 %c0 to i32
  %dig0 = call i32 @isdigit(i32 %c0i)
  %isdig = icmp ne i32 %dig0, 0
  %dash = icmp eq i8 %c0, 45
  %dot = icmp eq i8 %c0, 46
  %plus = icmp eq i8 %c0, 43
  %a = or i1 %isdig, %dash
  %b = or i1 %a, %dot
  %ok = or i1 %b, %plus
  br i1 %ok, label %checkminus, label %no
checkminus:
  br i1 %dash, label %second, label %yes
second:
  %p1 = getelementptr i8, ptr %str, i64 1
  %c1 = load i8, ptr %p1
  %c1i = sext i8 %c1 to i32
  %dig1 = call i32 @isdigit(i32 %c1i)
  %s1 = icmp ne i32 %dig1, 0
  %s2 = icmp eq i8 %c1, 46
  %ok2 = or i1 %s1, %s2
  br i1 %ok2, label %yes, label %no
yes:
  %end = alloca ptr, align 8
  %d = call double @strtod(ptr %str, ptr %end)
  store double %d, ptr %val, align 8
  %e = load ptr, ptr %end, align 8
  %ez = load i8, ptr %e
  %done = icmp eq i8 %ez, 0
  %r = zext i1 %done to i32
  ret i32 %r
no:
  ret i32 0
}
