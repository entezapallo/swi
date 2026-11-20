; fexl/type_crypto.ll — builtins cripto (antes src/type_crypto.c).

@QI = external global ptr

@.s_random_bytes = private constant [13 x i8] c"random_bytes\00"
@.s_random_nonce = private constant [13 x i8] c"random_nonce\00"
@.s_random_secret_key = private constant [18 x i8] c"random_secret_key\00"
@.s_box_public  = private constant [16 x i8] c"nacl_box_public\00"
@.s_box_prepare = private constant [17 x i8] c"nacl_box_prepare\00"
@.s_box_seal    = private constant [14 x i8] c"nacl_box_seal\00"
@.s_box_open    = private constant [14 x i8] c"nacl_box_open\00"
@.s_sign_public = private constant [17 x i8] c"nacl_sign_public\00"
@.s_sign_seal   = private constant [15 x i8] c"nacl_sign_seal\00"
@.s_sign_open   = private constant [15 x i8] c"nacl_sign_open\00"
@.s_sha256      = private constant [7 x i8] c"sha256\00"
@.s_sha512      = private constant [7 x i8] c"sha512\00"
@.s_pack64      = private constant [7 x i8] c"pack64\00"
@.s_unpack64    = private constant [9 x i8] c"unpack64\00"
@.s_hmac_sha512 = private constant [12 x i8] c"hmac_sha512\00"
@.s_hmac_sha256 = private constant [12 x i8] c"hmac_sha256\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @Qstr(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @boolean(i32)
declare void @define(ptr, ptr)
declare i64  @get_ulong(ptr)
declare ptr  @op_str(ptr, ptr)
declare ptr  @op_str2(ptr, ptr)
declare ptr  @op_str3(ptr, ptr)
declare ptr  @type_num(ptr)
declare ptr  @type_str(ptr)

declare ptr  @str_random_bytes(i64)
declare ptr  @str_random_nonce()
declare ptr  @str_random_secret_key()
declare ptr  @str_nacl_box_public(ptr)
declare ptr  @str_nacl_box_prepare(ptr, ptr)
declare ptr  @str_nacl_box_seal(ptr, ptr, ptr)
declare ptr  @str_nacl_box_open(ptr, ptr, ptr)
declare ptr  @str_nacl_sign_public(ptr)
declare ptr  @str_nacl_sign_seal(ptr, ptr, ptr)
declare i32  @str_nacl_sign_open(ptr, ptr, ptr)
declare ptr  @str_sha256(ptr)
declare ptr  @str_sha512(ptr)
declare ptr  @str_pack64(ptr)
declare ptr  @str_unpack64(ptr)
declare ptr  @str_hmac_sha512(ptr, ptr)
declare ptr  @str_hmac_sha256(ptr, ptr)
declare void @close_random()

