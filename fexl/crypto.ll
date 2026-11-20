; fexl/crypto.ll — aleatoriedad, NaCl, HMAC y hashes (antes src/crypto.c).

@fh_random = internal global ptr null

@.urandom = private constant [13 x i8] c"/dev/urandom\00"
@.r       = private constant [2 x i8] c"r\00"
@.err_random = private constant [34 x i8] c"could not open random byte source\00"
@.err_bytes = private constant [20 x i8] c"out of random bytes\00"

declare ptr  @fopen(ptr, ptr)
declare i64  @fread(ptr, i64, i64, ptr)
declare i32  @fclose(ptr)
declare void @die(ptr)
declare ptr  @str_new(i64)
declare ptr  @str_new_data(ptr, i64)
declare ptr  @new_memory(i64)
declare void @free_memory(ptr, i64)
declare ptr  @memcpy(ptr, ptr, i64)
declare ptr  @memset(ptr, i32, i64)

declare void @nacl_box_public(ptr, ptr)
declare void @nacl_box_prepare(ptr, ptr, ptr)
declare i32  @nacl_box_seal(ptr, ptr, i64, ptr, ptr)
declare i32  @nacl_box_open(ptr, ptr, i64, ptr, ptr)
declare void @nacl_sign_public(ptr, ptr)
declare void @nacl_sign_seal(ptr, ptr, i64, ptr, ptr)
declare i32  @nacl_sign_open(ptr, ptr, i64, ptr)
declare void @sha256(ptr, ptr, i64)
declare void @sha512(ptr, ptr, i64)
declare void @pack64(ptr, ptr, i64)
declare void @unpack64(ptr, ptr, i64)

define void @close_random() {
entry:
  %fh = load ptr, ptr @fh_random
  %nonnull = icmp ne ptr %fh, null
  br i1 %nonnull, label %close, label %done
close:
  %r = call i32 @fclose(ptr %fh)
  store ptr null, ptr @fh_random
  br label %done
done:
  ret void
}

define private void @read_random_bytes(ptr %result, i64 %num) {
entry:
  %fh = load ptr, ptr @fh_random
  %nonnull = icmp ne ptr %fh, null
  br i1 %nonnull, label %read, label %open
open:
  %f = call ptr @fopen(ptr @.urandom, ptr @.r)
  %ok = icmp ne ptr %f, null
  br i1 %ok, label %set, label %dieopen
dieopen:
  call void @die(ptr @.err_random)
  unreachable
set:
  store ptr %f, ptr @fh_random
  br label %read
read:
  %fh2 = load ptr, ptr @fh_random
  %n = call i64 @fread(ptr %result, i64 1, i64 %num, ptr %fh2)
  %enough = icmp uge i64 %n, %num
  br i1 %enough, label %done, label %diebytes
diebytes:
  call void @die(ptr @.err_bytes)
  unreachable
done:
  ret void
}

define ptr @str_random_bytes(i64 %num) {
entry:
  %s = call ptr @str_new(i64 %num)
  %dp = getelementptr i8, ptr %s, i64 8
  call void @read_random_bytes(ptr %dp, i64 %num)
  ret ptr %s
}

define ptr @str_random_nonce() {
entry:
  %r = call ptr @str_random_bytes(i64 24)
  ret ptr %r
}
define ptr @str_random_secret_key() {
entry:
  %r = call ptr @str_random_bytes(i64 32)
  ret ptr %r
}

define private ptr @op_public(ptr %op, ptr %sk) {
entry:
  %lp = getelementptr i8, ptr %sk, i64 0
  %len = load i64, ptr %lp
  %ok = icmp eq i64 %len, 32
  br i1 %ok, label %yes, label %no
yes:
  %pk = call ptr @str_new(i64 32)
  %pdp = getelementptr i8, ptr %pk, i64 8
  %sdp = getelementptr i8, ptr %sk, i64 8
  call void %op(ptr %pdp, ptr %sdp)
  ret ptr %pk
no:
  ret ptr null
}

define ptr @str_nacl_box_public(ptr %sk) {
entry:
  %r = call ptr @op_public(ptr @nacl_box_public, ptr %sk)
  ret ptr %r
}
define ptr @str_nacl_sign_public(ptr %sk) {
entry:
  %r = call ptr @op_public(ptr @nacl_sign_public, ptr %sk)
  ret ptr %r
}

