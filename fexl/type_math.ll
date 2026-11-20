; fexl/type_math.ll — operaciones numericas (antes src/type_math.c).

@QI    = external global ptr
@Qvoid = external global ptr

@.s_add = private constant [2 x i8] c"+\00"
@.s_sub = private constant [2 x i8] c"-\00"
@.s_mul = private constant [2 x i8] c"*\00"
@.s_div = private constant [2 x i8] c"/\00"
@.s_pow = private constant [2 x i8] c"^\00"
@.s_xor = private constant [4 x i8] c"xor\00"
@.s_round = private constant [6 x i8] c"round\00"
@.s_ceil = private constant [5 x i8] c"ceil\00"
@.s_trunc = private constant [6 x i8] c"trunc\00"
@.s_abs = private constant [4 x i8] c"abs\00"
@.s_sqrt = private constant [5 x i8] c"sqrt\00"
@.s_exp = private constant [4 x i8] c"exp\00"
@.s_log = private constant [4 x i8] c"log\00"
@.s_sin = private constant [4 x i8] c"sin\00"
@.s_cos = private constant [4 x i8] c"cos\00"
@.s_tan = private constant [4 x i8] c"tan\00"
@.s_atan = private constant [5 x i8] c"atan\00"
@.s_pi = private constant [3 x i8] c"pi\00"

@pi = private constant double 0x400921FB54442D18

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Qnum(double)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare void @define(ptr, ptr)
declare ptr  @type_num(ptr)

declare double @pow(double, double)
declare double @round(double)
declare double @ceil(double)
declare double @trunc(double)
declare double @fabs(double)
declare double @sqrt(double)
declare double @exp(double)
declare double @log(double)
declare double @sin(double)
declare double @cos(double)
declare double @tan(double)
declare double @atan(double)

define private double @op_add(double %x, double %y) { entry: %r = fadd double %x, %y  ret double %r }
define private double @op_sub(double %x, double %y) { entry: %r = fsub double %x, %y  ret double %r }
define private double @op_mul(double %x, double %y) { entry: %r = fmul double %x, %y  ret double %r }
define private double @op_div(double %x, double %y) { entry: %r = fdiv double %x, %y  ret double %r }
define private double @op_xor(double %x, double %y) {
entry:
  %xi = fptosi double %x to i64
  %yi = fptosi double %y to i64
  %v = xor i64 %xi, %yi
  %r = sitofp i64 %v to double
  ret double %r
}

define private ptr @op_num(ptr %f, ptr %op) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_num
  br i1 %is, label %yes, label %void
yes:
  %dp = getelementptr %value, ptr %x, i32 0, i32 3
  %d = load double, ptr %dp
  %v = call double %op(double %d)
  %q = call ptr @Qnum(double %v)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @op_num_num(ptr %f, ptr %op) {
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
  %xs = icmp eq ptr %xt, @type_num
  %ys = icmp eq ptr %yt, @type_num
  %both = and i1 %xs, %ys
  br i1 %both, label %yes, label %void
yes:
  %xdp = getelementptr %value, ptr %x, i32 0, i32 3
  %xd = load double, ptr %xdp
  %ydp = getelementptr %value, ptr %y, i32 0, i32 3
  %yd = load double, ptr %ydp
  %v = call double %op(double %xd, double %yd)
  %q = call ptr @Qnum(double %v)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_add(ptr %f) { entry: %r = call ptr @op_num_num(ptr %f, ptr @op_add) ret ptr %r }
define private ptr @type_sub(ptr %f) { entry: %r = call ptr @op_num_num(ptr %f, ptr @op_sub) ret ptr %r }
define private ptr @type_mul(ptr %f) { entry: %r = call ptr @op_num_num(ptr %f, ptr @op_mul) ret ptr %r }
define private ptr @type_div(ptr %f) { entry: %r = call ptr @op_num_num(ptr %f, ptr @op_div) ret ptr %r }
define private ptr @type_pow(ptr %f) { entry: %r = call ptr @op_num_num(ptr %f, ptr @pow) ret ptr %r }
define private ptr @type_xor(ptr %f) { entry: %r = call ptr @op_num_num(ptr %f, ptr @op_xor) ret ptr %r }
define private ptr @type_round(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @round) ret ptr %r }
define private ptr @type_ceil(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @ceil) ret ptr %r }
define private ptr @type_trunc(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @trunc) ret ptr %r }
define private ptr @type_abs(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @fabs) ret ptr %r }
define private ptr @type_sqrt(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @sqrt) ret ptr %r }
define private ptr @type_exp(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @exp) ret ptr %r }
define private ptr @type_log(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @log) ret ptr %r }
define private ptr @type_sin(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @sin) ret ptr %r }
define private ptr @type_cos(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @cos) ret ptr %r }
define private ptr @type_tan(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @tan) ret ptr %r }
define private ptr @type_atan(ptr %f) { entry: %r = call ptr @op_num(ptr %f, ptr @atan) ret ptr %r }

define ptr @type_load_math(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_add)
  call void @define(ptr @.s_add, ptr %q0)
  %q1 = call ptr @Q(ptr @type_sub)
  call void @define(ptr @.s_sub, ptr %q1)
  %q2 = call ptr @Q(ptr @type_mul)
  call void @define(ptr @.s_mul, ptr %q2)
  %q3 = call ptr @Q(ptr @type_div)
  call void @define(ptr @.s_div, ptr %q3)
  %q4 = call ptr @Q(ptr @type_pow)
  call void @define(ptr @.s_pow, ptr %q4)
  %q5 = call ptr @Q(ptr @type_xor)
  call void @define(ptr @.s_xor, ptr %q5)
  %q6 = call ptr @Q(ptr @type_round)
  call void @define(ptr @.s_round, ptr %q6)
  %q7 = call ptr @Q(ptr @type_ceil)
  call void @define(ptr @.s_ceil, ptr %q7)
  %q8 = call ptr @Q(ptr @type_trunc)
  call void @define(ptr @.s_trunc, ptr %q8)
  %q9 = call ptr @Q(ptr @type_abs)
  call void @define(ptr @.s_abs, ptr %q9)
  %q10 = call ptr @Q(ptr @type_sqrt)
  call void @define(ptr @.s_sqrt, ptr %q10)
  %q11 = call ptr @Q(ptr @type_exp)
  call void @define(ptr @.s_exp, ptr %q11)
  %q12 = call ptr @Q(ptr @type_log)
  call void @define(ptr @.s_log, ptr %q12)
  %q13 = call ptr @Q(ptr @type_sin)
  call void @define(ptr @.s_sin, ptr %q13)
  %q14 = call ptr @Q(ptr @type_cos)
  call void @define(ptr @.s_cos, ptr %q14)
  %q15 = call ptr @Q(ptr @type_tan)
  call void @define(ptr @.s_tan, ptr %q15)
  %q16 = call ptr @Q(ptr @type_atan)
  call void @define(ptr @.s_atan, ptr %q16)
  %pi = call ptr @Qnum(double 0x400921FB54442D18)
  call void @define(ptr @.s_pi, ptr %pi)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
