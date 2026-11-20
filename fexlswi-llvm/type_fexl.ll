; fexl/type_fexl.ll — introspeccion de valores (antes src/type_fexl.c).

@QI    = external global ptr
@Qvoid = external global ptr

@.s_fexl_type     = private constant [10 x i8] c"fexl_type\00"
@.s_fexl_look     = private constant [10 x i8] c"fexl_look\00"
@.s_fexl_look_quo = private constant [14 x i8] c"fexl_look_quo\00"
@.s_fexl_look_ref = private constant [14 x i8] c"fexl_look_ref\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Qnum(double)
declare ptr  @Qstr(ptr)
declare ptr  @pair(ptr, ptr)
declare ptr  @yield(ptr)
declare ptr  @A(ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare void @define(ptr, ptr)
declare ptr  @str_copy(ptr)
declare ptr  @type_quo(ptr)
declare ptr  @type_ref(ptr)

define private ptr @Qtype(ptr %T) {
entry:
  %n = ptrtoint ptr %T to i64
  %d = sitofp i64 %n to double
  %r = call ptr @Qnum(double %d)
  ret ptr %r
}

define private ptr @type_fexl_type(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %x = load ptr, ptr %rp
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %res = call ptr @Qtype(ptr %t)
  ret ptr %res
}

define private ptr @type_fexl_look(ptr %f) {
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
  br i1 %p2, label %keepf, label %lv3
lv3:
  %LLLLp = getelementptr %value, ptr %LLL, i32 0, i32 2
  %LLLL = load ptr, ptr %LLLLp
  %p3 = icmp eq ptr %LLLL, null
  br i1 %p3, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LLLRp = getelementptr %value, ptr %LLL, i32 0, i32 3
  %x = load ptr, ptr %LLLRp
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ty = call ptr @Qtype(ptr %xt)
  %Rp = getelementptr %value, ptr %f, i32 0, i32 3
  %xlp = getelementptr %value, ptr %x, i32 0, i32 2
  %xl = load ptr, ptr %xlp
  %isatom = icmp eq ptr %xl, null
  br i1 %isatom, label %atom, label %checkdata
atom:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %caseA = load ptr, ptr %LRp
  %hca = call ptr @hold(ptr %caseA)
  %res = call ptr @A(ptr %hca, ptr %ty)
  ret ptr %res
checkdata:
  %xlnp = getelementptr %value, ptr %xl, i32 0, i32 0
  %xln = load i64, ptr %xlnp
  %isdata = icmp eq i64 %xln, 0
  br i1 %isdata, label %data, label %tree
data:
  %caseD = load ptr, ptr %Rp
  %hcd = call ptr @hold(ptr %caseD)
  %res2 = call ptr @A(ptr %hcd, ptr %ty)
  ret ptr %res2
tree:
  %caseT = load ptr, ptr %Rp
  %hct = call ptr @hold(ptr %caseT)
  %a1 = call ptr @A(ptr %hct, ptr %ty)
  %hl = call ptr @hold(ptr %xl)
  %a2 = call ptr @A(ptr %a1, ptr %hl)
  %xrp = getelementptr %value, ptr %x, i32 0, i32 3
  %xr = load ptr, ptr %xrp
  %hr = call ptr @hold(ptr %xr)
  %res3 = call ptr @A(ptr %a2, ptr %hr)
  ret ptr %res3
}

define private ptr @type_fexl_look_quo(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %x = load ptr, ptr %rp
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_quo
  br i1 %is, label %yes, label %void
yes:
  %xrp = getelementptr %value, ptr %x, i32 0, i32 3
  %v = load ptr, ptr %xrp
  %hv = call ptr @hold(ptr %v)
  %res = call ptr @yield(ptr %hv)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  ret ptr %r
}

define private ptr @type_fexl_look_ref(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %x = load ptr, ptr %rp
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_ref
  br i1 %is, label %yes, label %void
yes:
  %xrp = getelementptr %value, ptr %x, i32 0, i32 3
  %inner = load ptr, ptr %xrp
  %ivp = getelementptr %value, ptr %inner, i32 0, i32 3
  %s = load ptr, ptr %ivp
  %cp = call ptr @str_copy(ptr %s)
  %sym = call ptr @Qstr(ptr %cp)
  %inp = getelementptr %value, ptr %inner, i32 0, i32 0
  %line = load i64, ptr %inp
  %d = sitofp i64 %line to double
  %ln = call ptr @Qnum(double %d)
  %res = call ptr @pair(ptr %sym, ptr %ln)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  ret ptr %r
}

define ptr @type_load_fexl(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_fexl_type)
  call void @define(ptr @.s_fexl_type, ptr %q0)
  %q1 = call ptr @Q(ptr @type_fexl_look)
  call void @define(ptr @.s_fexl_look, ptr %q1)
  %q2 = call ptr @Q(ptr @type_fexl_look_quo)
  call void @define(ptr @.s_fexl_look_quo, ptr %q2)
  %q3 = call ptr @Q(ptr @type_fexl_look_ref)
  call void @define(ptr @.s_fexl_look_ref, ptr %q3)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