define ptr @str_nacl_box_prepare(ptr %pk, ptr %sk) {
entry:
  %lp = getelementptr i8, ptr %pk, i64 0
  %lpk = load i64, ptr %lp
  %ls = getelementptr i8, ptr %sk, i64 0
  %lsk = load i64, ptr %ls
  %ok1 = icmp eq i64 %lpk, 32
  %ok2 = icmp eq i64 %lsk, 32
  %ok = and i1 %ok1, %ok2
  br i1 %ok, label %yes, label %no
yes:
  %res = call ptr @str_new(i64 32)
  %rdp = getelementptr i8, ptr %res, i64 8
  %pkp = getelementptr i8, ptr %pk, i64 8
  %skp = getelementptr i8, ptr %sk, i64 8
  call void @nacl_box_prepare(ptr %rdp, ptr %pkp, ptr %skp)
  ret ptr %res
no:
  ret ptr null
}

define private ptr @op_box_pad(ptr %op, i64 %pad_text, i64 %pad_result, ptr %text, ptr %nonce, ptr %key) {
entry:
  %lnp = getelementptr i8, ptr %nonce, i64 0
  %ln = load i64, ptr %lnp
  %lkk = getelementptr i8, ptr %key, i64 0
  %lk = load i64, ptr %lkk
  %okn = icmp eq i64 %ln, 24
  %okk = icmp eq i64 %lk, 32
  %ok = and i1 %okn, %okk
  br i1 %ok, label %yes, label %no
yes:
  %ltp = getelementptr i8, ptr %text, i64 0
  %lt = load i64, ptr %ltp
  %buflen = add i64 %lt, %pad_text
  %bt = call ptr @new_memory(i64 %buflen)
  %br = call ptr @new_memory(i64 %buflen)
  %z = call ptr @memset(ptr %bt, i32 0, i64 %pad_text)
  %tdp = getelementptr i8, ptr %text, i64 8
  %dst = getelementptr i8, ptr %bt, i64 %pad_text
  %c = call ptr @memcpy(ptr %dst, ptr %tdp, i64 %lt)
  %ndp = getelementptr i8, ptr %nonce, i64 8
  %kdp = getelementptr i8, ptr %key, i64 8
  %code = call i32 %op(ptr %br, ptr %bt, i64 %buflen, ptr %ndp, ptr %kdp)
  %bad = icmp eq i32 %code, -1
  br i1 %bad, label %no2, label %mk
mk:
  %outlen = sub i64 %buflen, %pad_result
  %start = getelementptr i8, ptr %br, i64 %pad_result
  %res = call ptr @str_new_data(ptr %start, i64 %outlen)
  br label %done
no2:
  br label %no
done:
  call void @free_memory(ptr %bt, i64 %buflen)
  call void @free_memory(ptr %br, i64 %buflen)
  ret ptr %res
no:
  ret ptr null
}

define ptr @str_nacl_box_seal(ptr %t, ptr %n, ptr %k) {
entry:
  %r = call ptr @op_box_pad(ptr @nacl_box_seal, i64 32, i64 16, ptr %t, ptr %n, ptr %k)
  ret ptr %r
}
define ptr @str_nacl_box_open(ptr %t, ptr %n, ptr %k) {
entry:
  %r = call ptr @op_box_pad(ptr @nacl_box_open, i64 16, i64 32, ptr %t, ptr %n, ptr %k)
  ret ptr %r
}

define ptr @str_nacl_sign_seal(ptr %text, ptr %pk, ptr %sk) {
entry:
  %lp = getelementptr i8, ptr %pk, i64 0
  %lpk = load i64, ptr %lp
  %ls = getelementptr i8, ptr %sk, i64 0
  %lsk = load i64, ptr %ls
  %o1 = icmp eq i64 %lpk, 32
  %o2 = icmp eq i64 %lsk, 32
  %ok = and i1 %o1, %o2
  br i1 %ok, label %yes, label %no
yes:
  %ltp = getelementptr i8, ptr %text, i64 0
  %lt = load i64, ptr %ltp
  %n = add i64 %lt, 64
  %sm = call ptr @new_memory(i64 %n)
  %tdp = getelementptr i8, ptr %text, i64 8
  %pkp = getelementptr i8, ptr %pk, i64 8
  %skp = getelementptr i8, ptr %sk, i64 8
  call void @nacl_sign_seal(ptr %sm, ptr %tdp, i64 %lt, ptr %pkp, ptr %skp)
  %res = call ptr @str_new_data(ptr %sm, i64 64)
  call void @free_memory(ptr %sm, i64 %n)
  ret ptr %res
no:
  ret ptr null
}

