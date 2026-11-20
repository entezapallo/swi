; fexl/str.ll — strings del intérprete Fexl (antes src/str.c).
; No depende de %value: solo del allocator y de libc. Se inyecta
; value_types.ll por concatenación para mantener el esquema uniforme.
;
; struct string { unsigned long len; char data[]; }
; sizeof == 8; una cadena de len bytes ocupa len + 9 bytes (len+1 de datos
; más el header de 8).

%string = type { i64, [0 x i8] }

declare ptr  @new_memory(i64)
declare void @free_memory(ptr, i64)
declare i64  @strlen(ptr)
declare ptr  @memcpy(ptr, ptr, i64)
declare i32  @memcmp(ptr, ptr, i64)

; bytes totales para una cadena de len bytes
define private i64 @str_size(i64 %len) {
entry:
  %n = add i64 %len, 9
  ret i64 %n
}

define ptr @str_new(i64 %len) {
entry:
  %size = call i64 @str_size(i64 %len)
  %x = call ptr @new_memory(i64 %size)
  %lp = getelementptr %string, ptr %x, i32 0, i32 0
  store i64 %len, ptr %lp
  %dp = getelementptr %string, ptr %x, i32 0, i32 1
  %endp = getelementptr i8, ptr %dp, i64 %len
  store i8 0, ptr %endp
  ret ptr %x
}

define ptr @str_new_data(ptr %data, i64 %len) {
entry:
  %x = call ptr @str_new(i64 %len)
  %dp = getelementptr %string, ptr %x, i32 0, i32 1
  %r = call ptr @memcpy(ptr %dp, ptr %data, i64 %len)
  ret ptr %x
}

define ptr @str_new_data0(ptr %data) {
entry:
  %len = call i64 @strlen(ptr %data)
  %x = call ptr @str_new_data(ptr %data, i64 %len)
  ret ptr %x
}

define ptr @str_copy(ptr %x) {
entry:
  %lp = getelementptr %string, ptr %x, i32 0, i32 0
  %len = load i64, ptr %lp
  %dp = getelementptr %string, ptr %x, i32 0, i32 1
  %r = call ptr @str_new_data(ptr %dp, i64 %len)
  ret ptr %r
}

define void @str_free(ptr %x) {
entry:
  %lp = getelementptr %string, ptr %x, i32 0, i32 0
  %len = load i64, ptr %lp
  %size = call i64 @str_size(i64 %len)
  call void @free_memory(ptr %x, i64 %size)
  ret void
}

define ptr @str_concat(ptr %x, ptr %y) {
entry:
  %xlp = getelementptr %string, ptr %x, i32 0, i32 0
  %xl = load i64, ptr %xlp
  %ylp = getelementptr %string, ptr %y, i32 0, i32 0
  %yl = load i64, ptr %ylp
  %n = add i64 %xl, %yl
  %z = call ptr @str_new(i64 %n)
  %zdp = getelementptr %string, ptr %z, i32 0, i32 1
  %xdp = getelementptr %string, ptr %x, i32 0, i32 1
  %r1 = call ptr @memcpy(ptr %zdp, ptr %xdp, i64 %xl)
  %ydp = getelementptr %string, ptr %y, i32 0, i32 1
  %zd2 = getelementptr i8, ptr %zdp, i64 %xl
  %r2 = call ptr @memcpy(ptr %zd2, ptr %ydp, i64 %yl)
  ret ptr %z
}

define i32 @str_cmp(ptr %x, ptr %y) {
entry:
  %same = icmp eq ptr %x, %y
  br i1 %same, label %zero, label %body
zero:
  ret i32 0
body:
  %xlp = getelementptr %string, ptr %x, i32 0, i32 0
  %xl = load i64, ptr %xlp
  %ylp = getelementptr %string, ptr %y, i32 0, i32 0
  %yl = load i64, ptr %ylp
  %xlt = icmp ult i64 %xl, %yl
  %min = select i1 %xlt, i64 %xl, i64 %yl
  %xdp = getelementptr %string, ptr %x, i32 0, i32 1
  %ydp = getelementptr %string, ptr %y, i32 0, i32 1
  %cmp = call i32 @memcmp(ptr %xdp, ptr %ydp, i64 %min)
  %is0 = icmp eq i32 %cmp, 0
  %lendiff = icmp ne i64 %xl, %yl
  %both = and i1 %is0, %lendiff
  br i1 %both, label %bylen, label %retcmp
bylen:
  %xlt2 = icmp ult i64 %xl, %yl
  %r = select i1 %xlt2, i32 -1, i32 1
  ret i32 %r
retcmp:
  ret i32 %cmp
}

