; fexl/sha256.ll — SHA-256 (antes src/sha256.c).

@.k = private constant [64 x i32] [
  i32 1116352408, i32 1899447441, i32 -1245643825, i32 -373957723,
  i32 961987163, i32 1508970993, i32 -1841331548, i32 -1424204075,
  i32 -670586216, i32 310598401, i32 607225278, i32 1426881987,
  i32 1925078388, i32 -2132889090, i32 -1680079193, i32 -1046744716,
  i32 -459576895, i32 -272742522, i32 264347078, i32 604807628,
  i32 770255983, i32 1249150122, i32 1555081692, i32 1996064986,
  i32 -1740746414, i32 -1473132947, i32 -1341970488, i32 -1084653625,
  i32 -958395405, i32 -710438585, i32 113926993, i32 338241895,
  i32 666307205, i32 773529912, i32 1294757372, i32 1396182291,
  i32 1695183700, i32 1986661051, i32 -2117940946, i32 -1838011259,
  i32 -1564481375, i32 -1474664885, i32 -1035236496, i32 -949202525,
  i32 -778901479, i32 -694614492, i32 -200395387, i32 275423344,
  i32 430227734, i32 506948616, i32 659060556, i32 883997877,
  i32 958139571, i32 1322822218, i32 1537002063, i32 1747873779,
  i32 1955562222, i32 2024104815, i32 -2067236844, i32 -1933114872,
  i32 -1866530822, i32 -1538233109, i32 -1090935817, i32 -965641998
]

@.h0 = private constant [8 x i32] [
  i32 1779033703, i32 -1150833019, i32 1013904242, i32 -1521486534,
  i32 1359893119, i32 -1694144372, i32 528734635, i32 1541459225
]

define private i32 @rot(i32 %x, i32 %n) {
entry:
  %m = sub i32 32, %n
  %a = lshr i32 %x, %n
  %b = shl i32 %x, %m
  %r = or i32 %a, %b
  ret i32 %r
}
define private i32 @Ch(i32 %x, i32 %y, i32 %z) {
entry:
  %a = and i32 %x, %y
  %nx = xor i32 %x, -1
  %b = and i32 %nx, %z
  %r = xor i32 %a, %b
  ret i32 %r
}
define private i32 @Maj(i32 %x, i32 %y, i32 %z) {
entry:
  %a = and i32 %x, %y
  %b = and i32 %x, %z
  %c = and i32 %y, %z
  %d = xor i32 %a, %b
  %r = xor i32 %d, %c
  ret i32 %r
}
define private i32 @S0(i32 %x) {
entry:
  %a = call i32 @rot(i32 %x, i32 2)
  %b = call i32 @rot(i32 %x, i32 13)
  %c = call i32 @rot(i32 %x, i32 22)
  %d = xor i32 %a, %b
  %r = xor i32 %d, %c
  ret i32 %r
}
define private i32 @S1(i32 %x) {
entry:
  %a = call i32 @rot(i32 %x, i32 6)
  %b = call i32 @rot(i32 %x, i32 11)
  %c = call i32 @rot(i32 %x, i32 25)
  %d = xor i32 %a, %b
  %r = xor i32 %d, %c
  ret i32 %r
}
define private i32 @s0(i32 %x) {
entry:
  %a = call i32 @rot(i32 %x, i32 7)
  %b = call i32 @rot(i32 %x, i32 18)
  %c = lshr i32 %x, 3
  %d = xor i32 %a, %b
  %r = xor i32 %d, %c
  ret i32 %r
}
define private i32 @s1(i32 %x) {
entry:
  %a = call i32 @rot(i32 %x, i32 17)
  %b = call i32 @rot(i32 %x, i32 19)
  %c = lshr i32 %x, 10
  %d = xor i32 %a, %b
  %r = xor i32 %d, %c
  ret i32 %r
}

define private i64 @roll_bytes(ptr %x, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %u = phi i64 [ 0, %entry ], [ %u1, %body ]
  %cont = icmp ult i64 %i, %n
  br i1 %cont, label %body, label %done
body:
  %p = getelementptr i8, ptr %x, i64 %i
  %c = load i8, ptr %p
  %cu = zext i8 %c to i64
  %sh = shl i64 %u, 8
  %u1 = or i64 %sh, %cu
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %u
}

