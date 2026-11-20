; fexl/type_bn.ll — builtins de big numbers (antes src/type_bn.c).

@QI    = external global ptr
@Qvoid = external global ptr

@.s_eq0      = private constant [7 x i8]  c"bn_eq0\00"
@.s_is_neg   = private constant [10 x i8] c"bn_is_neg\00"
@.s_neg      = private constant [7 x i8]  c"bn_neg\00"
@.s_cmp      = private constant [7 x i8]  c"bn_cmp\00"
@.s_lt       = private constant [6 x i8]  c"bn_lt\00"
@.s_le       = private constant [6 x i8]  c"bn_le\00"
@.s_eq       = private constant [6 x i8]  c"bn_eq\00"
@.s_ne       = private constant [6 x i8]  c"bn_ne\00"
@.s_ge       = private constant [6 x i8]  c"bn_ge\00"
@.s_gt       = private constant [6 x i8]  c"bn_gt\00"
@.s_from_dec = private constant [12 x i8] c"bn_from_dec\00"
@.s_to_dec   = private constant [10 x i8] c"bn_to_dec\00"
@.s_add      = private constant [7 x i8]  c"bn_add\00"
@.s_sub      = private constant [7 x i8]  c"bn_sub\00"
@.s_mul      = private constant [7 x i8]  c"bn_mul\00"
@.s_mod      = private constant [7 x i8]  c"bn_mod\00"
@.s_div      = private constant [7 x i8]  c"bn_div\00"
@.s_is_bn    = private constant [6 x i8]  c"is_bn\00"