define i32 @str_eq(ptr %x, ptr %y) {
entry:
  %same = icmp eq ptr %x, %y
  br i1 %same, label %yes, label %body
yes:
  ret i32 1
body:
  %xlp = getelementptr %string, ptr %x, i32 0, i32 0
  %xl = load i64, ptr %xlp
  %ylp = getelementptr %string, ptr %y, i32 0, i32 0
  %yl = load i64, ptr %ylp
  %lensame = icmp eq i64 %xl, %yl
  br i1 %lensame, label %domem, label %no
domem:
  %xdp = getelementptr %string, ptr %x, i32 0, i32 1
  %ydp = getelementptr %string, ptr %y, i32 0, i32 1
  %cmp = call i32 @memcmp(ptr %xdp, ptr %ydp, i64 %xl)
  %is0 = icmp eq i32 %cmp, 0
  br i1 %is0, label %yes2, label %no
yes2:
  ret i32 1
no:
  ret i32 0
}

define ptr @str_slice(ptr %x, i64 %pos, i64 %len) {
entry:
  %xlp = getelementptr %string, ptr %x, i32 0, i32 0
  %xl = load i64, ptr %xlp
  %posgt = icmp ugt i64 %pos, %xl
  br i1 %posgt, label %clamp_pos, label %check_len
clamp_pos:
  br label %check_len
check_len:
  %p = phi i64 [ %xl, %clamp_pos ], [ %pos, %entry ]
  %avail = sub i64 %xl, %p
  %lengt = icmp ugt i64 %len, %avail
  %l = select i1 %lengt, i64 %avail, i64 %len
  %dp = getelementptr %string, ptr %x, i32 0, i32 1
  %start = getelementptr i8, ptr %dp, i64 %p
  %r = call ptr @str_new_data(ptr %start, i64 %l)
  ret ptr %r
}

; Primera aparición de y en x desde offset. xn significa "no encontrado".
define i64 @str_search(ptr %x, ptr %y, i64 %offset) {
entry:
  %xlp = getelementptr %string, ptr %x, i32 0, i32 0
  %xn = load i64, ptr %xlp
  %ylp = getelementptr %string, ptr %y, i32 0, i32 0
  %yn = load i64, ptr %ylp
  %tooshort = icmp ult i64 %xn, %yn
  %span = sub i64 %xn, %yn
  %offgt = icmp ugt i64 %offset, %span
  %nomatch = or i1 %tooshort, %offgt
  br i1 %nomatch, label %fail, label %loop
fail:
  ret i64 %xn
loop:
  %xi = phi i64 [ %offset, %entry ], [ %xi2, %again ]
  %yi = phi i64 [ 0, %entry ], [ %yi2, %again ]
  %yidone = icmp uge i64 %yi, %yn
  br i1 %yidone, label %found, label %checkxi
found:
  %at = sub i64 %xi, %yi
  ret i64 %at
checkxi:
  %xidone = icmp uge i64 %xi, %xn
  br i1 %xidone, label %fail2, label %cmpbyte
fail2:
  ret i64 %xn
cmpbyte:
  %xdp = getelementptr %string, ptr %x, i32 0, i32 1
  %ydp = getelementptr %string, ptr %y, i32 0, i32 1
  %xc = getelementptr i8, ptr %xdp, i64 %xi
  %yc = getelementptr i8, ptr %ydp, i64 %yi
  %xv = load i8, ptr %xc
  %yv = load i8, ptr %yc
  %eq = icmp eq i8 %xv, %yv
  br i1 %eq, label %match, label %mismatch
match:
  %yi_m = add i64 %yi, 1
  %xi_m = add i64 %xi, 1
  br label %again
mismatch:
  %xi_back = sub i64 %xi, %yi
  %xi_mm = add i64 %xi_back, 1
  br label %again
again:
  %xi2 = phi i64 [ %xi_m, %match ], [ %xi_mm, %mismatch ]
  %yi2 = phi i64 [ %yi_m, %match ], [ 0, %mismatch ]
  br label %loop
}

; dirname(3)
define ptr @dirname(ptr %path) {
entry:
  %dp = getelementptr %string, ptr %path, i32 0, i32 1
  %lp = getelementptr %string, ptr %path, i32 0, i32 0
  %n0 = load i64, ptr %lp
  br label %l1
l1:
  %a = phi i64 [ %n0, %entry ], [ %ad, %l1body ]
  %gt1 = icmp ugt i64 %a, 0
  %im1 = sub i64 %a, 1
  %p1 = getelementptr i8, ptr %dp, i64 %im1
  %c1 = load i8, ptr %p1
  %s1 = icmp eq i8 %c1, 47
  %go1 = and i1 %gt1, %s1
  br i1 %go1, label %l1body, label %l2
l1body:
  %ad = sub i64 %a, 1
  br label %l1
l2:
  %b = phi i64 [ %a, %l1 ], [ %bd, %l2body ]
  %gt2 = icmp ugt i64 %b, 0
  %im2 = sub i64 %b, 1
  %p2 = getelementptr i8, ptr %dp, i64 %im2
  %c2 = load i8, ptr %p2
  %s2 = icmp ne i8 %c2, 47
  %go2 = and i1 %gt2, %s2
  br i1 %go2, label %l2body, label %l3
l2body:
  %bd = sub i64 %b, 1
  br label %l2
l3:
  %c = phi i64 [ %b, %l2 ], [ %cd, %l3body ]
  %gt3 = icmp ugt i64 %c, 1
  %im3 = sub i64 %c, 1
  %p3 = getelementptr i8, ptr %dp, i64 %im3
  %c3 = load i8, ptr %p3
  %s3 = icmp eq i8 %c3, 47
  %go3 = and i1 %gt3, %s3
  br i1 %go3, label %l3body, label %finish
l3body:
  %cd = sub i64 %c, 1
  br label %l3
finish:
  %iszero = icmp eq i64 %c, 0
  br i1 %iszero, label %dot, label %substr
dot:
  %d = call ptr @str_new_data(ptr @.dot, i64 1)
  ret ptr %d
substr:
  %r = call ptr @str_new_data(ptr %dp, i64 %c)
  ret ptr %r
}

