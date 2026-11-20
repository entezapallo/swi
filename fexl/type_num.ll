; fexl/type_num.ll — tipo número del intérprete Fexl (antes type_num.c).
; value_types.ll se inyecta por concatenacion en el build.

@QI    = external global ptr
@Qvoid = external global ptr

@.s_num_str = private constant [8 x i8] c"num_str\00"
@.s_is_num  = private constant [7 x i8] c"is_num\00"

declare ptr  @type_void(ptr)
declare ptr  @new_value()
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Qstr(ptr)
declare ptr  @op_is_type(ptr, ptr)
declare void @define(ptr, ptr)
declare i32  @str0_double(ptr, ptr)
declare ptr  @format_double(double)
declare ptr  @str_new_data0(ptr)

; centinela de dato: N=0, T=clear_num. value.ll lo usa para reconocer datos.
define private void @clear_num(ptr %f) {
entry:
  ret void
}
@clear_num_sentinel = private constant %value { i64 0, ptr @clear_num, ptr null, ptr null }

define i32 @num_cmp(double %x, double %y) {
entry:
  %lt = fcmp olt double %x, %y
  %gt = fcmp ogt double %x, %y
  %r = select i1 %lt, i32 -1, i32 0
  %r2 = select i1 %gt, i32 1, i32 %r
  ret i32 %r2
}

define ptr @type_num(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define ptr @Qnum(double %x) {
entry:
  %f = call ptr @new_value()
  %np = getelementptr %value, ptr %f, i32 0, i32 0
  store i64 1, ptr %np
  %tp = getelementptr %value, ptr %f, i32 0, i32 1
  store ptr @type_num, ptr %tp
  %lp = getelementptr %value, ptr %f, i32 0, i32 2
  store ptr @clear_num_sentinel, ptr %lp
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  store double %x, ptr %rp
  ret ptr %f
}

define ptr @Qnum_str0(ptr %name) {
entry:
  %d = alloca double, align 8
  %ok = call i32 @str0_double(ptr %name, ptr %d)
  %good = icmp eq i32 %ok, 1
  br i1 %good, label %yes, label %no
yes:
  %v = load double, ptr %d, align 8
  %n = call ptr @Qnum(double %v)
  ret ptr %n
no:
  ret ptr null
}

define i64 @get_ulong(ptr %x) {
entry:
  %rp = getelementptr %value, ptr %x, i32 0, i32 3
  %d = load double, ptr %rp
  %nonneg = fcmp oge double %d, 0.0
  br i1 %nonneg, label %conv, label %zero
conv:
  %u = fptosi double %d to i64
  ret i64 %u
zero:
  ret i64 0
}

define private ptr @type_num_str(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isnum = icmp eq ptr %t, @type_num
  br i1 %isnum, label %num, label %void
num:
  %dp = getelementptr %value, ptr %x, i32 0, i32 3
  %d = load double, ptr %dp
  %cstr = call ptr @format_double(double %d)
  %s = call ptr @str_new_data0(ptr %cstr)
  %q = call ptr @Qstr(ptr %s)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %num ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_is_num(ptr %f) {
entry:
  %r = call ptr @op_is_type(ptr %f, ptr @type_num)
  ret ptr %r
}

define ptr @type_load_num(ptr %f) {
entry:
  %q1 = call ptr @Q(ptr @type_num_str)
  call void @define(ptr @.s_num_str, ptr %q1)
  %q2 = call ptr @Q(ptr @type_is_num)
  call void @define(ptr @.s_is_num, ptr %q2)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
