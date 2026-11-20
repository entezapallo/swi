; fexl/base64.ll — codificacion base64 (antes src/base64.c).

@.unpack_ch = private constant [65 x i8] c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\00"

define private i8 @pack_ch(i8 %ch) {
entry:
  %geA = icmp uge i8 %ch, 65
  %leZ = icmp ule i8 %ch, 90
  %upper = and i1 %geA, %leZ
  br i1 %upper, label %u, label %low
u:
  %r = sub i8 %ch, 65
  ret i8 %r
low:
  %gea = icmp uge i8 %ch, 97
  %lez = icmp ule i8 %ch, 122
  %lower = and i1 %gea, %lez
  br i1 %lower, label %l, label %digit
l:
  %r2 = sub i8 %ch, 97
  %r3 = add i8 %r2, 26
  ret i8 %r3
digit:
  %ge0 = icmp uge i8 %ch, 48
  %le9 = icmp ule i8 %ch, 57
  %dig = and i1 %ge0, %le9
  br i1 %dig, label %d, label %special
d:
  %r4 = sub i8 %ch, 48
  %r5 = add i8 %r4, 52
  ret i8 %r5
special:
  %plus = icmp eq i8 %ch, 43
  br i1 %plus, label %p62, label %slash
p62:
  ret i8 62
slash:
  %sl = icmp eq i8 %ch, 47
  br i1 %sl, label %p63, label %zero
p63:
  ret i8 63
zero:
  ret i8 0
}

define private i8 @dig(i8 %n) {
entry:
  %ni = zext i8 %n to i64
  %p = getelementptr [65 x i8], ptr @.unpack_ch, i64 0, i64 %ni
  %r = load i8, ptr %p
  ret i8 %r
}

define void @unpack64(ptr %out, ptr %in, i64 %n) {
entry:
  %ng = udiv i64 %n, 3
  %rem = urem i64 %n, 3
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %cont = icmp ult i64 %i, %ng
  br i1 %cont, label %body, label %tail
body:
  %i3 = mul i64 %i, 3
  %c0p = getelementptr i8, ptr %in, i64 %i3
  %c0 = load i8, ptr %c0p
  %c1p = getelementptr i8, ptr %c0p, i64 1
  %c1 = load i8, ptr %c1p
  %c2p = getelementptr i8, ptr %c0p, i64 2
  %c2 = load i8, ptr %c2p
  %s0 = lshr i8 %c0, 2
  %d0 = call i8 @dig(i8 %s0)
  %m0 = and i8 %c0, 3
  %sh0 = shl i8 %m0, 4
  %s1 = lshr i8 %c1, 4
  %o1 = or i8 %sh0, %s1
  %d1 = call i8 @dig(i8 %o1)
  %m1 = and i8 %c1, 15
  %sh1 = shl i8 %m1, 2
  %s2 = lshr i8 %c2, 6
  %o2 = or i8 %sh1, %s2
  %d2 = call i8 @dig(i8 %o2)
  %m2 = and i8 %c2, 63
  %d3 = call i8 @dig(i8 %m2)
  %i4 = mul i64 %i, 4
  %o0 = getelementptr i8, ptr %out, i64 %i4
  %o1p = getelementptr i8, ptr %o0, i64 1
  %o2p = getelementptr i8, ptr %o0, i64 2
  %o3p = getelementptr i8, ptr %o0, i64 3
  store i8 %d0, ptr %o0
  store i8 %d1, ptr %o1p
  store i8 %d2, ptr %o2p
  store i8 %d3, ptr %o3p
  %i1 = add i64 %i, 1
  br label %loop
tail:
  %i3t = mul i64 %i, 3
  %i4t = mul i64 %i, 4
  %zero = icmp eq i64 %rem, 0
  br i1 %zero, label %justnul, label %haverem
justnul:
  %zn = getelementptr i8, ptr %out, i64 %i4t
  store i8 0, ptr %zn
  ret void
haverem:
  %t0p = getelementptr i8, ptr %in, i64 %i3t
  %t0 = load i8, ptr %t0p
  %ts = lshr i8 %t0, 2
  %td0 = call i8 @dig(i8 %ts)
  %to0 = getelementptr i8, ptr %out, i64 %i4t
  store i8 %td0, ptr %to0
  %r1 = icmp eq i64 %rem, 1
  br i1 %r1, label %one, label %two
one:
  %tm0 = and i8 %t0, 3
  %tsh = shl i8 %tm0, 4
  %td1 = call i8 @dig(i8 %tsh)
  %to1 = getelementptr i8, ptr %to0, i64 1
  store i8 %td1, ptr %to1
  br label %pad2
two:
  %t1p = getelementptr i8, ptr %t0p, i64 1
  %t1 = load i8, ptr %t1p
  %tm0b = and i8 %t0, 3
  %tshb = shl i8 %tm0b, 4
  %t1s = lshr i8 %t1, 4
  %orb = or i8 %tshb, %t1s
  %td1b = call i8 @dig(i8 %orb)
  %to1b = getelementptr i8, ptr %to0, i64 1
  store i8 %td1b, ptr %to1b
  %t1m = and i8 %t1, 15
  %t1sh = shl i8 %t1m, 2
  %td2 = call i8 @dig(i8 %t1sh)
  %to2 = getelementptr i8, ptr %to0, i64 2
  store i8 %td2, ptr %to2
  br label %pad1
pad2:
  %p2 = getelementptr i8, ptr %to0, i64 2
  store i8 61, ptr %p2
  br label %finish
pad1:
  br label %finish
finish:
  %p3 = getelementptr i8, ptr %to0, i64 3
  store i8 61, ptr %p3
  %pn = getelementptr i8, ptr %to0, i64 4
  store i8 0, ptr %pn
  ret void
}