define i32 @str_nacl_sign_open(ptr %text, ptr %pk, ptr %sig) {
entry:
  %lp = getelementptr i8, ptr %pk, i64 0
  %lpk = load i64, ptr %lp
  %ls = getelementptr i8, ptr %sig, i64 0
  %lsig = load i64, ptr %ls
  %o1 = icmp eq i64 %lpk, 32
  %o2 = icmp eq i64 %lsig, 64
  %ok = and i1 %o1, %o2
  br i1 %ok, label %yes, label %no
yes:
  %ltp = getelementptr i8, ptr %text, i64 0
  %lt = load i64, ptr %ltp
  %n = add i64 %lt, 64
  %sm = call ptr @new_memory(i64 %n)
  %m = call ptr @new_memory(i64 %n)
  %sdp = getelementptr i8, ptr %sig, i64 8
  %c1 = call ptr @memcpy(ptr %sm, ptr %sdp, i64 64)
  %tdp = getelementptr i8, ptr %text, i64 8
  %sm64 = getelementptr i8, ptr %sm, i64 64
  %c2 = call ptr @memcpy(ptr %sm64, ptr %tdp, i64 %lt)
  %pkp = getelementptr i8, ptr %pk, i64 8
  %code = call i32 @nacl_sign_open(ptr %m, ptr %sm, i64 %n, ptr %pkp)
  call void @free_memory(ptr %sm, i64 %n)
  call void @free_memory(ptr %m, i64 %n)
  %isok = icmp eq i32 %code, 0
  %r = zext i1 %isok to i32
  ret i32 %r
no:
  ret i32 0
}

define ptr @str_sha256(ptr %text) {
entry:
  %h = call ptr @str_new(i64 32)
  %dp = getelementptr i8, ptr %h, i64 8
  %ltp = getelementptr i8, ptr %text, i64 0
  %lt = load i64, ptr %ltp
  %tdp = getelementptr i8, ptr %text, i64 8
  call void @sha256(ptr %dp, ptr %tdp, i64 %lt)
  ret ptr %h
}
define ptr @str_sha512(ptr %text) {
entry:
  %h = call ptr @str_new(i64 64)
  %dp = getelementptr i8, ptr %h, i64 8
  %ltp = getelementptr i8, ptr %text, i64 0
  %lt = load i64, ptr %ltp
  %tdp = getelementptr i8, ptr %text, i64 8
  call void @sha512(ptr %dp, ptr %tdp, i64 %lt)
  ret ptr %h
}

define ptr @str_pack64(ptr %text) {
entry:
  %ltp = getelementptr i8, ptr %text, i64 0
  %n0 = load i64, ptr %ltp
  %im1 = sub i64 %n0, 1
  %lastp = getelementptr i8, ptr %text, i64 %im1
  %last = load i8, ptr %lastp
  %eq = icmp eq i8 %last, 61
  br i1 %eq, label %dec1, label %chk2
dec1:
  %n1 = sub i64 %n0, 1
  br label %chk2
chk2:
  %n2 = phi i64 [ %n0, %entry ], [ %n1, %dec1 ]
  %im2 = sub i64 %n2, 1
  %lastp2 = getelementptr i8, ptr %text, i64 %im2
  %last2 = load i8, ptr %lastp2
  %eq2 = icmp eq i8 %last2, 61
  br i1 %eq2, label %dec2, label %calc
dec2:
  %n3 = sub i64 %n2, 1
  br label %calc
calc:
  %n = phi i64 [ %n2, %chk2 ], [ %n3, %dec2 ]
  %ng = udiv i64 %n, 4
  %rem = urem i64 %n, 4
  %b = mul i64 3, %ng
  %isz = icmp eq i64 %rem, 0
  br i1 %isz, label %mk, label %nz
nz:
  %rm1 = sub i64 %rem, 1
  %extra = add i64 %b, %rm1
  br label %mk
mk:
  %nout = phi i64 [ %b, %calc ], [ %extra, %nz ]
  %out = call ptr @str_new(i64 %nout)
  %odp = getelementptr i8, ptr %out, i64 8
  %tdp = getelementptr i8, ptr %text, i64 8
  call void @pack64(ptr %odp, ptr %tdp, i64 %n)
  ret ptr %out
}

