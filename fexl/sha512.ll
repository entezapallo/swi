; fexl/sha512.ll — SHA-512 (antes src/sha512.c).

@.k = private constant [80 x i64] [
  i64 4794697086780616226, i64 8158064640168781261, i64 -5349999486874862801, i64 -1606136188198331460,
  i64 4131703408338449720, i64 6480981068601479193, i64 -7908458776815382629, i64 -6116909921290321640,
  i64 -2880145864133508542, i64 1334009975649890238, i64 2608012711638119052, i64 6128411473006802146,
  i64 8268148722764581231, i64 -9160688886553864527, i64 -7215885187991268811, i64 -4495734319001033068,
  i64 -1973867731355612462, i64 -1171420211273849373, i64 1135362057144423861, i64 2597628984639134821,
  i64 3308224258029322869, i64 5365058923640841347, i64 6679025012923562964, i64 8573033837759648693,
  i64 -7476448914759557205, i64 -6327057829258317296, i64 -5763719355590565569, i64 -4658551843659510044,
  i64 -4116276920077217854, i64 -3051310485924567259, i64 489312712824947311, i64 1452737877330783856,
  i64 2861767655752347644, i64 3322285676063803686, i64 5560940570517711597, i64 5996557281743188959,
  i64 7280758554555802590, i64 8532644243296465576, i64 -9096487096722542874, i64 -7894198246740708037,
  i64 -6719396339535248540, i64 -6333637450476146687, i64 -4446306890439682159, i64 -4076793802049405392,
  i64 -3345356375505022440, i64 -2983346525034927856, i64 -860691631967231958, i64 1182934255886127544,
  i64 1847814050463011016, i64 2177327727835720531, i64 2830643537854262169, i64 3796741975233480872,
  i64 4115178125766777443, i64 5681478168544905931, i64 6601373596472566643, i64 7507060721942968483,
  i64 8399075790359081724, i64 8693463985226723168, i64 -8878714635349349518, i64 -8302665154208450068,
  i64 -8016688836872298968, i64 -6606660893046293015, i64 -4685533653050689259, i64 -4147400797238176981,
  i64 -3880063495543823972, i64 -3348786107499101689, i64 -1523767162380948706, i64 -757361751448694408,
  i64 500013540394364858, i64 748580250866718886, i64 1242879168328830382, i64 1977374033974150939,
  i64 2944078676154940804, i64 3659926193048069267, i64 4368137639120453308, i64 4836135668995329356,
  i64 5532061633213252278, i64 6448918945643986474, i64 6902733635092675308, i64 7801388544844847127
]
@.h0 = private constant [8 x i64] [
  i64 7640891576956012808, i64 -4942790177534073029, i64 4354685564936845355, i64 -6534734903238641935,
  i64 5840696475078001361, i64 -7276294671716946913, i64 2270897969802886507, i64 6620516959819538809
]

