; fexl/type_cmp.ll — comparaciones del intérprete Fexl (antes type_cmp.c).
; value_types.ll se inyecta por concatenacion en el build.

@QI    = external global ptr
@Qvoid = external global ptr

@.s_compare = private constant [8 x i8] c"compare\00"
@.s_lt = private constant [3 x i8] c"lt\00"
@.s_le = private constant [3 x i8] c"le\00"
@.s_eq = private constant [3 x i8] c"eq\00"
@.s_ne = private constant [3 x i8] c"ne\00"
@.s_ge = private constant [3 x i8] c"ge\00"
@.s_gt = private constant [3 x i8] c"gt\00"

declare ptr  @arg(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @boolean(i32)
declare ptr  @Q(ptr)
declare void @define(ptr, ptr)
declare i32  @num_cmp(double, double)
declare i32  @str_cmp(ptr, ptr)
declare ptr  @type_num(ptr)
declare ptr  @type_str(ptr)

; los seis operadores int(int) del C
define private i32 @op_lt(i32 %x) {
entry:
  %c = icmp slt i32 %x, 0
  %r = zext i1 %c to i32
  ret i32 %r
}
define private i32 @op_le(i32 %x) {
entry:
  %c = icmp sle i32 %x, 0
  %r = zext i1 %c to i32
  ret i32 %r
}
define private i32 @op_eq(i32 %x) {
entry:
  %c = icmp eq i32 %x, 0
  %r = zext i1 %c to i32
  ret i32 %r
}
define private i32 @op_ne(i32 %x) {
entry:
  %c = icmp ne i32 %x, 0
  %r = zext i1 %c to i32
  ret i32 %r
}
define private i32 @op_ge(i32 %x) {
entry:
  %c = icmp sge i32 %x, 0
  %r = zext i1 %c to i32
  ret i32 %r
}
define private i32 @op_gt(i32 %x) {
entry:
  %c = icmp sgt i32 %x, 0
  %r = zext i1 %c to i32
  ret i32 %r
}

define private ptr @op_cmp(ptr %f, ptr %op) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %iszero = icmp eq ptr %LL, null
  br i1 %iszero, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %lrval = load ptr, ptr %LRp
  %x = call ptr @arg(ptr %lrval)
  %Rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rval = load ptr, ptr %Rp
  %y = call ptr @arg(ptr %rval)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xnum = icmp eq ptr %xt, @type_num
  %ynum = icmp eq ptr %yt, @type_num
  %nums = and i1 %xnum, %ynum
  br i1 %nums, label %cmpnum, label %checkstr
cmpnum:
  %xdp = getelementptr %value, ptr %x, i32 0, i32 3
  %xd = load double, ptr %xdp
  %ydp = getelementptr %value, ptr %y, i32 0, i32 3
  %yd = load double, ptr %ydp
  %c = call i32 @num_cmp(double %xd, double %yd)
  %res = call i32 %op(i32 %c)
  %b = call ptr @boolean(i32 %res)
  br label %done
checkstr:
  %xstr = icmp eq ptr %xt, @type_str
  %ystr = icmp eq ptr %yt, @type_str
  %strs = and i1 %xstr, %ystr
  br i1 %strs, label %cmpstr, label %void
cmpstr:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %c2 = call i32 @str_cmp(ptr %xv, ptr %yv)
  %res2 = call i32 %op(i32 %c2)
  %b2 = call ptr @boolean(i32 %res2)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %b3 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %b, %cmpnum ], [ %b2, %cmpstr ], [ %b3, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_lt(ptr %f) {
entry:
  %r = call ptr @op_cmp(ptr %f, ptr @op_lt)
  ret ptr %r
}
define private ptr @type_le(ptr %f) {
entry:
  %r = call ptr @op_cmp(ptr %f, ptr @op_le)
  ret ptr %r
}
define private ptr @type_eq(ptr %f) {
entry:
  %r = call ptr @op_cmp(ptr %f, ptr @op_eq)
  ret ptr %r
}
define private ptr @type_ne(ptr %f) {
entry:
  %r = call ptr @op_cmp(ptr %f, ptr @op_ne)
  ret ptr %r
}
define private ptr @type_ge(ptr %f) {
entry:
  %r = call ptr @op_cmp(ptr %f, ptr @op_ge)
  ret ptr %r
}
define private ptr @type_gt(ptr %f) {
entry:
  %r = call ptr @op_cmp(ptr %f, ptr @op_gt)
  ret ptr %r
}

; (compare x y LT EQ GT)
define private ptr @type_compare(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %a = icmp eq ptr %LL, null
  br i1 %a, label %keepf, label %lv3
lv3:
  %LLLp = getelementptr %value, ptr %LL, i32 0, i32 2
  %LLL = load ptr, ptr %LLLp
  %b = icmp eq ptr %LLL, null
  br i1 %b, label %keepf, label %lv4
lv4:
  %LLLLp = getelementptr %value, ptr %LLL, i32 0, i32 2
  %LLLL = load ptr, ptr %LLLLp
  %c = icmp eq ptr %LLLL, null
  br i1 %c, label %keepf, label %lv5
lv5:
  %LLLLLp = getelementptr %value, ptr %LLLL, i32 0, i32 2
  %LLLLL = load ptr, ptr %LLLLLp
  %d = icmp eq ptr %LLLLL, null
  br i1 %d, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %xsrc = getelementptr %value, ptr %LLLL, i32 0, i32 3
  %xarg = load ptr, ptr %xsrc
  %x = call ptr @arg(ptr %xarg)
  %ysrc = getelementptr %value, ptr %LLL, i32 0, i32 3
  %yarg = load ptr, ptr %ysrc
  %y = call ptr @arg(ptr %yarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xnum = icmp eq ptr %xt, @type_num
  %ynum = icmp eq ptr %yt, @type_num
  %nums = and i1 %xnum, %ynum
  br i1 %nums, label %cmpnum, label %checkstr
cmpnum:
  %xdp = getelementptr %value, ptr %x, i32 0, i32 3
  %xd = load double, ptr %xdp
  %ydp = getelementptr %value, ptr %y, i32 0, i32 3
  %yd = load double, ptr %ydp
  %lt = fcmp olt double %xd, %yd
  %eqv = fcmp oeq double %xd, %yd
  br i1 %lt, label %less, label %checkeq
checkeq:
  br i1 %eqv, label %equal, label %greater
checkstr:
  %xstr = icmp eq ptr %xt, @type_str
  %ystr = icmp eq ptr %yt, @type_str
  %strs = and i1 %xstr, %ystr
  br i1 %strs, label %cmpstr, label %void
cmpstr:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %c2 = call i32 @str_cmp(ptr %xv, ptr %yv)
  %slt = icmp slt i32 %c2, 0
  %seqv = icmp eq i32 %c2, 0
  br i1 %slt, label %less, label %checkeq2
checkeq2:
  br i1 %seqv, label %equal, label %greater
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
less:
  %LLRp = getelementptr %value, ptr %LL, i32 0, i32 3
  %LLR = load ptr, ptr %LLRp
  %hl = call ptr @hold(ptr %LLR)
  br label %done
equal:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %LR = load ptr, ptr %LRp
  %he = call ptr @hold(ptr %LR)
  br label %done
greater:
  %Rp = getelementptr %value, ptr %f, i32 0, i32 3
  %R = load ptr, ptr %Rp
  %hg = call ptr @hold(ptr %R)
  br label %done
done:
  %r = phi ptr [ %h, %void ], [ %hl, %less ], [ %he, %equal ], [ %hg, %greater ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define ptr @type_load_cmp(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_compare)
  call void @define(ptr @.s_compare, ptr %q0)
  %q1 = call ptr @Q(ptr @type_lt)
  call void @define(ptr @.s_lt, ptr %q1)
  %q2 = call ptr @Q(ptr @type_le)
  call void @define(ptr @.s_le, ptr %q2)
  %q3 = call ptr @Q(ptr @type_eq)
  call void @define(ptr @.s_eq, ptr %q3)
  %q4 = call ptr @Q(ptr @type_ne)
  call void @define(ptr @.s_ne, ptr %q4)
  %q5 = call ptr @Q(ptr @type_ge)
  call void @define(ptr @.s_ge, ptr %q5)
  %q6 = call ptr @Q(ptr @type_gt)
  call void @define(ptr @.s_gt, ptr %q6)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
