; fexl/basic.ll — constantes y combinadores basicos (antes src/basic.c).
; value_types.ll se inyecta por concatenacion en el build.

@QI    = global ptr null
@QT    = global ptr null
@QF    = global ptr null
@Qvoid = global ptr null
@Qnull = global ptr null
@Qonce = global ptr null
@QY    = internal global ptr null

@.s_I         = private constant [2 x i8] c"I\00"
@.s_T         = private constant [2 x i8] c"T\00"
@.s_F         = private constant [2 x i8] c"F\00"
@.s_at        = private constant [2 x i8] c"@\00"
@.s_void      = private constant [5 x i8] c"void\00"
@.s_null      = private constant [5 x i8] c"null\00"
@.s_once      = private constant [5 x i8] c"once\00"
@.s_cons      = private constant [5 x i8] c"cons\00"
@.s_eval      = private constant [5 x i8] c"eval\00"
@.s_yield     = private constant [6 x i8] c"yield\00"
@.s_is_defined= private constant [11 x i8] c"is_defined\00"
@.s_is_undef  = private constant [9 x i8] c"is_undef\00"
@.s_is_void   = private constant [8 x i8] c"is_void\00"
@.s_is_good   = private constant [8 x i8] c"is_good\00"
@.s_is_bool   = private constant [8 x i8] c"is_bool\00"
@.s_is_list   = private constant [8 x i8] c"is_list\00"
@.s_chain     = private constant [3 x i8] c"::\00"

declare ptr  @new_value()
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @A(ptr, ptr)
declare ptr  @Q(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @eval(ptr)
declare ptr  @arg(ptr)
declare ptr  @tail(ptr)
declare void @define(ptr, ptr)

; (I x) = x
define private ptr @type_I(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %r = load ptr, ptr %rp
  %res = call ptr @hold(ptr %r)
  ret ptr %res
}

; (T x y) = x
define ptr @type_T(ptr %f) {
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
  %v = load ptr, ptr %LRp
  %res = call ptr @hold(ptr %v)
  ret ptr %res
}

; (F x y) = y
define ptr @type_F(ptr %f) {
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
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %v = load ptr, ptr %rp
  %res = call ptr @hold(ptr %v)
  ret ptr %res
}

; (Y x) = (x (Y x))
define private ptr @type_Y(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %r = load ptr, ptr %rp
  %hr = call ptr @hold(ptr %r)
  %hf = call ptr @hold(ptr %f)
  %res = call ptr @A(ptr %hr, ptr %hf)
  ret ptr %res
}

; (void x) = void
define ptr @type_void(ptr %f) {
entry:
  %v = load ptr, ptr @Qvoid
  %res = call ptr @hold(ptr %v)
  ret ptr %res
}

; ((pair x y) h) = (h x y)
define ptr @type_pair(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %x = load ptr, ptr %LLp
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %y = load ptr, ptr %LRp
  %Rp = getelementptr %value, ptr %f, i32 0, i32 3
  %h = load ptr, ptr %Rp
  %hx = call ptr @hold(ptr %x)
  %hy = call ptr @hold(ptr %y)
  %hh = call ptr @hold(ptr %h)
  %a1 = call ptr @A(ptr %hh, ptr %hx)
  %res = call ptr @A(ptr %a1, ptr %hy)
  ret ptr %res
}

define ptr @pair(ptr %x, ptr %y) {
entry:
  %r = call ptr @V(ptr @type_pair, ptr %x, ptr %y)
  ret ptr %r
}

; ((list x y) h) = (pair x y)
define ptr @type_list(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %x = load ptr, ptr %LLp
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %y = load ptr, ptr %LRp
  %hx = call ptr @hold(ptr %x)
  %hy = call ptr @hold(ptr %y)
  %res = call ptr @pair(ptr %hx, ptr %hy)
  ret ptr %res
}

define ptr @cons(ptr %x, ptr %y) {
entry:
  %r = call ptr @V(ptr @type_list, ptr %x, ptr %y)
  ret ptr %r
}

define private ptr @type_cons(ptr %f) {
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
  %x = load ptr, ptr %LRp
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %y = load ptr, ptr %rp
  %hx = call ptr @hold(ptr %x)
  %hy = call ptr @hold(ptr %y)
  %res = call ptr @cons(ptr %hx, ptr %hy)
  ret ptr %res
}

; (null x y) = x
define ptr @type_null(ptr %f) {
entry:
  %tp = getelementptr %value, ptr %f, i32 0, i32 1
  store ptr @type_T, ptr %tp
  %res = call ptr @hold(ptr %f)
  ret ptr %res
}

; (eval x f) = (f y)
define private ptr @type_eval(ptr %f) {
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
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %r = load ptr, ptr %rp
  %hr = call ptr @hold(ptr %r)
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %lx = load ptr, ptr %LRp
  %x = call ptr @arg(ptr %lx)
  %res = call ptr @A(ptr %hr, ptr %x)
  ret ptr %res
}

define private ptr @type_once(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %r = load ptr, ptr %rp
  %v = call ptr @eval(ptr %r)
  store ptr %v, ptr %rp
  %res = call ptr @hold(ptr %v)
  ret ptr %res
}

; (yield x f) = (f x)
define private ptr @type_yield(ptr %f) {
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
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %r = load ptr, ptr %rp
  %hr = call ptr @hold(ptr %r)
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %lx = load ptr, ptr %LRp
  %hx = call ptr @hold(ptr %lx)
  %res = call ptr @A(ptr %hr, ptr %hx)
  ret ptr %res
}

define ptr @yield(ptr %x) {
entry:
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  %r = call ptr @V(ptr @type_yield, ptr %hqi, ptr %x)
  ret ptr %r
}

define ptr @maybe(ptr %x) {
entry:
  %isnull = icmp eq ptr %x, null
  br i1 %isnull, label %yes, label %no
yes:
  %qt = load ptr, ptr @QT
  %hqt = call ptr @hold(ptr %qt)
  ret ptr %hqt
no:
  %qt2 = load ptr, ptr @QT
  %hqt2 = call ptr @hold(ptr %qt2)
  %hy = call ptr @yield(ptr %x)
  %r = call ptr @V(ptr @type_T, ptr %hqt2, ptr %hy)
  ret ptr %r
}

define ptr @boolean(i32 %x) {
entry:
  %true = icmp ne i32 %x, 0
  %q = select i1 %true, ptr @QT, ptr @QF
  %v = load ptr, ptr %q
  %res = call ptr @hold(ptr %v)
  ret ptr %res
}

define ptr @op_is_type(ptr %f, ptr %t) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %tp
  %same = icmp eq ptr %xt, %t
  %ci = zext i1 %same to i32
  %res = call ptr @boolean(i32 %ci)
  call void @drop(ptr %x)
  ret ptr %res
}