define private i64 @rot(i64 %x, i64 %n) {
entry:
  %m = sub i64 64, %n
  %a = lshr i64 %x, %n
  %b = shl i64 %x, %m
  %r = or i64 %a, %b
  ret i64 %r
}
define private i64 @Ch(i64 %x, i64 %y, i64 %z) {
entry:
  %a = and i64 %x, %y
  %nx = xor i64 %x, -1
  %b = and i64 %nx, %z
  %r = xor i64 %a, %b
  ret i64 %r
}
define private i64 @Maj(i64 %x, i64 %y, i64 %z) {
entry:
  %a = and i64 %x, %y
  %b = and i64 %x, %z
  %c = and i64 %y, %z
  %d = xor i64 %a, %b
  %r = xor i64 %d, %c
  ret i64 %r
}
define private i64 @S0(i64 %x) {
entry:
  %a = call i64 @rot(i64 %x, i64 28)
  %b = call i64 @rot(i64 %x, i64 34)
  %c = call i64 @rot(i64 %x, i64 39)
  %d = xor i64 %a, %b
  %r = xor i64 %d, %c
  ret i64 %r
}
define private i64 @S1(i64 %x) {
entry:
  %a = call i64 @rot(i64 %x, i64 14)
  %b = call i64 @rot(i64 %x, i64 18)
  %c = call i64 @rot(i64 %x, i64 41)
  %d = xor i64 %a, %b
  %r = xor i64 %d, %c
  ret i64 %r
}
define private i64 @s0(i64 %x) {
entry:
  %a = call i64 @rot(i64 %x, i64 1)
  %b = call i64 @rot(i64 %x, i64 8)
  %c = lshr i64 %x, 7
  %d = xor i64 %a, %b
  %r = xor i64 %d, %c
  ret i64 %r
}
define private i64 @s1(i64 %x) {
entry:
  %a = call i64 @rot(i64 %x, i64 19)
  %b = call i64 @rot(i64 %x, i64 61)
  %c = lshr i64 %x, 6
  %d = xor i64 %a, %b
  %r = xor i64 %d, %c
  ret i64 %r
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
  %off = mul i64 %i1, 8
  %cp = getelementptr i8, ptr %chunk, i64 %off
  %v = call i64 @roll_bytes(ptr %cp, i64 8)
  %wp = getelementptr i64, ptr %w, i64 %i1
  store i64 %v, ptr %wp
  %i1n = add i64 %i1, 1
  br label %w1
w2:
  %i2 = phi i64 [ 16, %w1 ], [ %i2n, %w2body ]
  %c2 = icmp ult i64 %i2, 80
  br i1 %c2, label %w2body, label %ainit
w2body:
  %im15 = sub i64 %i2, 15
  %p15 = getelementptr i64, ptr %w, i64 %im15
  %v15 = load i64, ptr %p15
  %sv0 = call i64 @s0(i64 %v15)
  %im2 = sub i64 %i2, 2
  %p2 = getelementptr i64, ptr %w, i64 %im2
  %v2 = load i64, ptr %p2
  %sv1 = call i64 @s1(i64 %v2)
  %im16 = sub i64 %i2, 16
  %p16 = getelementptr i64, ptr %w, i64 %im16
  %v16 = load i64, ptr %p16
  %im7 = sub i64 %i2, 7
  %p7 = getelementptr i64, ptr %w, i64 %im7
  %v7 = load i64, ptr %p7
  %s1a = add i64 %v16, %sv0
  %s2a = add i64 %s1a, %v7
  %s3a = add i64 %s2a, %sv1
  %dst = getelementptr i64, ptr %w, i64 %i2
  store i64 %s3a, ptr %dst
  %i2n = add i64 %i2, 1
  br label %w2
ainit:
  %a = alloca [8 x i64], align 8
  br label %acopy
acopy:
  %ia = phi i64 [ 0, %ainit ], [ %ian, %acopybody ]
  %ca = icmp ult i64 %ia, 8
  br i1 %ca, label %acopybody, label %compress
acopybody:
  %hp = getelementptr i64, ptr %h, i64 %ia
  %hv = load i64, ptr %hp
  %ap = getelementptr [8 x i64], ptr %a, i64 0, i64 %ia
  store i64 %hv, ptr %ap
  %ian = add i64 %ia, 1
  br label %acopy
compress:
  %ir = phi i64 [ 0, %acopy ], [ %irn, %finishround ]
  %cr = icmp ult i64 %ir, 80
  br i1 %cr, label %rbody, label %addh
rbody:
  %a4p = getelementptr [8 x i64], ptr %a, i64 0, i64 4
  %a4 = load i64, ptr %a4p
  %a5p = getelementptr [8 x i64], ptr %a, i64 0, i64 5
  %a5 = load i64, ptr %a5p
  %a6p = getelementptr [8 x i64], ptr %a, i64 0, i64 6
  %a6 = load i64, ptr %a6p
  %S1 = call i64 @S1(i64 %a4)
  %ch = call i64 @Ch(i64 %a4, i64 %a5, i64 %a6)
  %a7p = getelementptr [8 x i64], ptr %a, i64 0, i64 7
  %a7 = load i64, ptr %a7p
  %kp = getelementptr [80 x i64], ptr @.k, i64 0, i64 %ir
  %kv = load i64, ptr %kp
  %wp2 = getelementptr i64, ptr %w, i64 %ir
  %wv = load i64, ptr %wp2
  %t1 = add i64 %a7, %S1
  %t2 = add i64 %t1, %ch
  %t3 = add i64 %t2, %kv
  %T = add i64 %t3, %wv
  %a0p = getelementptr [8 x i64], ptr %a, i64 0, i64 0
  %a0 = load i64, ptr %a0p
  %S0 = call i64 @S0(i64 %a0)
  %a1p = getelementptr [8 x i64], ptr %a, i64 0, i64 1
  %a1 = load i64, ptr %a1p
  %a2p = getelementptr [8 x i64], ptr %a, i64 0, i64 2
  %a2 = load i64, ptr %a2p
  %maj = call i64 @Maj(i64 %a0, i64 %a1, i64 %a2)
  br label %shift
shift:
  %j = phi i64 [ 7, %rbody ], [ %jn, %shiftbody ]
  %contj = icmp ugt i64 %j, 0
  br i1 %contj, label %shiftbody, label %finishround
shiftbody:
  %jm = sub i64 %j, 1
  %src = getelementptr [8 x i64], ptr %a, i64 0, i64 %jm
  %sv = load i64, ptr %src
  %dst2 = getelementptr [8 x i64], ptr %a, i64 0, i64 %j
  store i64 %sv, ptr %dst2
  %jn = sub i64 %j, 1
  br label %shift
finishround:
  %a4v = load i64, ptr %a4p
  %a4new = add i64 %a4v, %T
  store i64 %a4new, ptr %a4p
  %n0 = add i64 %T, %S0
  %a0new = add i64 %n0, %maj
  store i64 %a0new, ptr %a0p
  %irn = add i64 %ir, 1
  br label %compress
addh:
  %ih = phi i64 [ 0, %compress ], [ %ihn, %addhbody ]
  %ch2 = icmp ult i64 %ih, 8
  br i1 %ch2, label %addhbody, label %done
addhbody:
  %hp2 = getelementptr i64, ptr %h, i64 %ih
  %hv2 = load i64, ptr %hp2
  %ap2 = getelementptr [8 x i64], ptr %a, i64 0, i64 %ih
  %av2 = load i64, ptr %ap2
  %s = add i64 %hv2, %av2
  store i64 %s, ptr %hp2
  %ihn = add i64 %ih, 1
  br label %addh
done:
  ret void
}

