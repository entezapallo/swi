; fexl/type_time.ll — builtins de tiempo (antes src/type_time.c).

%Timeval = type { i64, i64 }

@QI    = external global ptr
@Qvoid = external global ptr

@.s_time       = private constant [5 x i8] c"time\00"
@.s_localtime  = private constant [10 x i8] c"localtime\00"
@.s_gmtime     = private constant [7 x i8] c"gmtime\00"
@.s_timelocal  = private constant [10 x i8] c"timelocal\00"
@.s_timegm     = private constant [7 x i8] c"timegm\00"
@.s_microtime  = private constant [10 x i8] c"microtime\00"
@.s_dow        = private constant [4 x i8] c"dow\00"
@.fmt          = private constant [18 x i8] c"%Y-%m-%d %H:%M:%S\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @Qnum(double)
declare ptr  @Qstr(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare void @define(ptr, ptr)
declare ptr  @str_data(ptr)
declare ptr  @format_uint64_t(i64)
declare ptr  @type_num(ptr)
declare ptr  @type_str(ptr)

declare i64  @time(ptr)
declare ptr  @localtime(ptr)
declare ptr  @gmtime(ptr)
declare i64  @mktime(ptr)
declare i64  @timegm(ptr)
declare i64  @strftime(ptr, i64, ptr, ptr)
declare ptr  @strptime(ptr, ptr, ptr)
declare i32  @gettimeofday(ptr, ptr)

define private ptr @type_time(ptr %f) {
entry:
  %p = alloca i64, align 8
  %n = call i64 @time(ptr %p)
  %d = sitofp i64 %n to double
  %r = call ptr @Qnum(double %d)
  ret ptr %r
}

define private ptr @op_strftime(ptr %f, ptr %convert) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_num
  br i1 %is, label %yes, label %void
yes:
  %dp = getelementptr %value, ptr %x, i32 0, i32 3
  %d = load double, ptr %dp
  %n = fptosi double %d to i64
  %np = alloca i64, align 8
  store i64 %n, ptr %np
  %tm = call ptr %convert(ptr %np)
  %buf = alloca [32 x i8], align 1
  %written = call i64 @strftime(ptr %buf, i64 32, ptr @.fmt, ptr %tm)
  %s = call ptr @Qstr(ptr %buf)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %s, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @op_strptime(ptr %f, ptr %convert) {
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
  %tm = alloca [64 x i8], align 8
  %result = call ptr @strptime(ptr %s, ptr @.fmt, ptr %tm)
  %nonnull = icmp ne ptr %result, null
  br i1 %nonnull, label %mk, label %void
mk:
  %n = call i64 %convert(ptr %tm)
  %d = sitofp i64 %n to double
  %res = call ptr @Qnum(double %d)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %mk ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_localtime(ptr %f) { entry: %r = call ptr @op_strftime(ptr %f, ptr @localtime) ret ptr %r }
define private ptr @type_gmtime(ptr %f) { entry: %r = call ptr @op_strftime(ptr %f, ptr @gmtime) ret ptr %r }
define private ptr @type_timelocal(ptr %f) { entry: %r = call ptr @op_strptime(ptr %f, ptr @mktime) ret ptr %r }
define private ptr @type_timegm(ptr %f) { entry: %r = call ptr @op_strptime(ptr %f, ptr @timegm) ret ptr %r }

define private ptr @type_microtime(ptr %f) {
entry:
  %tv = alloca %Timeval, align 8
  %r = call i32 @gettimeofday(ptr %tv, ptr null)
  %secp = getelementptr %Timeval, ptr %tv, i32 0, i32 0
  %sec = load i64, ptr %secp
  %usecp = getelementptr %Timeval, ptr %tv, i32 0, i32 1
  %usec = load i64, ptr %usecp
  %m = mul i64 %sec, 1000000
  %n = add i64 %m, %usec
  %s = call ptr @format_uint64_t(i64 %n)
  %res = call ptr @Qstr(ptr %s)
  ret ptr %res
}

define private i32 @get_dow(i32 %y, i32 %m, i32 %d) {
entry:
  %lt3 = icmp slt i32 %m, 3
  br i1 %lt3, label %decy, label %table
decy:
  %y1 = sub i32 %y, 1
  br label %table
table:
  %yy = phi i32 [ %y, %entry ], [ %y1, %decy ]
  %tidx = sub i32 %m, 1
  %ti = zext i32 %tidx to i64
  %tp = getelementptr [12 x i32], ptr @.dow_table, i64 0, i64 %ti
  %t = load i32, ptr %tp
  %d1 = udiv i32 %yy, 4
  %d2 = udiv i32 %yy, 100
  %d3 = udiv i32 %yy, 400
  %s1 = add i32 %yy, %d1
  %s2 = sub i32 %s1, %d2
  %s3 = add i32 %s2, %d3
  %s4 = add i32 %s3, %t
  %s5 = add i32 %s4, %d
  %r = srem i32 %s5, 7
  ret i32 %r
}

define private ptr @type_dow(ptr %f) {
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
  %a1arg = load ptr, ptr %LLRp
  %a1 = call ptr @arg(ptr %a1arg)
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %a2arg = load ptr, ptr %LRp
  %a2 = call ptr @arg(ptr %a2arg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %a3arg = load ptr, ptr %rp
  %a3 = call ptr @arg(ptr %a3arg)
  %t1p = getelementptr %value, ptr %a1, i32 0, i32 1
  %t1 = load ptr, ptr %t1p
  %t2p = getelementptr %value, ptr %a2, i32 0, i32 1
  %t2 = load ptr, ptr %t2p
  %t3p = getelementptr %value, ptr %a3, i32 0, i32 1
  %t3 = load ptr, ptr %t3p
  %n1 = icmp eq ptr %t1, @type_num
  %n2 = icmp eq ptr %t2, @type_num
  %n3 = icmp eq ptr %t3, @type_num
  %a = and i1 %n1, %n2
  %all = and i1 %a, %n3
  br i1 %all, label %yes, label %void
yes:
  %d1p = getelementptr %value, ptr %a1, i32 0, i32 3
  %dv1 = load double, ptr %d1p
  %y = fptosi double %dv1 to i32
  %d2p = getelementptr %value, ptr %a2, i32 0, i32 3
  %dv2 = load double, ptr %d2p
  %m = fptosi double %dv2 to i32
  %d3p = getelementptr %value, ptr %a3, i32 0, i32 3
  %dv3 = load double, ptr %d3p
  %dd = fptosi double %dv3 to i32
  %dow = call i32 @get_dow(i32 %y, i32 %m, i32 %dd)
  %zero = icmp eq i32 %dow, 0
  %final = select i1 %zero, i32 7, i32 %dow
  %fd = sitofp i32 %final to double
  %res = call ptr @Qnum(double %fd)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %a1)
  call void @drop(ptr %a2)
  call void @drop(ptr %a3)
  ret ptr %r
}

define ptr @type_load_time(ptr %f) {
entry:
  %q0 = call ptr @Q0(ptr @type_time)
  call void @define(ptr @.s_time, ptr %q0)
  %q1 = call ptr @Q(ptr @type_localtime)
  call void @define(ptr @.s_localtime, ptr %q1)
  %q2 = call ptr @Q(ptr @type_gmtime)
  call void @define(ptr @.s_gmtime, ptr %q2)
  %q3 = call ptr @Q(ptr @type_timelocal)
  call void @define(ptr @.s_timelocal, ptr %q3)
  %q4 = call ptr @Q(ptr @type_timegm)
  call void @define(ptr @.s_timegm, ptr %q4)
  %q5 = call ptr @Q0(ptr @type_microtime)
  call void @define(ptr @.s_microtime, ptr %q5)
  %q6 = call ptr @Q(ptr @type_dow)
  call void @define(ptr @.s_dow, ptr %q6)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

@.dow_table = private constant [12 x i32] [i32 0, i32 3, i32 2, i32 5, i32 0, i32 3, i32 5, i32 1, i32 4, i32 6, i32 2, i32 4]