define private i32 @is_good(ptr %x) {
entry:
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isvoid = icmp eq ptr %t, @type_void
  %r = select i1 %isvoid, i32 0, i32 1
  ret i32 %r
}

define private i32 @is_bool(ptr %x) {
entry:
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %ist = icmp eq ptr %t, @type_T
  %isf = icmp eq ptr %t, @type_F
  %tf = or i1 %ist, %isf
  %lp = getelementptr %value, ptr %x, i32 0, i32 2
  %l = load ptr, ptr %lp
  %nl = icmp eq ptr %l, null
  %ok = and i1 %tf, %nl
  %r = zext i1 %ok to i32
  ret i32 %r
}

define private i32 @is_list(ptr %x) {
entry:
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isl = icmp eq ptr %t, @type_list
  %isn = icmp eq ptr %t, @type_null
  %ok = or i1 %isl, %isn
  %r = zext i1 %ok to i32
  ret i32 %r
}

define private ptr @op_predicate(ptr %f, ptr %op) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %c = call i32 %op(ptr %x)
  %res = call ptr @boolean(i32 %c)
  call void @drop(ptr %x)
  ret ptr %res
}

define private ptr @type_is_defined(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isvoid = icmp ne ptr %t, @type_void
  %ci = zext i1 %isvoid to i32
  %res = call ptr @boolean(i32 %ci)
  call void @drop(ptr %x)
  ret ptr %res
}

define private ptr @type_is_undef(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isvoid = icmp eq ptr %t, @type_void
  %ci = zext i1 %isvoid to i32
  %res = call ptr @boolean(i32 %ci)
  call void @drop(ptr %x)
  ret ptr %res
}

define private ptr @type_is_void(ptr %f) {
entry:
  %r = call ptr @op_is_type(ptr %f, ptr @type_void)
  ret ptr %r
}

define private ptr @type_is_good(ptr %f) {
entry:
  %r = call ptr @op_predicate(ptr %f, ptr @is_good)
  ret ptr %r
}
define private ptr @type_is_bool(ptr %f) {
entry:
  %r = call ptr @op_predicate(ptr %f, ptr @is_bool)
  ret ptr %r
}
define private ptr @type_is_list(ptr %f) {
entry:
  %r = call ptr @op_predicate(ptr %f, ptr @is_list)
  ret ptr %r
}

