; fexl/type_signal.ll — manejadores de serial (antes src/type_signal.c).

@QI = external global ptr

@.s_set_alarm   = private constant [10 x i8] c"set_alarm\00"
@.s_sigaction_err = private constant [19 x i8] c"sigaction(2) error\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare void @define(ptr, ptr)
declare i64  @get_ulong(ptr)
declare ptr  @type_num(ptr)
declare i32  @sigemptyset(ptr)
declare i32  @sigaction(i32, ptr, ptr)
declare i32  @alarm(i32)
declare void @perror(ptr)
declare void @exit(i32)

define private void @handle_signal(i32 %signum) {
entry:
  ret void
}

define private void @set_handler(i32 %signum) {
entry:
  %act = alloca [152 x i8], align 8
  %hp = getelementptr [152 x i8], ptr %act, i64 0, i64 0
  store ptr @handle_signal, ptr %hp
  %flagp = getelementptr [152 x i8], ptr %act, i64 0, i64 136
  store i32 0, ptr %flagp
  %maskp = getelementptr [152 x i8], ptr %act, i64 0, i64 8
  %e = call i32 @sigemptyset(ptr %maskp)
  %r = call i32 @sigaction(i32 %signum, ptr %act, ptr null)
  %bad = icmp slt i32 %r, 0
  br i1 %bad, label %die, label %done
die:
  call void @perror(ptr @.s_sigaction_err)
  call void @exit(i32 1)
  unreachable
done:
  ret void
}

define private ptr @type_set_alarm(ptr %f) {
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
  %sec = trunc i64 %n to i32
  %old = call i32 @alarm(i32 %sec)
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

define ptr @type_load_signal(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_set_alarm)
  call void @define(ptr @.s_set_alarm, ptr %q0)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define void @beg_signal() {
entry:
  call void @set_handler(i32 14)
  call void @set_handler(i32 17)
  ret void
}

define void @end_signal() {
entry:
  ret void
}

@Qvoid = external global ptr