define ptr @str_unpack64(ptr %text) {
entry:
  %ltp = getelementptr i8, ptr %text, i64 0
  %n = load i64, ptr %ltp
  %ng = udiv i64 %n, 3
  %rem = urem i64 %n, 3
  %b = mul i64 4, %ng
  %isz = icmp eq i64 %rem, 0
  br i1 %isz, label %mk, label %nz
nz:
  %extra = add i64 %b, 4
  br label %mk
mk:
  %nout = phi i64 [ %b, %entry ], [ %extra, %nz ]
  %out = call ptr @str_new(i64 %nout)
  %odp = getelementptr i8, ptr %out, i64 8
  %tdp = getelementptr i8, ptr %text, i64 8
  call void @unpack64(ptr %odp, ptr %tdp, i64 %n)
  ret ptr %out
}

define private ptr @str_hmac(ptr %hash, i64 %blocksize, ptr %text, ptr %key) {
entry:
  %outsize = udiv i64 %blocksize, 2
  %mac = call ptr @str_new(i64 %outsize)
  %ltp = getelementptr i8, ptr %text, i64 0
  %lt = load i64, ptr %ltp
  %lenipad = add i64 %blocksize, %lt
  %ipad = call ptr @new_memory(i64 %lenipad)
  %opad_size = add i64 %blocksize, %outsize
  %opad = call ptr @new_memory(i64 %opad_size)
  %lkk = getelementptr i8, ptr %key, i64 0
  %kl0 = load i64, ptr %lkk
  %too = icmp ugt i64 %kl0, %blocksize
  br i1 %too, label %clamp, label %fill
clamp:
  br label %fill
fill:
  %kl = phi i64 [ %kl0, %entry ], [ %blocksize, %clamp ]
  %f = sub i64 %blocksize, %kl
  %kdp = getelementptr i8, ptr %key, i64 8
  br label %xorloop
xorloop:
  %i = phi i64 [ 0, %fill ], [ %i1, %xorbody ]
  %c = icmp ult i64 %i, %kl
  br i1 %c, label %xorbody, label %pads
xorbody:
  %kp = getelementptr i8, ptr %kdp, i64 %i
  %kv = load i8, ptr %kp
  %x36 = xor i8 %kv, 54
  %x5c = xor i8 %kv, 92
  %ip = getelementptr i8, ptr %ipad, i64 %i
  %op = getelementptr i8, ptr %opad, i64 %i
  store i8 %x36, ptr %ip
  store i8 %x5c, ptr %op
  %i1 = add i64 %i, 1
  br label %xorloop
pads:
  %ippad = getelementptr i8, ptr %ipad, i64 %kl
  %oppad = getelementptr i8, ptr %opad, i64 %kl
  %zi = call ptr @memset(ptr %ippad, i8 54, i64 %f)
  %z2 = call ptr @memset(ptr %oppad, i8 92, i64 %f)
  %tdp = getelementptr i8, ptr %text, i64 8
  %bsp = getelementptr i8, ptr %ipad, i64 %blocksize
  %c3 = call ptr @memcpy(ptr %bsp, ptr %tdp, i64 %lt)
  %dst = getelementptr i8, ptr %opad, i64 %blocksize
  call void %hash(ptr %dst, ptr %ipad, i64 %lenipad)
  %mdp = getelementptr i8, ptr %mac, i64 8
  call void %hash(ptr %mdp, ptr %opad, i64 %opad_size)
  call void @free_memory(ptr %ipad, i64 %lenipad)
  call void @free_memory(ptr %opad, i64 %opad_size)
  ret ptr %mac
}

define ptr @str_hmac_sha512(ptr %t, ptr %k) {
entry:
  %r = call ptr @str_hmac(ptr @sha512, i64 128, ptr %t, ptr %k)
  ret ptr %r
}
define ptr @str_hmac_sha256(ptr %t, ptr %k) {
entry:
  %r = call ptr @str_hmac(ptr @sha256, i64 64, ptr %t, ptr %k)
  ret ptr %r
}
