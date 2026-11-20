; fexl/type_output.ll — salida y impresion (antes src/type_output.c).
; value_types.ll se inyecta por concatenacion en el build.

@Qput  = internal global ptr null
@Qnl   = internal global ptr null
@Qfput = internal global ptr null
@Qfnl  = internal global ptr null

@stdout = external global ptr

@.s_put    = private constant [4 x i8] c"put\00"
@.s_nl     = private constant [3 x i8] c"nl\00"
@.s_say    = private constant [4 x i8] c"say\00"
@.s_fput   = private constant [5 x i8] c"fput\00"
@.s_fnl    = private constant [4 x i8] c"fnl\00"
@.s_fsay   = private constant [5 x i8] c"fsay\00"
@.s_fflush = private constant [7 x i8] c"fflush\00"

declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @A(ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @arg(ptr)
declare void @define(ptr, ptr)
declare ptr  @type_list(ptr)
declare ptr  @type_str(ptr)
declare ptr  @type_num(ptr)
declare ptr  @type_T(ptr)
declare ptr  @type_F(ptr)
declare ptr  @type_bn(ptr)
declare ptr  @type_file(ptr)
declare void @fput_str(ptr, ptr)
declare void @fput_double(ptr, double)
declare void @fput_ch(ptr, i8)
declare void @fnl(ptr)
declare void @nl()
declare void @fflush(ptr)
declare ptr  @bn_to_dec(ptr)
declare void @str_free(ptr)

@QI    = external global ptr
@Qvoid = external global ptr

define private ptr @op_put(ptr %fh, ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %islist = icmp eq ptr %xt, @type_list
  br i1 %islist, label %listcase, label %dispatch
listcase:
  %lp = getelementptr %value, ptr %f, i32 0, i32 2
  %lf = load ptr, ptr %lp
  %xlp = getelementptr %value, ptr %x, i32 0, i32 2
  %xl = load ptr, ptr %xlp
  %xrp = getelementptr %value, ptr %x, i32 0, i32 3
  %xr = load ptr, ptr %xrp
  %h1 = call ptr @hold(ptr %lf)
  %h2 = call ptr @hold(ptr %xl)
  %h3 = call ptr @hold(ptr %lf)
  %h4 = call ptr @hold(ptr %xr)
  %a1 = call ptr @A(ptr %h1, ptr %h2)
  %a2 = call ptr @A(ptr %h3, ptr %h4)
  %res = call ptr @A(ptr %a1, ptr %a2)
  br label %done
dispatch:
  %isstr = icmp eq ptr %xt, @type_str
  br i1 %isstr, label %strcase, label %checknum
strcase:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %xvp
  call void @fput_str(ptr %fh, ptr %s)
  br label %scalar
checknum:
  %isnum = icmp eq ptr %xt, @type_num
  br i1 %isnum, label %numcase, label %checkT
numcase:
  %xdp = getelementptr %value, ptr %x, i32 0, i32 3
  %d = load double, ptr %xdp
  call void @fput_double(ptr %fh, double %d)
  br label %scalar
checkT:
  %isT = icmp eq ptr %xt, @type_T
  br i1 %isT, label %checkTnil, label %checkF
checkTnil:
  %xlp2 = getelementptr %value, ptr %x, i32 0, i32 2
  %xl2 = load ptr, ptr %xlp2
  %nil = icmp eq ptr %xl2, null
  br i1 %nil, label %printT, label %checkF
printT:
  call void @fput_ch(ptr %fh, i8 84)
  br label %scalar
checkF:
  %isF = icmp eq ptr %xt, @type_F
  br i1 %isF, label %checkFnil, label %checkbn
checkFnil:
  %xlp3 = getelementptr %value, ptr %x, i32 0, i32 2
  %xl3 = load ptr, ptr %xlp3
  %nil2 = icmp eq ptr %xl3, null
  br i1 %nil2, label %printF, label %checkbn
printF:
  call void @fput_ch(ptr %fh, i8 70)
  br label %scalar
checkbn:
  %isbn = icmp eq ptr %xt, @type_bn
  br i1 %isbn, label %bncase, label %scalar
bncase:
  %xvp2 = getelementptr %value, ptr %x, i32 0, i32 3
  %bn = load ptr, ptr %xvp2
  %s2 = call ptr @bn_to_dec(ptr %bn)
  call void @fput_str(ptr %fh, ptr %s2)
  call void @str_free(ptr %s2)
  br label %scalar
scalar:
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  br label %done
done:
  %r = phi ptr [ %res, %listcase ], [ %hqi, %scalar ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_put(ptr %f) {
entry:
  %out = load ptr, ptr @stdout
  %r = call ptr @op_put(ptr %out, ptr %f)
  ret ptr %r
}

define private ptr @type_nl(ptr %f) {
entry:
  call void @nl()
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define private ptr @type_say(ptr %f) {
entry:
  %p = load ptr, ptr @Qput
  %hp = call ptr @hold(ptr %p)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %hr = call ptr @hold(ptr %rv)
  %n = load ptr, ptr @Qnl
  %hn = call ptr @hold(ptr %n)
  %a1 = call ptr @A(ptr %hp, ptr %hr)
  %r = call ptr @A(ptr %a1, ptr %hn)
  ret ptr %r
}

define private ptr @type_fput(ptr %f) {
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
  %argp = load ptr, ptr %LRp
  %out = call ptr @arg(ptr %argp)
  %otp = getelementptr %value, ptr %out, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isfile = icmp eq ptr %ot, @type_file
  br i1 %isfile, label %yes, label %void
yes:
  %ovp = getelementptr %value, ptr %out, i32 0, i32 3
  %fh = load ptr, ptr %ovp
  %r = call ptr @op_put(ptr %fh, ptr %f)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %rr = phi ptr [ %r, %yes ], [ %h, %void ]
  call void @drop(ptr %out)
  ret ptr %rr
}

define private ptr @type_fnl(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %out = call ptr @arg(ptr %argp)
  %otp = getelementptr %value, ptr %out, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isfile = icmp eq ptr %ot, @type_file
  br i1 %isfile, label %yes, label %void
yes:
  %ovp = getelementptr %value, ptr %out, i32 0, i32 3
  %fh = load ptr, ptr %ovp
  call void @fnl(ptr %fh)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %h, %yes ], [ %h2, %void ]
  call void @drop(ptr %out)
  ret ptr %r
}

define private ptr @type_fsay(ptr %f) {
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
  %fp = load ptr, ptr @Qfput
  %hfp = call ptr @hold(ptr %fp)
  %LLRp = getelementptr %value, ptr %L, i32 0, i32 3
  %fh = load ptr, ptr %LLRp
  %hfh = call ptr @hold(ptr %fh)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %hr = call ptr @hold(ptr %rv)
  %np = load ptr, ptr @Qfnl
  %hnp = call ptr @hold(ptr %np)
  %hnl = call ptr @hold(ptr %fh)
  %a1 = call ptr @A(ptr %hfp, ptr %hfh)
  %a2 = call ptr @A(ptr %a1, ptr %hr)
  %a3 = call ptr @A(ptr %hnp, ptr %hnl)
  %r = call ptr @A(ptr %a2, ptr %a3)
  ret ptr %r
}

define private ptr @type_fflush(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %out = call ptr @arg(ptr %argp)
  %otp = getelementptr %value, ptr %out, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isfile = icmp eq ptr %ot, @type_file
  br i1 %isfile, label %yes, label %void
yes:
  %ovp = getelementptr %value, ptr %out, i32 0, i32 3
  %fh = load ptr, ptr %ovp
  call void @fflush(ptr %fh)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %h, %yes ], [ %h2, %void ]
  call void @drop(ptr %out)
  ret ptr %r
}

define ptr @type_load_output(ptr %f) {
entry:
  %p = load ptr, ptr @Qput
  %hp = call ptr @hold(ptr %p)
  call void @define(ptr @.s_put, ptr %hp)
  %n = load ptr, ptr @Qnl
  %hn = call ptr @hold(ptr %n)
  call void @define(ptr @.s_nl, ptr %hn)
  %q1 = call ptr @Q(ptr @type_say)
  call void @define(ptr @.s_say, ptr %q1)
  %fp = load ptr, ptr @Qfput
  %hfp = call ptr @hold(ptr %fp)
  call void @define(ptr @.s_fput, ptr %hfp)
  %fn = load ptr, ptr @Qfnl
  %hfn = call ptr @hold(ptr %fn)
  call void @define(ptr @.s_fnl, ptr %hfn)
  %q2 = call ptr @Q(ptr @type_fsay)
  call void @define(ptr @.s_fsay, ptr %q2)
  %q3 = call ptr @Q(ptr @type_fflush)
  call void @define(ptr @.s_fflush, ptr %q3)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  ret ptr %hqi
}

define void @beg_output() {
entry:
  %a = call ptr @Q(ptr @type_put)
  store ptr %a, ptr @Qput
  %b = call ptr @Q0(ptr @type_nl)
  store ptr %b, ptr @Qnl
  %c = call ptr @Q(ptr @type_fput)
  store ptr %c, ptr @Qfput
  %d = call ptr @Q(ptr @type_fnl)
  store ptr %d, ptr @Qfnl
  ret void
}

define void @end_output() {
entry:
  %a = load ptr, ptr @Qput
  call void @drop(ptr %a)
  %b = load ptr, ptr @Qnl
  call void @drop(ptr %b)
  %c = load ptr, ptr @Qfput
  call void @drop(ptr %c)
  %d = load ptr, ptr @Qfnl
  call void @drop(ptr %d)
  ret void
}