define void @sha512(ptr %digest, ptr %data, i64 %nbytes) {
entry:
  %bits = mul i64 %nbytes, 8
  %plus = add i64 %bits, 129
  %div = udiv i64 %plus, 1024
  %nchunk = add i64 %div, 1
  %ntotal = mul i64 %nchunk, 128
  %ndchunk = udiv i64 %nbytes, 128
  %nremain = urem i64 %nbytes, 128
  %npad1 = sub i64 %ntotal, %nbytes
  %npad = sub i64 %npad1, 17
  %x = alloca [256 x i8], align 1
  %h = alloca [8 x i64], align 8
  %w = alloca [80 x i64], align 8
  br label %hinit
hinit:
  %ih = phi i64 [ 0, %entry ], [ %ihn, %hinitbody ]
  %ch = icmp ult i64 %ih, 8
  br i1 %ch, label %hinitbody, label %full
hinitbody:
  %kp = getelementptr [8 x i64], ptr @.h0, i64 0, i64 %ih
  %kv = load i64, ptr %kp
  %hp = getelementptr [8 x i64], ptr %h, i64 0, i64 %ih
  store i64 %kv, ptr %hp
  %ihn = add i64 %ih, 1
  br label %hinit
full:
  %if = phi i64 [ 0, %hinit ], [ %ifn, %fullbody ]
  %cf = icmp ult i64 %if, %ndchunk
  br i1 %cf, label %fullbody, label %remain
fullbody:
  %off = mul i64 %if, 128
  %dp = getelementptr i8, ptr %data, i64 %off
  call void @process_chunk(ptr %dp, ptr %h, ptr %w)
  %ifn = add i64 %if, 1
  br label %full
remain:
  %ir = phi i64 [ 0, %full ], [ %irn, %remainbody ]
  %cr = icmp ult i64 %ir, %nremain
  br i1 %cr, label %remainbody, label %pad80
remainbody:
  %base = mul i64 %ndchunk, 128
  %offr = add i64 %base, %ir
  %sp = getelementptr i8, ptr %data, i64 %offr
  %v = load i8, ptr %sp
  %xp = getelementptr [256 x i8], ptr %x, i64 0, i64 %ir
  store i8 %v, ptr %xp
  %irn = add i64 %ir, 1
  br label %remain
pad80:
  %p80 = getelementptr [256 x i8], ptr %x, i64 0, i64 %nremain
  store i8 -128, ptr %p80
  %zstart = add i64 %nremain, 1
  %zend = add i64 %zstart, %npad
  br label %zeroloop
zeroloop:
  %iz = phi i64 [ %zstart, %pad80 ], [ %izn, %zerobody ]
  %cz = icmp ult i64 %iz, %zend
  br i1 %cz, label %zerobody, label %appendbits
zerobody:
  %zp = getelementptr [256 x i8], ptr %x, i64 0, i64 %iz
  store i8 0, ptr %zp
  %izn = add i64 %iz, 1
  br label %zeroloop
appendbits:
  %bp = getelementptr [256 x i8], ptr %x, i64 0, i64 %zend
  call void @fill_bytes(ptr %bp, i64 %bits, i64 16)
  %extra = sub i64 %nchunk, %ndchunk
  br label %lastchunks
lastchunks:
  %il = phi i64 [ 0, %appendbits ], [ %iln, %lastbody ]
  %cl = icmp ult i64 %il, %extra
  br i1 %cl, label %lastbody, label %flatten
lastbody:
  %offl = mul i64 %il, 128
  %cp = getelementptr [256 x i8], ptr %x, i64 0, i64 %offl
  call void @process_chunk(ptr %cp, ptr %h, ptr %w)
  %iln = add i64 %il, 1
  br label %lastchunks
flatten:
  %if2 = phi i64 [ 0, %lastchunks ], [ %if2n, %flattenbody ]
  %c2 = icmp ult i64 %if2, 8
  br i1 %c2, label %flattenbody, label %done
flattenbody:
  %hp2 = getelementptr [8 x i64], ptr %h, i64 0, i64 %if2
  %hv2 = load i64, ptr %hp2
  %off2 = mul i64 %if2, 8
  %dp2 = getelementptr i8, ptr %digest, i64 %off2
  call void @fill_bytes(ptr %dp2, i64 %hv2, i64 8)
  %if2n = add i64 %if2, 1
  br label %flatten
done:
  ret void
}