define private ptr @type_random_bytes(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_num
  br i1 %is, label %yes, label %void
yes:
  %n = call i64 @get_ulong(ptr %x)
  %s = call ptr @str_random_bytes(i64 %n)
  %res = call ptr @Qstr(ptr %s)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_random_nonce(ptr %f) {
entry:
  %s = call ptr @str_random_nonce()
  %r = call ptr @Qstr(ptr %s)
  ret ptr %r
}
define private ptr @type_random_secret_key(ptr %f) {
entry:
  %s = call ptr @str_random_secret_key()
  %r = call ptr @Qstr(ptr %s)
  ret ptr %r
}

define private ptr @type_nacl_box_public(ptr %f) { entry: %r = call ptr @op_str(ptr %f, ptr @str_nacl_box_public) ret ptr %r }
define private ptr @type_nacl_box_prepare(ptr %f) { entry: %r = call ptr @op_str2(ptr %f, ptr @str_nacl_box_prepare) ret ptr %r }
define private ptr @type_nacl_box_seal(ptr %f) { entry: %r = call ptr @op_str3(ptr %f, ptr @str_nacl_box_seal) ret ptr %r }
define private ptr @type_nacl_box_open(ptr %f) { entry: %r = call ptr @op_str3(ptr %f, ptr @str_nacl_box_open) ret ptr %r }
define private ptr @type_nacl_sign_public(ptr %f) { entry: %r = call ptr @op_str(ptr %f, ptr @str_nacl_sign_public) ret ptr %r }
define private ptr @type_nacl_sign_seal(ptr %f) { entry: %r = call ptr @op_str3(ptr %f, ptr @str_nacl_sign_seal) ret ptr %r }

define private ptr @type_nacl_sign_open(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %p1 = icmp eq ptr %LL, null
  br i1 %p1, label %keepf, label %lv2
lv2:
  %LLLp = getelementptr %value, ptr %LL, i32 0, i32 2
  %LLL = load ptr, ptr %LLLp
  %p2 = icmp eq ptr %LLL, null
  br i1 %p2, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LLRp = getelementptr %value, ptr %LL, i32 0, i32 3
  %xarg = load ptr, ptr %LLRp
  %x = call ptr @arg(ptr %xarg)
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %yarg = load ptr, ptr %LRp
  %y = call ptr @arg(ptr %yarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %zarg = load ptr, ptr %rp
  %z = call ptr @arg(ptr %zarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %ztp = getelementptr %value, ptr %z, i32 0, i32 1
  %zt = load ptr, ptr %ztp
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %zs = icmp eq ptr %zt, @type_str
  %a = and i1 %xs, %ys
  %all = and i1 %a, %zs
  br i1 %all, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %zvp = getelementptr %value, ptr %z, i32 0, i32 3
  %zv = load ptr, ptr %zvp
  %ok = call i32 @str_nacl_sign_open(ptr %xv, ptr %yv, ptr %zv)
  %res = call ptr @boolean(i32 %ok)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  call void @drop(ptr %z)
  ret ptr %r
}

define private ptr @type_sha256(ptr %f) { entry: %r = call ptr @op_str(ptr %f, ptr @str_sha256) ret ptr %r }
define private ptr @type_sha512(ptr %f) { entry: %r = call ptr @op_str(ptr %f, ptr @str_sha512) ret ptr %r }
define private ptr @type_pack64(ptr %f) { entry: %r = call ptr @op_str(ptr %f, ptr @str_pack64) ret ptr %r }
define private ptr @type_unpack64(ptr %f) { entry: %r = call ptr @op_str(ptr %f, ptr @str_unpack64) ret ptr %r }
define private ptr @type_hmac_sha512(ptr %f) { entry: %r = call ptr @op_str2(ptr %f, ptr @str_hmac_sha512) ret ptr %r }
define private ptr @type_hmac_sha256(ptr %f) { entry: %r = call ptr @op_str2(ptr %f, ptr @str_hmac_sha256) ret ptr %r }

define ptr @type_load_crypto(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_random_bytes)
  call void @define(ptr @.s_random_bytes, ptr %q0)
  %q1 = call ptr @Q0(ptr @type_random_nonce)
  call void @define(ptr @.s_random_nonce, ptr %q1)
  %q2 = call ptr @Q0(ptr @type_random_secret_key)
  call void @define(ptr @.s_random_secret_key, ptr %q2)
  %q3 = call ptr @Q(ptr @type_nacl_box_public)
  call void @define(ptr @.s_box_public, ptr %q3)
  %q4 = call ptr @Q(ptr @type_nacl_box_prepare)
  call void @define(ptr @.s_box_prepare, ptr %q4)
  %q5 = call ptr @Q(ptr @type_nacl_box_seal)
  call void @define(ptr @.s_box_seal, ptr %q5)
  %q6 = call ptr @Q(ptr @type_nacl_box_open)
  call void @define(ptr @.s_box_open, ptr %q6)
  %q7 = call ptr @Q(ptr @type_nacl_sign_public)
  call void @define(ptr @.s_sign_public, ptr %q7)
  %q8 = call ptr @Q(ptr @type_nacl_sign_seal)
  call void @define(ptr @.s_sign_seal, ptr %q8)
  %q9 = call ptr @Q(ptr @type_nacl_sign_open)
  call void @define(ptr @.s_sign_open, ptr %q9)
  %q10 = call ptr @Q(ptr @type_sha256)
  call void @define(ptr @.s_sha256, ptr %q10)
  %q11 = call ptr @Q(ptr @type_sha512)
  call void @define(ptr @.s_sha512, ptr %q11)
  %q12 = call ptr @Q(ptr @type_pack64)
  call void @define(ptr @.s_pack64, ptr %q12)
  %q13 = call ptr @Q(ptr @type_unpack64)
  call void @define(ptr @.s_unpack64, ptr %q13)
  %q14 = call ptr @Q(ptr @type_hmac_sha512)
  call void @define(ptr @.s_hmac_sha512, ptr %q14)
  %q15 = call ptr @Q(ptr @type_hmac_sha256)
  call void @define(ptr @.s_hmac_sha256, ptr %q15)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define void @beg_crypto() {
entry:
  ret void
}
define void @end_crypto() {
entry:
  call void @close_random()
  ret void
}

@Qvoid = external global ptr