@.dot  = private constant [2 x i8] c".\00"
@.root = private constant [2 x i8] c"/\00"

; basename(3)
define ptr @basename(ptr %path) {
entry:
  %dp = getelementptr %string, ptr %path, i32 0, i32 1
  %lp = getelementptr %string, ptr %path, i32 0, i32 0
  %n0 = load i64, ptr %lp
  br label %loop
loop:
  %n = phi i64 [ %n0, %entry ], [ %nd, %body ]
  %gt1 = icmp ugt i64 %n, 1
  %im1 = sub i64 %n, 1
  %lastp = getelementptr i8, ptr %dp, i64 %im1
  %last = load i8, ptr %lastp
  %isslash = icmp eq i8 %last, 47
  %go = and i1 %gt1, %isslash
  br i1 %go, label %body, label %checkroot
body:
  %nd = sub i64 %n, 1
  br label %loop
checkroot:
  %nf = phi i64 [ %n, %loop ]
  %gt0 = icmp ugt i64 %nf, 0
  %im1f = sub i64 %nf, 1
  %lastfp = getelementptr i8, ptr %dp, i64 %im1f
  %lastf = load i8, ptr %lastfp
  %isrootslash = icmp eq i8 %lastf, 47
  %root = and i1 %gt0, %isrootslash
  br i1 %root, label %retroot, label %findpos
retroot:
  %r = call ptr @str_new_data(ptr @.root, i64 1)
  ret ptr %r
findpos:
  br label %posloop
posloop:
  %pos = phi i64 [ %nf, %findpos ], [ %posd, %posbody ]
  %posgt = icmp ugt i64 %pos, 0
  %im1p = sub i64 %pos, 1
  %prevp = getelementptr i8, ptr %dp, i64 %im1p
  %prev = load i8, ptr %prevp
  %notslash = icmp ne i8 %prev, 47
  %go2 = and i1 %posgt, %notslash
  br i1 %go2, label %posbody, label %done
posbody:
  %posd = sub i64 %pos, 1
  br label %posloop
done:
  %p = phi i64 [ %pos, %posloop ]
  %skip = sub i64 %nf, %p
  %start = getelementptr i8, ptr %dp, i64 %p
  %r2 = call ptr @str_new_data(ptr %start, i64 %skip)
  ret ptr %r2
}

define i64 @length_common(ptr %x, ptr %y) {
entry:
  %xlp = getelementptr %string, ptr %x, i32 0, i32 0
  %xl = load i64, ptr %xlp
  %ylp = getelementptr %string, ptr %y, i32 0, i32 0
  %yl = load i64, ptr %ylp
  %xlt = icmp ult i64 %xl, %yl
  %min = select i1 %xlt, i64 %xl, i64 %yl
  %xdp = getelementptr %string, ptr %x, i32 0, i32 1
  %ydp = getelementptr %string, ptr %y, i32 0, i32 1
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %cont = icmp ult i64 %i, %min
  br i1 %cont, label %check, label %done
check:
  %xp = getelementptr i8, ptr %xdp, i64 %i
  %yp = getelementptr i8, ptr %ydp, i64 %i
  %xv = load i8, ptr %xp
  %yv = load i8, ptr %yp
  %eq = icmp eq i8 %xv, %yv
  br i1 %eq, label %body, label %done
body:
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %i
}

; Ancho en bytes de un carácter UTF-8 según el byte líder.
define i8 @char_width(i8 %ch) {
entry:
  br label %loop
loop:
  %mask = phi i8 [ -128, %entry ], [ %mask1, %body ]
  %n = phi i8 [ 0, %entry ], [ %n1, %body ]
  %set = and i8 %ch, %mask
  %nonzero = icmp ne i8 %set, 0
  br i1 %nonzero, label %body, label %done
body:
  %n1 = add i8 %n, 1
  %mask1 = lshr i8 %mask, 1
  br label %loop
done:
  %is0 = icmp eq i8 %n, 0
  %r = select i1 %is0, i8 1, i8 %n
  ret i8 %r
}