declare ptr  @type_void(ptr)
declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Qnum(double)
declare ptr  @Qstr(ptr)
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @pair(ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @boolean(i32)
declare void @define(ptr, ptr)
declare ptr  @str_data(ptr)
declare ptr  @op_is_type(ptr, ptr)
declare ptr  @type_num(ptr)
declare ptr  @type_str(ptr)

declare void @bn_free(ptr)
declare i32  @bn_eq0(ptr)
declare i32  @bn_is_neg(ptr)
declare ptr  @bn_neg(ptr)
declare i32  @bn_cmp(ptr, ptr)
declare ptr  @bn_from_dec(ptr)
declare ptr  @bn_to_dec(ptr)
declare ptr  @bn_add(ptr, ptr)
declare ptr  @bn_sub(ptr, ptr)
declare ptr  @bn_mul(ptr, ptr)
declare ptr  @bn_mod(ptr, ptr)
declare void @bn_div(ptr, ptr, ptr, ptr)

define private void @clear_bn(ptr %f) {
entry:
  %vp = getelementptr %value, ptr %f, i32 0, i32 3
  %x = load ptr, ptr %vp
  call void @bn_free(ptr %x)
  ret void
}
@clear_bn_sentinel = private constant %value { i64 0, ptr @clear_bn, ptr null, ptr null }

define ptr @type_bn(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define private ptr @Qbn(ptr %x) {
entry:
  %r = call ptr @V(ptr @type_bn, ptr @clear_bn_sentinel, ptr %x)
  ret ptr %r
}

define private ptr @op_pred(ptr %f, ptr %op) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_bn
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %b = load ptr, ptr %vp
  %c = call i32 %op(ptr %b)
  %res = call ptr @boolean(i32 %c)
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

define private ptr @type_bn_eq0(ptr %f) { entry: %r = call ptr @op_pred(ptr %f, ptr @bn_eq0) ret ptr %r }
define private ptr @type_bn_is_neg(ptr %f) { entry: %r = call ptr @op_pred(ptr %f, ptr @bn_is_neg) ret ptr %r }

define private ptr @type_bn_neg(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_bn
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %b = load ptr, ptr %vp
  %nb = call ptr @bn_neg(ptr %b)
  %res = call ptr @Qbn(ptr %nb)
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

define private ptr @type_bn_cmp(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %partial = icmp eq ptr %LL, null
  br i1 %partial, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %xarg = load ptr, ptr %LRp
  %x = call ptr @arg(ptr %xarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %yarg = load ptr, ptr %rp
  %y = call ptr @arg(ptr %yarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xb = icmp eq ptr %xt, @type_bn
  %yb = icmp eq ptr %yt, @type_bn
  %both = and i1 %xb, %yb
  br i1 %both, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %c = call i32 @bn_cmp(ptr %xv, ptr %yv)
  %d = sitofp i32 %c to double
  %res = call ptr @Qnum(double %d)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private i32 @pred_lt(i32 %x) { entry: %r = icmp slt i32 %x, 0 %z = zext i1 %r to i32 ret i32 %z }
define private i32 @pred_le(i32 %x) { entry: %r = icmp sle i32 %x, 0 %z = zext i1 %r to i32 ret i32 %z }
define private i32 @pred_eq(i32 %x) { entry: %r = icmp eq i32 %x, 0 %z = zext i1 %r to i32 ret i32 %z }
define private i32 @pred_ne(i32 %x) { entry: %r = icmp ne i32 %x, 0 %z = zext i1 %r to i32 ret i32 %z }
define private i32 @pred_ge(i32 %x) { entry: %r = icmp sge i32 %x, 0 %z = zext i1 %r to i32 ret i32 %z }
define private i32 @pred_gt(i32 %x) { entry: %r = icmp sgt i32 %x, 0 %z = zext i1 %r to i32 ret i32 %z }

define private ptr @op_cmp(ptr %f, ptr %op) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %partial = icmp eq ptr %LL, null
  br i1 %partial, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %xarg = load ptr, ptr %LRp
  %x = call ptr @arg(ptr %xarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %yarg = load ptr, ptr %rp
  %y = call ptr @arg(ptr %yarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xb = icmp eq ptr %xt, @type_bn
  %yb = icmp eq ptr %yt, @type_bn
  %both = and i1 %xb, %yb
  br i1 %both, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %c = call i32 @bn_cmp(ptr %xv, ptr %yv)
  %res0 = call i32 %op(i32 %c)
  %res = call ptr @boolean(i32 %res0)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_bn_lt(ptr %f) { entry: %r = call ptr @op_cmp(ptr %f, ptr @pred_lt) ret ptr %r }
define private ptr @type_bn_le(ptr %f) { entry: %r = call ptr @op_cmp(ptr %f, ptr @pred_le) ret ptr %r }
define private ptr @type_bn_eq(ptr %f) { entry: %r = call ptr @op_cmp(ptr %f, ptr @pred_eq) ret ptr %r }
define private ptr @type_bn_ne(ptr %f) { entry: %r = call ptr @op_cmp(ptr %f, ptr @pred_ne) ret ptr %r }
define private ptr @type_bn_ge(ptr %f) { entry: %r = call ptr @op_cmp(ptr %f, ptr @pred_ge) ret ptr %r }
define private ptr @type_bn_gt(ptr %f) { entry: %r = call ptr @op_cmp(ptr %f, ptr @pred_gt) ret ptr %r }

define private ptr @type_bn_from_dec(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %b = call ptr @bn_from_dec(ptr %s)
  %res = call ptr @Qbn(ptr %b)
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

define private ptr @type_bn_to_dec(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_bn
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %b = load ptr, ptr %vp
  %s = call ptr @bn_to_dec(ptr %b)
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

define private ptr @op_2(ptr %f, ptr %op) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %partial = icmp eq ptr %LL, null
  br i1 %partial, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %xarg = load ptr, ptr %LRp
  %x = call ptr @arg(ptr %xarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %yarg = load ptr, ptr %rp
  %y = call ptr @arg(ptr %yarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xb = icmp eq ptr %xt, @type_bn
  %yb = icmp eq ptr %yt, @type_bn
  %both = and i1 %xb, %yb
  br i1 %both, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %nb = call ptr %op(ptr %xv, ptr %yv)
  %res = call ptr @Qbn(ptr %nb)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_bn_add(ptr %f) { entry: %r = call ptr @op_2(ptr %f, ptr @bn_add) ret ptr %r }
define private ptr @type_bn_sub(ptr %f) { entry: %r = call ptr @op_2(ptr %f, ptr @bn_sub) ret ptr %r }
define private ptr @type_bn_mul(ptr %f) { entry: %r = call ptr @op_2(ptr %f, ptr @bn_mul) ret ptr %r }
define private ptr @type_bn_mod(ptr %f) { entry: %r = call ptr @op_2(ptr %f, ptr @bn_mod) ret ptr %r }

define private ptr @type_bn_div(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %partial = icmp eq ptr %LL, null
  br i1 %partial, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %xarg = load ptr, ptr %LRp
  %x = call ptr @arg(ptr %xarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %yarg = load ptr, ptr %rp
  %y = call ptr @arg(ptr %yarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xb = icmp eq ptr %xt, @type_bn
  %yb = icmp eq ptr %yt, @type_bn
  %both = and i1 %xb, %yb
  br i1 %both, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %q = alloca ptr, align 8
  %r = alloca ptr, align 8
  call void @bn_div(ptr %xv, ptr %yv, ptr %q, ptr %r)
  %qv = load ptr, ptr %q
  %rv = load ptr, ptr %r
  %bq = call ptr @Qbn(ptr %qv)
  %br = call ptr @Qbn(ptr %rv)
  %res = call ptr @pair(ptr %bq, ptr %br)
  br label %done
void:
  %qvv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qvv)
  br label %done
done:
  %result = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %result
}

define private ptr @type_is_bn(ptr %f) {
entry:
  %r = call ptr @op_is_type(ptr %f, ptr @type_bn)
  ret ptr %r
}

define ptr @type_load_bn(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_bn_eq0)
  call void @define(ptr @.s_eq0, ptr %q0)
  %q1 = call ptr @Q(ptr @type_bn_is_neg)
  call void @define(ptr @.s_is_neg, ptr %q1)
  %q2 = call ptr @Q(ptr @type_bn_neg)
  call void @define(ptr @.s_neg, ptr %q2)
  %q3 = call ptr @Q(ptr @type_bn_cmp)
  call void @define(ptr @.s_cmp, ptr %q3)
  %q4 = call ptr @Q(ptr @type_bn_lt)
  call void @define(ptr @.s_lt, ptr %q4)
  %q5 = call ptr @Q(ptr @type_bn_le)
  call void @define(ptr @.s_le, ptr %q5)
  %q6 = call ptr @Q(ptr @type_bn_eq)
  call void @define(ptr @.s_eq, ptr %q6)
  %q7 = call ptr @Q(ptr @type_bn_ne)
  call void @define(ptr @.s_ne, ptr %q7)
  %q8 = call ptr @Q(ptr @type_bn_ge)
  call void @define(ptr @.s_ge, ptr %q8)
  %q9 = call ptr @Q(ptr @type_bn_gt)
  call void @define(ptr @.s_gt, ptr %q9)
  %q10 = call ptr @Q(ptr @type_bn_from_dec)
  call void @define(ptr @.s_from_dec, ptr %q10)
  %q11 = call ptr @Q(ptr @type_bn_to_dec)
  call void @define(ptr @.s_to_dec, ptr %q11)
  %q12 = call ptr @Q(ptr @type_bn_add)
  call void @define(ptr @.s_add, ptr %q12)
  %q13 = call ptr @Q(ptr @type_bn_sub)
  call void @define(ptr @.s_sub, ptr %q13)
  %q14 = call ptr @Q(ptr @type_bn_mul)
  call void @define(ptr @.s_mul, ptr %q14)
  %q15 = call ptr @Q(ptr @type_bn_mod)
  call void @define(ptr @.s_mod, ptr %q15)
  %q16 = call ptr @Q(ptr @type_bn_div)
  call void @define(ptr @.s_div, ptr %q16)
  %q17 = call ptr @Q(ptr @type_is_bn)
  call void @define(ptr @.s_is_bn, ptr %q17)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