; (:: a b) x — prueba a, si es void prueba b
define private ptr @type_chain(ptr %f) {
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
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %LLRp = getelementptr %value, ptr %LL, i32 0, i32 3
  %a = call ptr @eval(ptr %LLRp)
  store ptr %a, ptr %LLRp
  %ha = call ptr @hold(ptr %a)
  %app = call ptr @A(ptr %ha, ptr %x)
  %v = call ptr @eval(ptr %app)
  %vtp = getelementptr %value, ptr %v, i32 0, i32 1
  %vt = load ptr, ptr %vtp
  %isvoid = icmp eq ptr %vt, @type_void
  br i1 %isvoid, label %fallback, label %found
found:
  ret ptr %v
fallback:
  call void @drop(ptr %v)
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %b = call ptr @eval(ptr %LRp)
  store ptr %b, ptr %LRp
  %hb = call ptr @hold(ptr %b)
  %hx = call ptr @hold(ptr %x)
  %res = call ptr @A(ptr %hb, ptr %hx)
  ret ptr %res
}

define ptr @Q0(ptr %T) {
entry:
  %q = call ptr @Q(ptr %T)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  %r = call ptr @A(ptr %q, ptr %hqi)
  ret ptr %r
}

define ptr @type_load_basic(ptr %f) {
entry:
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  call void @define(ptr @.s_I, ptr %hqi)
  %qt = load ptr, ptr @QT
  %hqt = call ptr @hold(ptr %qt)
  call void @define(ptr @.s_T, ptr %hqt)
  %qf = load ptr, ptr @QF
  %hqf = call ptr @hold(ptr %qf)
  call void @define(ptr @.s_F, ptr %hqf)
  %qy = load ptr, ptr @QY
  %hqy = call ptr @hold(ptr %qy)
  call void @define(ptr @.s_at, ptr %hqy)
  %qv = load ptr, ptr @Qvoid
  %hqv = call ptr @hold(ptr %qv)
  call void @define(ptr @.s_void, ptr %hqv)
  %qn = load ptr, ptr @Qnull
  %hqn = call ptr @hold(ptr %qn)
  call void @define(ptr @.s_null, ptr %hqn)
  %qo = load ptr, ptr @Qonce
  %hqo = call ptr @hold(ptr %qo)
  call void @define(ptr @.s_once, ptr %hqo)
  %q1 = call ptr @Q(ptr @type_cons)
  call void @define(ptr @.s_cons, ptr %q1)
  %q2 = call ptr @Q(ptr @type_eval)
  call void @define(ptr @.s_eval, ptr %q2)
  %q3 = call ptr @Q(ptr @type_yield)
  call void @define(ptr @.s_yield, ptr %q3)
  %q4 = call ptr @Q(ptr @type_is_defined)
  call void @define(ptr @.s_is_defined, ptr %q4)
  %q5 = call ptr @Q(ptr @type_is_undef)
  call void @define(ptr @.s_is_undef, ptr %q5)
  %q6 = call ptr @Q(ptr @type_is_void)
  call void @define(ptr @.s_is_void, ptr %q6)
  %q7 = call ptr @Q(ptr @type_is_good)
  call void @define(ptr @.s_is_good, ptr %q7)
  %q8 = call ptr @Q(ptr @type_is_bool)
  call void @define(ptr @.s_is_bool, ptr %q8)
  %q9 = call ptr @Q(ptr @type_is_list)
  call void @define(ptr @.s_is_list, ptr %q9)
  %q10 = call ptr @Q(ptr @type_chain)
  call void @define(ptr @.s_chain, ptr %q10)
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define void @beg_basic() {
entry:
  %a = call ptr @Q(ptr @type_I)
  store ptr %a, ptr @QI
  %b = call ptr @Q(ptr @type_T)
  store ptr %b, ptr @QT
  %c = call ptr @Q(ptr @type_F)
  store ptr %c, ptr @QF
  %d = call ptr @Q(ptr @type_Y)
  store ptr %d, ptr @QY
  %e = call ptr @Q(ptr @type_void)
  store ptr %e, ptr @Qvoid
  %g = call ptr @Q(ptr @type_null)
  store ptr %g, ptr @Qnull
  %h = call ptr @Q(ptr @type_once)
  store ptr %h, ptr @Qonce
  ret void
}

define void @end_basic() {
entry:
  %a = load ptr, ptr @QI
  call void @drop(ptr %a)
  %b = load ptr, ptr @QT
  call void @drop(ptr %b)
  %c = load ptr, ptr @QF
  call void @drop(ptr %c)
  %d = load ptr, ptr @QY
  call void @drop(ptr %d)
  %e = load ptr, ptr @Qvoid
  call void @drop(ptr %e)
  %g = load ptr, ptr @Qnull
  call void @drop(ptr %g)
  %h = load ptr, ptr @Qonce
  call void @drop(ptr %h)
  ret void
}
