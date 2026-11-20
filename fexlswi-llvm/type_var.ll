; fexl/type_var.ll — variables mutables (antes src/type_var.c).

@QI    = external global ptr
@Qvoid = external global ptr

@.s_var_new   = private constant [8 x i8] c"var_new\00"
@.s_var_get   = private constant [8 x i8] c"var_get\00"
@.s_var_getf  = private constant [9 x i8] c"var_getf\00"
@.s_var_put   = private constant [8 x i8] c"var_put\00"
@.s_var_putf  = private constant [9 x i8] c"var_putf\00"
@.s_is_var    = private constant [7 x i8] c"is_var\00"

declare ptr  @type_void(ptr)
declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @yield(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @arg(ptr)
declare void @define(ptr, ptr)
declare ptr  @op_is_type(ptr, ptr)

define private void @clear_var(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %v = load ptr, ptr %rp
  call void @drop(ptr %v)
  ret void
}
@clear_var_sentinel = private constant %value { i64 0, ptr @clear_var, ptr null, ptr null }

define private ptr @type_var(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define private ptr @type_var_new(ptr %f) {
entry:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  %r = call ptr @V(ptr @type_var, ptr @clear_var_sentinel, ptr %h)
  ret ptr %r
}

define private ptr @type_var_get(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_var
  br i1 %is, label %yes, label %void
yes:
  %xrp = getelementptr %value, ptr %x, i32 0, i32 3
  %v = load ptr, ptr %xrp
  %h = call ptr @hold(ptr %v)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %h, %yes ], [ %h2, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_var_getf(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_var
  br i1 %is, label %yes, label %void
yes:
  %xrp = getelementptr %value, ptr %x, i32 0, i32 3
  %v = load ptr, ptr %xrp
  %hv = call ptr @hold(ptr %v)
  %res = call ptr @yield(ptr %hv)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h2, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @op_put(ptr %f, ptr %op) {
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
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %is = icmp eq ptr %xt, @type_var
  br i1 %is, label %yes, label %void
yes:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %varg = load ptr, ptr %rp
  %v = call ptr %op(ptr %varg)
  %xrp = getelementptr %value, ptr %x, i32 0, i32 3
  %old = load ptr, ptr %xrp
  call void @drop(ptr %old)
  store ptr %v, ptr %xrp
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %hqi, %yes ], [ %h2, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_var_put(ptr %f) {
entry:
  %r = call ptr @op_put(ptr %f, ptr @arg)
  ret ptr %r
}
define private ptr @type_var_putf(ptr %f) {
entry:
  %r = call ptr @op_put(ptr %f, ptr @hold)
  ret ptr %r
}
define private ptr @type_is_var(ptr %f) {
entry:
  %r = call ptr @op_is_type(ptr %f, ptr @type_var)
  ret ptr %r
}

define ptr @type_load_var(ptr %f) {
entry:
  %q0 = call ptr @Q0(ptr @type_var_new)
  call void @define(ptr @.s_var_new, ptr %q0)
  %q1 = call ptr @Q(ptr @type_var_get)
  call void @define(ptr @.s_var_get, ptr %q1)
  %q2 = call ptr @Q(ptr @type_var_getf)
  call void @define(ptr @.s_var_getf, ptr %q2)
  %q3 = call ptr @Q(ptr @type_var_put)
  call void @define(ptr @.s_var_put, ptr %q3)
  %q4 = call ptr @Q(ptr @type_var_putf)
  call void @define(ptr @.s_var_putf, ptr %q4)
  %q5 = call ptr @Q(ptr @type_is_var)
  call void @define(ptr @.s_is_var, ptr %q5)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
