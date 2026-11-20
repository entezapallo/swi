; fexl/type_limit.ll — limites de ejecucion (antes src/type_limit.c).

@QI    = external global ptr
@Qvoid = external global ptr

@.s_time   = private constant [11 x i8] c"limit_time\00"
@.s_stack  = private constant [12 x i8] c"limit_stack\00"
@.s_memory = private constant [13 x i8] c"limit_memory\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare void @define(ptr, ptr)
declare i64  @get_ulong(ptr)
declare ptr  @type_num(ptr)
declare void @limit_time(i64)
declare void @limit_stack(i64)
declare void @limit_memory(i64)

define private ptr @op_limit(ptr %f, ptr %op) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_num
  br i1 %is, label %yes, label %void
yes:
  %n = call i64 @get_ulong(ptr %x)
  call void %op(i64 %n)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
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

define private ptr @type_limit_time(ptr %f) {
entry:
  %r = call ptr @op_limit(ptr %f, ptr @limit_time)
  ret ptr %r
}
define private ptr @type_limit_stack(ptr %f) {
entry:
  %r = call ptr @op_limit(ptr %f, ptr @limit_stack)
  ret ptr %r
}
define private ptr @type_limit_memory(ptr %f) {
entry:
  %r = call ptr @op_limit(ptr %f, ptr @limit_memory)
  ret ptr %r
}

define ptr @type_load_limit(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_limit_time)
  call void @define(ptr @.s_time, ptr %q0)
  %q1 = call ptr @Q(ptr @type_limit_stack)
  call void @define(ptr @.s_stack, ptr %q1)
  %q2 = call ptr @Q(ptr @type_limit_memory)
  call void @define(ptr @.s_memory, ptr %q2)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