define private void @fill_bytes(ptr %x, i64 %u, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %v = phi i64 [ %u, %entry ], [ %v1, %body ]
  %cont = icmp ult i64 %i, %n
  br i1 %cont, label %body, label %done
body:
  %im = sub i64 %n, 1
  %pos = sub i64 %im, %i
  %p = getelementptr i8, ptr %x, i64 %pos
  %b = trunc i64 %v to i8
  store i8 %b, ptr %p
  %v1 = lshr i64 %v, 8
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

define private void @process_chunk(ptr %chunk, ptr %h, ptr %w) {
entry:
  br label %w1
w1:
  %i1 = phi i64 [ 0, %entry ], [ %i1n, %w1body ]
  %c1 = icmp ult i64 %i1, 16
  br i1 %c1, label %w1body, label %w2
w1body:
  %off = mul i64 %i1, 4
  %cp = getelementptr i8, ptr %chunk, i64 %off
  %v = call i64 @roll_bytes(ptr %cp, i64 4)
  %vw = trunc i64 %v to i32
  %wp = getelementptr i32, ptr %w, i64 %i1
  store i32 %vw, ptr %wp
  %i1n = add i64 %i1, 1
  br label %w1
w2:
  %i2 = phi i64 [ 16, %w1 ], [ %i2n, %w2body ]
  %c2 = icmp ult i64 %i2, 64
  br i1 %c2, label %w2body, label %ainit
w2body:
  %im15 = sub i64 %i2, 15
  %p15 = getelementptr i32, ptr %w, i64 %im15
  %v15 = load i32, ptr %p15
  %sv0 = call i32 @s0(i32 %v15)
  %im2 = sub i64 %i2, 2
  %p2 = getelementptr i32, ptr %w, i64 %im2
  %v2 = load i32, ptr %p2
  %sv1 = call i32 @s1(i32 %v2)
  %im16 = sub i64 %i2, 16
  %p16 = getelementptr i32, ptr %w, i64 %im16
  %v16 = load i32, ptr %p16
  %im7 = sub i64 %i2, 7
  %p7 = getelementptr i32, ptr %w, i64 %im7
  %v7 = load i32, ptr %p7
  %sum1 = add i32 %v16, %sv0
  %sum2 = add i32 %sum1, %v7
  %sum3 = add i32 %sum2, %sv1
  %dst = getelementptr i32, ptr %w, i64 %i2
  store i32 %sum3, ptr %dst
  %i2n = add i64 %i2, 1
  br label %w2
ainit:
  %a = alloca [8 x i32], align 4
  br label %acopy
acopy:
  %ia = phi i64 [ 0, %ainit ], [ %ian, %acopybody ]
  %ca = icmp ult i64 %ia, 8
  br i1 %ca, label %acopybody, label %compress
acopybody:
  %hp = getelementptr i32, ptr %h, i64 %ia
  %hv = load i32, ptr %hp
  %ap = getelementptr [8 x i32], ptr %a, i64 0, i64 %ia
  store i32 %hv, ptr %ap
  %ian = add i64 %ia, 1
  br label %acopy
compress:
  %ir = phi i64 [ 0, %acopy ], [ %irn, %finishround ]
  %cr = icmp ult i64 %ir, 64
  br i1 %cr, label %rbody, label %addh
rbody:
  %a4p = getelementptr [8 x i32], ptr %a, i64 0, i64 4
  %a4 = load i32, ptr %a4p
  %a5p = getelementptr [8 x i32], ptr %a, i64 0, i64 5
  %a5 = load i32, ptr %a5p
  %a6p = getelementptr [8 x i32], ptr %a, i64 0, i64 6
  %a6 = load i32, ptr %a6p
  %S1 = call i32 @S1(i32 %a4)
  %ch = call i32 @Ch(i32 %a4, i32 %a5, i32 %a6)
  %a7p = getelementptr [8 x i32], ptr %a, i64 0, i64 7
  %a7 = load i32, ptr %a7p
  %kp = getelementptr [64 x i32], ptr @.k, i64 0, i64 %ir
  %kv = load i32, ptr %kp
  %wp2 = getelementptr i32, ptr %w, i64 %ir
  %wv = load i32, ptr %wp2
  %t1 = add i32 %a7, %S1
  %t2 = add i32 %t1, %ch
  %t3 = add i32 %t2, %kv
  %T = add i32 %t3, %wv
  %a0p = getelementptr [8 x i32], ptr %a, i64 0, i64 0
  %a0 = load i32, ptr %a0p
  %S0 = call i32 @S0(i32 %a0)
  %a1p = getelementptr [8 x i32], ptr %a, i64 0, i64 1
  %a1 = load i32, ptr %a1p
  %a2p = getelementptr [8 x i32], ptr %a, i64 0, i64 2
  %a2 = load i32, ptr %a2p
  %maj = call i32 @Maj(i32 %a0, i32 %a1, i32 %a2)
  br label %shift
shift:
  %j = phi i64 [ 7, %rbody ], [ %jn, %shiftbody ]
  %contj = icmp ugt i64 %j, 0
  br i1 %contj, label %shiftbody, label %finishround
shiftbody:
  %jm = sub i64 %j, 1
  %src = getelementptr [8 x i32], ptr %a, i64 0, i64 %jm
  %sv = load i32, ptr %src
  %dst2 = getelementptr [8 x i32], ptr %a, i64 0, i64 %j
  store i32 %sv, ptr %dst2
  %jn = sub i64 %j, 1
  br label %shift
finishround:
  %a4v = load i32, ptr %a4p
  %a4new = add i32 %a4v, %T
  store i32 %a4new, ptr %a4p
  %n0 = add i32 %T, %S0
  %a0new = add i32 %n0, %maj
  store i32 %a0new, ptr %a0p
  %irn = add i64 %ir, 1
  br label %compress
addh:
  %ih = phi i64 [ 0, %compress ], [ %ihn, %addhbody ]
  %ch2 = icmp ult i64 %ih, 8
  br i1 %ch2, label %addhbody, label %done
addhbody:
  %hp2 = getelementptr i32, ptr %h, i64 %ih
  %hv2 = load i32, ptr %hp2
  %ap2 = getelementptr [8 x i32], ptr %a, i64 0, i64 %ih
  %av2 = load i32, ptr %ap2
  %s = add i32 %hv2, %av2
  store i32 %s, ptr %hp2
  %ihn = add i64 %ih, 1
  br label %addh
done:
  ret void
}

define void @sha256(ptr %digest, ptr %data, i64 %nbytes) {
entry:
  %bits = mul i64 %nbytes, 8
  %plus = add i64 %bits, 65
  %div = udiv i64 %plus, 512
  %nchunk = add i64 %div, 1
  %ntotal = mul i64 %nchunk, 64
  %ndchunk = udiv i64 %nbytes, 64
  %nremain = urem i64 %nbytes, 64
  %npad1 = sub i64 %ntotal, %nbytes
  %npad = sub i64 %npad1, 9
  %x = alloca [128 x i8], align 1
  %h = alloca [8 x i32], align 4
  %w = alloca [64 x i32], align 4
  br label %hinit
hinit:
  %ih = phi i64 [ 0, %entry ], [ %ihn, %hinitbody ]
  %ch = icmp ult i64 %ih, 8
  br i1 %ch, label %hinitbody, label %full
hinitbody:
  %kp = getelementptr [8 x i32], ptr @.h0, i64 0, i64 %ih
  %kv = load i32, ptr %kp
  %hp = getelementptr [8 x i32], ptr %h, i64 0, i64 %ih
  store i32 %kv, ptr %hp
  %ihn = add i64 %ih, 1
  br label %hinit
full:
  %if = phi i64 [ 0, %hinit ], [ %ifn, %fullbody ]
  %cf = icmp ult i64 %if, %ndchunk
  br i1 %cf, label %fullbody, label %remain
fullbody:
  %off = mul i64 %if, 64
  %dp = getelementptr i8, ptr %data, i64 %off
  call void @process_chunk(ptr %dp, ptr %h, ptr %w)
  %ifn = add i64 %if, 1
  br label %full
remain:
  %ir = phi i64 [ 0, %full ], [ %irn, %remainbody ]
  %cr = icmp ult i64 %ir, %nremain
  br i1 %cr, label %remainbody, label %pad80
remainbody:
  %base = mul i64 %ndchunk, 64
  %offr = add i64 %base, %ir
  %sp = getelementptr i8, ptr %data, i64 %offr
  %v = load i8, ptr %sp
  %xp = getelementptr [128 x i8], ptr %x, i64 0, i64 %ir
  store i8 %v, ptr %xp
  %irn = add i64 %ir, 1
  br label %remain
pad80:
  %p80 = getelementptr [128 x i8], ptr %x, i64 0, i64 %nremain
  store i8 -128, ptr %p80
  %zstart = add i64 %nremain, 1
  %zend = add i64 %zstart, %npad
  br label %zeroloop
zeroloop:
  %iz = phi i64 [ %zstart, %pad80 ], [ %izn, %zerobody ]
  %cz = icmp ult i64 %iz, %zend
  br i1 %cz, label %zerobody, label %appendbits
zerobody:
  %zp = getelementptr [128 x i8], ptr %x, i64 0, i64 %iz
  store i8 0, ptr %zp
  %izn = add i64 %iz, 1
  br label %zeroloop
appendbits:
  %bp = getelementptr [128 x i8], ptr %x, i64 0, i64 %zend
  call void @fill_bytes(ptr %bp, i64 %bits, i64 8)
  %extra = sub i64 %nchunk, %ndchunk
  br label %lastchunks
lastchunks:
  %il = phi i64 [ 0, %appendbits ], [ %iln, %lastbody ]
  %cl = icmp ult i64 %il, %extra
  br i1 %cl, label %lastbody, label %flatten
lastbody:
  %offl = mul i64 %il, 64
  %cp = getelementptr [128 x i8], ptr %x, i64 0, i64 %offl
  call void @process_chunk(ptr %cp, ptr %h, ptr %w)
  %iln = add i64 %il, 1
  br label %lastchunks
flatten:
  %if2 = phi i64 [ 0, %lastchunks ], [ %if2n, %flattenbody ]
  %c2 = icmp ult i64 %if2, 8
  br i1 %c2, label %flattenbody, label %done
flattenbody:
  %hp2 = getelementptr [8 x i32], ptr %h, i64 0, i64 %if2
  %hv2 = load i32, ptr %hp2
  %off2 = mul i64 %if2, 4
  %dp2 = getelementptr i8, ptr %digest, i64 %off2
  %dv = zext i32 %hv2 to i64
  call void @fill_bytes(ptr %dp2, i64 %dv, i64 4)
  %if2n = add i64 %if2, 1
  br label %flatten
done:
  ret void
}