define void @pack64(ptr %out, ptr %in, i64 %n) {
entry:
  %ng = udiv i64 %n, 4
  %rem = urem i64 %n, 4
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %cont = icmp ult i64 %i, %ng
  br i1 %cont, label %body, label %tail
body:
  %i4 = mul i64 %i, 4
  %c0p = getelementptr i8, ptr %in, i64 %i4
  %c0 = load i8, ptr %c0p
  %c1p = getelementptr i8, ptr %c0p, i64 1
  %c1 = load i8, ptr %c1p
  %c2p = getelementptr i8, ptr %c0p, i64 2
  %c2 = load i8, ptr %c2p
  %c3p = getelementptr i8, ptr %c0p, i64 3
  %c3 = load i8, ptr %c3p
  %v0 = call i8 @pack_ch(i8 %c0)
  %v1 = call i8 @pack_ch(i8 %c1)
  %v2 = call i8 @pack_ch(i8 %c2)
  %v3 = call i8 @pack_ch(i8 %c3)
  %s0 = shl i8 %v0, 2
  %v1s = lshr i8 %v1, 4
  %o0 = or i8 %s0, %v1s
  %m1 = and i8 %v1, 15
  %s1 = shl i8 %m1, 4
  %v2s = lshr i8 %v2, 2
  %o1 = or i8 %s1, %v2s
  %m2 = and i8 %v2, 3
  %s2 = shl i8 %m2, 6
  %m3 = and i8 %v3, 63
  %o2 = or i8 %s2, %m3
  %i3 = mul i64 %i, 3
  %op = getelementptr i8, ptr %out, i64 %i3
  %op1 = getelementptr i8, ptr %op, i64 1
  %op2 = getelementptr i8, ptr %op, i64 2
  store i8 %o0, ptr %op
  store i8 %o1, ptr %op1
  store i8 %o2, ptr %op2
  %i1 = add i64 %i, 1
  br label %loop
tail:
  %i4t = mul i64 %i, 4
  %i3t = mul i64 %i, 3
  %le1 = icmp ule i64 %rem, 1
  br i1 %le1, label %nul, label %hrem
nul:
  %zn = getelementptr i8, ptr %out, i64 %i3t
  store i8 0, ptr %zn
  ret void
hrem:
  %t0p = getelementptr i8, ptr %in, i64 %i4t
  %t0 = load i8, ptr %t0p
  %t1p = getelementptr i8, ptr %t0p, i64 1
  %t1 = load i8, ptr %t1p
  %hv0 = call i8 @pack_ch(i8 %t0)
  %hv1 = call i8 @pack_ch(i8 %t1)
  %hs0 = shl i8 %hv0, 2
  %hv1s = lshr i8 %hv1, 4
  %ho0 = or i8 %hs0, %hv1s
  %hop = getelementptr i8, ptr %out, i64 %i3t
  store i8 %ho0, ptr %hop
  %r2 = icmp eq i64 %rem, 2
  br i1 %r2, label %pad, label %more
pad:
  %hp1 = getelementptr i8, ptr %hop, i64 1
  store i8 0, ptr %hp1
  ret void
more:
  %t2p = getelementptr i8, ptr %t0p, i64 2
  %t2 = load i8, ptr %t2p
  %hv2 = call i8 @pack_ch(i8 %t2)
  %hm1 = and i8 %hv1, 15
  %hs1 = shl i8 %hm1, 4
  %hv2s = lshr i8 %hv2, 2
  %ho1 = or i8 %hs1, %hv2s
  %mp1 = getelementptr i8, ptr %hop, i64 1
  store i8 %ho1, ptr %mp1
  %mp2 = getelementptr i8, ptr %hop, i64 2
  store i8 0, ptr %mp2
  ret void
}
