; fexl/type_record.ll — registros con clave ordenada (antes type_record.c).
; value_types.ll se inyecta por concatenacion en el build.

%Item   = type { ptr, ptr }
%Record = type { i64, i64, ptr }
%Search = type { i64, ptr, i32 }

@QI    = external global ptr
@Qvoid = external global ptr

@.s_empty        = private constant [6 x i8] c"empty\00"
@.s_set          = private constant [4 x i8] c"set\00"
@.s_setf         = private constant [5 x i8] c"setf\00"
@.s_del          = private constant [4 x i8] c"del\00"
@.s_get          = private constant [4 x i8] c"get\00"
@.s_record_copy  = private constant [12 x i8] c"record_copy\00"
@.s_record_count = private constant [13 x i8] c"record_count\00"
@.s_record_item  = private constant [12 x i8] c"record_item\00"
@.s_fetch        = private constant [6 x i8] c"fetch\00"
@.s_record_fill  = private constant [12 x i8] c"record_fill\00"
@.s_rmod         = private constant [5 x i8] c"rmod\00"

declare ptr  @new_value()
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @A(ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @arg(ptr)
declare ptr  @eval(ptr)
declare ptr  @pair(ptr, ptr)
declare ptr  @maybe(ptr)
declare void @define(ptr, ptr)
declare ptr  @new_memory(i64)
declare void @free_memory(ptr, i64)
declare i32  @str_cmp(ptr, ptr)
declare i32  @num_cmp(double, double)
declare ptr  @Qnum(double)
declare i64  @get_ulong(ptr)
declare ptr  @type_str(ptr)
declare ptr  @type_num(ptr)
declare ptr  @type_list(ptr)

define private void @clear_record(ptr %f) {
entry:
  %vp = getelementptr %value, ptr %f, i32 0, i32 3
  %rec = load ptr, ptr %vp
  %countp = getelementptr %Record, ptr %rec, i32 0, i32 0
  %count = load i64, ptr %countp
  %vecp = getelementptr %Record, ptr %rec, i32 0, i32 2
  %vec = load ptr, ptr %vecp
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %cont = icmp ult i64 %i, %count
  br i1 %cont, label %body, label %finish
body:
  %item = getelementptr %Item, ptr %vec, i64 %i
  %kp = getelementptr %Item, ptr %item, i32 0, i32 0
  %k = load ptr, ptr %kp
  %vp2 = getelementptr %Item, ptr %item, i32 0, i32 1
  %v = load ptr, ptr %vp2
  call void @drop(ptr %k)
  call void @drop(ptr %v)
  %i1 = add i64 %i, 1
  br label %loop
finish:
  %sizep = getelementptr %Record, ptr %rec, i32 0, i32 1
  %size = load i64, ptr %sizep
  %bytes = shl i64 %size, 4
  call void @free_memory(ptr %vec, i64 %bytes)
  call void @free_memory(ptr %rec, i64 24)
  ret void
}
@clear_record_sentinel = private constant %value { i64 0, ptr @clear_record, ptr null, ptr null }

define private ptr @Qrecord(ptr %rec) {
entry:
  %r = call ptr @V(ptr @type_record, ptr @clear_record_sentinel, ptr %rec)
  ret ptr %r
}

define private i64 @calc_size(i64 %count) {
entry:
  %extra = lshr i64 %count, 1
  %lt5 = icmp ult i64 %extra, 5
  %e = select i1 %lt5, i64 5, i64 %extra
  %n = add i64 %count, %e
  ret i64 %n
}

define private ptr @new_record(i64 %count, i64 %size) {
entry:
  %rec = call ptr @new_memory(i64 24)
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  store i64 %count, ptr %cp
  %sp = getelementptr %Record, ptr %rec, i32 0, i32 1
  store i64 %size, ptr %sp
  %bytes = shl i64 %size, 4
  %vec = call ptr @new_memory(i64 %bytes)
  %vp = getelementptr %Record, ptr %rec, i32 0, i32 2
  store ptr %vec, ptr %vp
  ret ptr %rec
}

define private i32 @key_cmp(ptr %x, ptr %y) {
entry:
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xs = icmp eq ptr %xt, @type_str
  br i1 %xs, label %xstr, label %xnum
xstr:
  %ys = icmp eq ptr %yt, @type_str
  br i1 %ys, label %bothstr, label %ret1
bothstr:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %c = call i32 @str_cmp(ptr %xv, ptr %yv)
  ret i32 %c
xnum:
  %yn = icmp eq ptr %yt, @type_num
  br i1 %yn, label %bothnum, label %retm1
bothnum:
  %xdp = getelementptr %value, ptr %x, i32 0, i32 3
  %xd = load double, ptr %xdp
  %ydp = getelementptr %value, ptr %y, i32 0, i32 3
  %yd = load double, ptr %ydp
  %c2 = call i32 @num_cmp(double %xd, double %yd)
  ret i32 %c2
ret1:
  ret i32 1
retm1:
  ret i32 -1
}

; Se usa en record_find/record_set: computa (pos, item, cmp).
define private %Search @find_key2(ptr %rec, ptr %key) {
entry:
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  %count = load i64, ptr %cp
  %vp = getelementptr %Record, ptr %rec, i32 0, i32 2
  %vec = load ptr, ptr %vp
  br label %loop
loop:
  %lo = phi i64 [ 0, %entry ], [ %lo1, %gtbranch ], [ %lo, %ltbranch ]
  %hi = phi i64 [ %count, %entry ], [ %hi, %gtbranch ], [ %i, %ltbranch ]
  %pos = phi i64 [ %count, %entry ], [ %pos, %gtbranch ], [ %i, %ltbranch ]
  %item = phi ptr [ null, %entry ], [ %it, %gtbranch ], [ %it, %ltbranch ]
  %cmp = phi i32 [ 1, %entry ], [ %c, %gtbranch ], [ %c, %ltbranch ]
  %go = icmp ult i64 %lo, %hi
  br i1 %go, label %body, label %done
body:
  %span = sub i64 %hi, %lo
  %half = lshr i64 %span, 1
  %i = add i64 %lo, %half
  %it = getelementptr %Item, ptr %vec, i64 %i
  %kp = getelementptr %Item, ptr %it, i32 0, i32 0
  %k = load ptr, ptr %kp
  %c = call i32 @key_cmp(ptr %key, ptr %k)
  %gt = icmp sgt i32 %c, 0
  br i1 %gt, label %gtbranch, label %checklt
gtbranch:
  %lo1 = add i64 %i, 1
  br label %loop
checklt:
  %lt = icmp slt i32 %c, 0
  br i1 %lt, label %ltbranch, label %found
ltbranch:
  br label %loop
found:
  %s = insertvalue %Search undef, i64 %i, 0
  %s2 = insertvalue %Search %s, ptr %it, 1
  %s3 = insertvalue %Search %s2, i32 %c, 2
  ret %Search %s3
done:
  %r = insertvalue %Search undef, i64 %pos, 0
  %r2 = insertvalue %Search %r, ptr %item, 1
  %r3 = insertvalue %Search %r2, i32 %cmp, 2
  ret %Search %r3
}

define ptr @record_find(ptr %obj, ptr %key) {
entry:
  %vp = getelementptr %value, ptr %obj, i32 0, i32 3
  %rec = load ptr, ptr %vp
  %s = call %Search @find_key2(ptr %rec, ptr %key)
  %cmp = extractvalue %Search %s, 2
  %zero = icmp eq i32 %cmp, 0
  br i1 %zero, label %yes, label %no
yes:
  %item = extractvalue %Search %s, 1
  %vp2 = getelementptr %Item, ptr %item, i32 0, i32 1
  %v = load ptr, ptr %vp2
  ret ptr %v
no:
  ret ptr null
}

define ptr @type_record(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %key = call ptr @arg(ptr %rv)
  %ktp = getelementptr %value, ptr %key, i32 0, i32 1
  %kt = load ptr, ptr %ktp
  %ks = icmp eq ptr %kt, @type_str
  %kn = icmp eq ptr %kt, @type_num
  %ok = or i1 %ks, %kn
  br i1 %ok, label %yes, label %void
yes:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %obj = load ptr, ptr %Lp
  %val = call ptr @record_find(ptr %obj, ptr %key)
  %none = icmp eq ptr %val, null
  br i1 %none, label %usevoid, label %found
usevoid:
  %qv = load ptr, ptr @Qvoid
  br label %found
found:
  %v = phi ptr [ %val, %yes ], [ %qv, %usevoid ]
  %r = call ptr @hold(ptr %v)
  br label %done
void:
  %qv2 = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv2)
  br label %done
done:
  %res = phi ptr [ %r, %found ], [ %h, %void ]
  call void @drop(ptr %key)
  ret ptr %res
}

define private void @bump(ptr %rec) {
entry:
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  %count = load i64, ptr %cp
  %n1 = add i64 %count, 1
  %size = call i64 @calc_size(i64 %n1)
  %bytes = shl i64 %size, 4
  %newvec = call ptr @new_memory(i64 %bytes)
  %vp = getelementptr %Record, ptr %rec, i32 0, i32 2
  %oldvec = load ptr, ptr %vp
  %sizep = getelementptr %Record, ptr %rec, i32 0, i32 1
  %oldsize = load i64, ptr %sizep
  %oldbytes = shl i64 %oldsize, 4
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %cont = icmp ult i64 %i, %count
  br i1 %cont, label %body, label %finish
body:
  %srcp = getelementptr %Item, ptr %oldvec, i64 %i
  %dstp = getelementptr %Item, ptr %newvec, i64 %i
  %item = load %Item, ptr %srcp
  store %Item %item, ptr %dstp
  %i1 = add i64 %i, 1
  br label %loop
finish:
  call void @free_memory(ptr %oldvec, i64 %oldbytes)
  store i64 %size, ptr %sizep
  store ptr %newvec, ptr %vp
  ret void
}

define private ptr @insert(ptr %rec, i64 %pos) {
entry:
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  %count = load i64, ptr %cp
  %sizep = getelementptr %Record, ptr %rec, i32 0, i32 1
  %size = load i64, ptr %sizep
  %full = icmp uge i64 %count, %size
  br i1 %full, label %dobump, label %shift
dobump:
  call void @bump(ptr %rec)
  br label %shift
shift:
  %vp = getelementptr %Record, ptr %rec, i32 0, i32 2
  %vec = load ptr, ptr %vp
  br label %sloop
sloop:
  %i = phi i64 [ %count, %shift ], [ %i1, %sbody ]
  %go = icmp ugt i64 %i, %pos
  br i1 %go, label %sbody, label %finish
sbody:
  %src = getelementptr %Item, ptr %vec, i64 %i
  %im1 = sub i64 %i, 1
  %srcm1 = getelementptr %Item, ptr %vec, i64 %im1
  %item = load %Item, ptr %srcm1
  store %Item %item, ptr %src
  %i1 = sub i64 %i, 1
  br label %sloop
finish:
  %c1 = add i64 %count, 1
  store i64 %c1, ptr %cp
  %slot = getelementptr %Item, ptr %vec, i64 %pos
  ret ptr %slot
}

define void @record_set(ptr %obj, ptr %key, ptr %val) {
entry:
  %vp = getelementptr %value, ptr %obj, i32 0, i32 3
  %rec = load ptr, ptr %vp
  %s = call %Search @find_key2(ptr %rec, ptr %key)
  %cmp = extractvalue %Search %s, 2
  %found = icmp eq i32 %cmp, 0
  br i1 %found, label %existing, label %new
existing:
  %item = extractvalue %Search %s, 1
  %vp2 = getelementptr %Item, ptr %item, i32 0, i32 1
  %old = load ptr, ptr %vp2
  call void @drop(ptr %old)
  br label %setval
new:
  %pos = extractvalue %Search %s, 0
  %it = call ptr @insert(ptr %rec, i64 %pos)
  %hk = call ptr @hold(ptr %key)
  %kp = getelementptr %Item, ptr %it, i32 0, i32 0
  store ptr %hk, ptr %kp
  br label %setval
setval:
  %dst = phi ptr [ %item, %existing ], [ %it, %new ]
  %valp = getelementptr %Item, ptr %dst, i32 0, i32 1
  store ptr %val, ptr %valp
  ret void
}

define ptr @record_empty() {
entry:
  %size = call i64 @calc_size(i64 0)
  %rec = call ptr @new_record(i64 0, i64 %size)
  %r = call ptr @Qrecord(ptr %rec)
  ret ptr %r
}

define private void @shift_down(ptr %vec, i64 %n, i64 %pos) {
entry:
  br label %loop
loop:
  %i = phi i64 [ %pos, %entry ], [ %i1, %body ]
  %go = icmp ult i64 %i, %n
  br i1 %go, label %body, label %done
body:
  %ip1 = add i64 %i, 1
  %src = getelementptr %Item, ptr %vec, i64 %i
  %src1 = getelementptr %Item, ptr %vec, i64 %ip1
  %item = load %Item, ptr %src1
  store %Item %item, ptr %src
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

define private void @record_del(ptr %obj, ptr %key) {
entry:
  %vp = getelementptr %value, ptr %obj, i32 0, i32 3
  %rec = load ptr, ptr %vp
  %s = call %Search @find_key2(ptr %rec, ptr %key)
  %cmp = extractvalue %Search %s, 2
  %found = icmp eq i32 %cmp, 0
  br i1 %found, label %body, label %done
body:
  %pos = extractvalue %Search %s, 0
  %item = extractvalue %Search %s, 1
  %kp = getelementptr %Item, ptr %item, i32 0, i32 0
  %k = load ptr, ptr %kp
  %vp2 = getelementptr %Item, ptr %item, i32 0, i32 1
  %v = load ptr, ptr %vp2
  call void @drop(ptr %k)
  call void @drop(ptr %v)
  %sizep = getelementptr %Record, ptr %rec, i32 0, i32 1
  %size = load i64, ptr %sizep
  %vecp = getelementptr %Record, ptr %rec, i32 0, i32 2
  %vec = load ptr, ptr %vecp
  call void @shift_down(ptr %vec, i64 %size, i64 %pos)
  %c1 = sub i64 %size, 1
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  store i64 %c1, ptr %cp
  ret void
done:
  ret void
}

define ptr @record_copy(ptr %obj) {
entry:
  %vp = getelementptr %value, ptr %obj, i32 0, i32 3
  %old = load ptr, ptr %vp
  %cp = getelementptr %Record, ptr %old, i32 0, i32 0
  %count = load i64, ptr %cp
  %sp = getelementptr %Record, ptr %old, i32 0, i32 1
  %size = load i64, ptr %sp
  %new = call ptr @new_record(i64 %count, i64 %size)
  %ovp = getelementptr %Record, ptr %old, i32 0, i32 2
  %ovec = load ptr, ptr %ovp
  %nvp = getelementptr %Record, ptr %new, i32 0, i32 2
  %nvec = load ptr, ptr %nvp
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %cont = icmp ult i64 %i, %count
  br i1 %cont, label %body, label %finish
body:
  %oi = getelementptr %Item, ptr %ovec, i64 %i
  %ni = getelementptr %Item, ptr %nvec, i64 %i
  %okp = getelementptr %Item, ptr %oi, i32 0, i32 0
  %ok = load ptr, ptr %okp
  %ovp2 = getelementptr %Item, ptr %oi, i32 0, i32 1
  %ov = load ptr, ptr %ovp2
  %hk = call ptr @hold(ptr %ok)
  %hv = call ptr @hold(ptr %ov)
  %nkp = getelementptr %Item, ptr %ni, i32 0, i32 0
  %nvp2 = getelementptr %Item, ptr %ni, i32 0, i32 1
  store ptr %hk, ptr %nkp
  store ptr %hv, ptr %nvp2
  %i1 = add i64 %i, 1
  br label %loop
finish:
  %r = call ptr @Qrecord(ptr %new)
  ret ptr %r
}

define private ptr @type_empty(ptr %f) {
entry:
  %r = call ptr @record_empty()
  ret ptr %r
}

define private ptr @op_set(ptr %f, ptr %op) {
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
  %objarg = load ptr, ptr %LLRp
  %obj = call ptr @arg(ptr %objarg)
  %otp = getelementptr %value, ptr %obj, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isrec = icmp eq ptr %ot, @type_record
  br i1 %isrec, label %inrec, label %void
inrec:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %keyarg = load ptr, ptr %LRp
  %key = call ptr @arg(ptr %keyarg)
  %ktp = getelementptr %value, ptr %key, i32 0, i32 1
  %kt = load ptr, ptr %ktp
  %ks = icmp eq ptr %kt, @type_str
  %kn = icmp eq ptr %kt, @type_num
  %kok = or i1 %ks, %kn
  br i1 %kok, label %setit, label %voidkey
setit:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %valarg = load ptr, ptr %rp
  %val = call ptr %op(ptr %valarg)
  call void @record_set(ptr %obj, ptr %key, ptr %val)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  br label %donekey
voidkey:
  %qv = load ptr, ptr @Qvoid
  %hqv = call ptr @hold(ptr %qv)
  br label %donekey
donekey:
  %rk = phi ptr [ %hqi, %setit ], [ %hqv, %voidkey ]
  call void @drop(ptr %key)
  br label %done
void:
  %qv2 = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv2)
  br label %done
done:
  %res = phi ptr [ %rk, %donekey ], [ %h2, %void ]
  call void @drop(ptr %obj)
  ret ptr %res
}

define private ptr @type_set(ptr %f) {
entry:
  %r = call ptr @op_set(ptr %f, ptr @arg)
  ret ptr %r
}
define private ptr @type_setf(ptr %f) {
entry:
  %r = call ptr @op_set(ptr %f, ptr @hold)
  ret ptr %r
}

define private ptr @type_del(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %p1 = icmp eq ptr %LL, null
  br i1 %p1, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %objarg = load ptr, ptr %LRp
  %obj = call ptr @arg(ptr %objarg)
  %otp = getelementptr %value, ptr %obj, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isrec = icmp eq ptr %ot, @type_record
  br i1 %isrec, label %inrec, label %void
inrec:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %keyarg = load ptr, ptr %rp
  %key = call ptr @arg(ptr %keyarg)
  %ktp = getelementptr %value, ptr %key, i32 0, i32 1
  %kt = load ptr, ptr %ktp
  %ks = icmp eq ptr %kt, @type_str
  %kn = icmp eq ptr %kt, @type_num
  %kok = or i1 %ks, %kn
  br i1 %kok, label %delit, label %voidkey
delit:
  call void @record_del(ptr %obj, ptr %key)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  br label %donekey
voidkey:
  %qv = load ptr, ptr @Qvoid
  %hqv = call ptr @hold(ptr %qv)
  br label %donekey
donekey:
  %rk = phi ptr [ %hqi, %delit ], [ %hqv, %voidkey ]
  call void @drop(ptr %key)
  br label %done
void:
  %qv2 = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv2)
  br label %done
done:
  %res = phi ptr [ %rk, %donekey ], [ %h2, %void ]
  call void @drop(ptr %obj)
  ret ptr %res
}

define private ptr @type_get(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %p1 = icmp eq ptr %LL, null
  br i1 %p1, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %objarg = load ptr, ptr %LRp
  %obj = call ptr @arg(ptr %objarg)
  %otp = getelementptr %value, ptr %obj, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isrec = icmp eq ptr %ot, @type_record
  br i1 %isrec, label %inrec, label %void
inrec:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %keyarg = load ptr, ptr %rp
  %key = call ptr @arg(ptr %keyarg)
  %ktp = getelementptr %value, ptr %key, i32 0, i32 1
  %kt = load ptr, ptr %ktp
  %ks = icmp eq ptr %kt, @type_str
  %kn = icmp eq ptr %kt, @type_num
  %kok = or i1 %ks, %kn
  br i1 %kok, label %getit, label %voidkey
getit:
  %val = call ptr @record_find(ptr %obj, ptr %key)
  %res = call ptr @maybe(ptr %val)
  br label %donekey
voidkey:
  %qv = load ptr, ptr @Qvoid
  %hqv = call ptr @hold(ptr %qv)
  br label %donekey
donekey:
  %rk = phi ptr [ %res, %getit ], [ %hqv, %voidkey ]
  call void @drop(ptr %key)
  br label %done
void:
  %qv2 = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv2)
  br label %done
done:
  %r = phi ptr [ %rk, %donekey ], [ %h2, %void ]
  call void @drop(ptr %obj)
  ret ptr %r
}

define private ptr @type_record_copy(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %obj = call ptr @arg(ptr %argp)
  %otp = getelementptr %value, ptr %obj, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %is = icmp eq ptr %ot, @type_record
  br i1 %is, label %yes, label %void
yes:
  %r = call ptr @record_copy(ptr %obj)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %res = phi ptr [ %r, %yes ], [ %h, %void ]
  call void @drop(ptr %obj)
  ret ptr %res
}

define private ptr @type_record_count(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %obj = call ptr @arg(ptr %argp)
  %otp = getelementptr %value, ptr %obj, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %is = icmp eq ptr %ot, @type_record
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %obj, i32 0, i32 3
  %rec = load ptr, ptr %vp
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  %n = load i64, ptr %cp
  %d = sitofp i64 %n to double
  %q = call ptr @Qnum(double %d)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %res = phi ptr [ %q, %yes ], [ %h, %void ]
  call void @drop(ptr %obj)
  ret ptr %res
}

define private ptr @type_record_item(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %p1 = icmp eq ptr %LL, null
  br i1 %p1, label %keepf, label %body
keepf:
  %kf = call ptr @keep(ptr %f)
  ret ptr %kf
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %objarg = load ptr, ptr %LRp
  %obj = call ptr @arg(ptr %objarg)
  %otp = getelementptr %value, ptr %obj, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isrec = icmp eq ptr %ot, @type_record
  br i1 %isrec, label %inrec, label %void
inrec:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %posarg = load ptr, ptr %rp
  %vpos = call ptr @arg(ptr %posarg)
  %ptp = getelementptr %value, ptr %vpos, i32 0, i32 1
  %pt = load ptr, ptr %ptp
  %isnum = icmp eq ptr %pt, @type_num
  br i1 %isnum, label %getitem, label %voidpos
getitem:
  %vp = getelementptr %value, ptr %obj, i32 0, i32 3
  %rec = load ptr, ptr %vp
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  %count = load i64, ptr %cp
  %pos = call i64 @get_ulong(ptr %vpos)
  %in = icmp ult i64 %pos, %count
  br i1 %in, label %yes, label %voidpos
yes:
  %vecp = getelementptr %Record, ptr %rec, i32 0, i32 2
  %vec = load ptr, ptr %vecp
  %item = getelementptr %Item, ptr %vec, i64 %pos
  %kp = getelementptr %Item, ptr %item, i32 0, i32 0
  %k = load ptr, ptr %kp
  %vp2 = getelementptr %Item, ptr %item, i32 0, i32 1
  %v = load ptr, ptr %vp2
  %hk = call ptr @hold(ptr %k)
  %hv = call ptr @hold(ptr %v)
  %res = call ptr @pair(ptr %hk, ptr %hv)
  br label %donepos
voidpos:
  %qv = load ptr, ptr @Qvoid
  %hqv = call ptr @hold(ptr %qv)
  br label %donepos
donepos:
  %rr = phi ptr [ %res, %yes ], [ %hqv, %voidpos ]
  call void @drop(ptr %vpos)
  br label %done
void:
  %qv2 = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv2)
  br label %done
done:
  %r = phi ptr [ %rr, %donepos ], [ %h2, %void ]
  call void @drop(ptr %obj)
  ret ptr %r
}

define private ptr @type_fetch(ptr %f) {
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
  %varg = load ptr, ptr %LLRp
  %v = call ptr @arg(ptr %varg)
  %vtp = getelementptr %value, ptr %v, i32 0, i32 1
  %vt = load ptr, ptr %vtp
  %isrec = icmp eq ptr %vt, @type_record
  br i1 %isrec, label %inrec, label %void
inrec:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %karg = load ptr, ptr %LRp
  %key = call ptr @arg(ptr %karg)
  %y = call ptr @record_find(ptr %v, ptr %key)
  %found = icmp ne ptr %y, null
  br i1 %found, label %yes, label %no
yes:
  %hy = call ptr @hold(ptr %y)
  br label %donekey
no:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %xarg = load ptr, ptr %rp
  %fx = call ptr @arg(ptr %xarg)
  %hv = call ptr @hold(ptr %fx)
  call void @record_set(ptr %v, ptr %key, ptr %hv)
  br label %donekey
donekey:
  %rk = phi ptr [ %hy, %yes ], [ %fx, %no ]
  call void @drop(ptr %key)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %res = phi ptr [ %rk, %donekey ], [ %h, %void ]
  call void @drop(ptr %v)
  ret ptr %res
}

define void @record_fill(ptr %obj, ptr %list) {
entry:
  br label %loop
loop:
  %cur = phi ptr [ %list, %entry ], [ %tail, %endhead ]
  %tp = getelementptr %value, ptr %cur, i32 0, i32 1
  %t = load ptr, ptr %tp
  %islist = icmp eq ptr %t, @type_list
  br i1 %islist, label %body, label %done
body:
  %lp = getelementptr %value, ptr %cur, i32 0, i32 2
  %headarg = load ptr, ptr %lp
  %head = call ptr @arg(ptr %headarg)
  %rp = getelementptr %value, ptr %cur, i32 0, i32 3
  %tailarg = load ptr, ptr %rp
  %tail = call ptr @arg(ptr %tailarg)
  %htp = getelementptr %value, ptr %head, i32 0, i32 1
  %ht = load ptr, ptr %htp
  %hl = icmp eq ptr %ht, @type_list
  br i1 %hl, label %inhead, label %endhead
inhead:
  %hlp = getelementptr %value, ptr %head, i32 0, i32 2
  %keyarg = load ptr, ptr %hlp
  %key = call ptr @arg(ptr %keyarg)
  %ktp = getelementptr %value, ptr %key, i32 0, i32 1
  %kt = load ptr, ptr %ktp
  %ks = icmp eq ptr %kt, @type_str
  %kn = icmp eq ptr %kt, @type_num
  %kok = or i1 %ks, %kn
  br i1 %kok, label %inkey, label %endkey
inkey:
  %hrp = getelementptr %value, ptr %head, i32 0, i32 3
  %argsarg = load ptr, ptr %hrp
  %args = call ptr @arg(ptr %argsarg)
  %atp = getelementptr %value, ptr %args, i32 0, i32 1
  %at = load ptr, ptr %atp
  %alis = icmp eq ptr %at, @type_list
  br i1 %alis, label %doargs, label %endargs
doargs:
  %alp = getelementptr %value, ptr %args, i32 0, i32 2
  %first = load ptr, ptr %alp
  %hv = call ptr @hold(ptr %first)
  call void @record_set(ptr %obj, ptr %key, ptr %hv)
  br label %endargs
endargs:
  call void @drop(ptr %args)
  br label %endkey
endkey:
  call void @drop(ptr %key)
  br label %endhead
endhead:
  call void @drop(ptr %head)
  call void @drop(ptr %cur)
  br label %loop
done:
  call void @drop(ptr %cur)
  ret void
}

define private ptr @type_record_fill(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %LL = load ptr, ptr %LLp
  %p1 = icmp eq ptr %LL, null
  br i1 %p1, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %objarg = load ptr, ptr %LRp
  %obj = call ptr @arg(ptr %objarg)
  %otp = getelementptr %value, ptr %obj, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isrec = icmp eq ptr %ot, @type_record
  br i1 %isrec, label %yes, label %void
yes:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %listarg = load ptr, ptr %rp
  %list = call ptr @arg(ptr %listarg)
  call void @record_fill(ptr %obj, ptr %list)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %res = phi ptr [ %hqi, %yes ], [ %h, %void ]
  call void @drop(ptr %obj)
  ret ptr %res
}

define private ptr @rmod(ptr %obj, ptr %key, ptr %val, ptr %fn) {
entry:
  %vp = getelementptr %value, ptr %obj, i32 0, i32 3
  %rec = load ptr, ptr %vp
  %s = call %Search @find_key2(ptr %rec, ptr %key)
  %cmp = extractvalue %Search %s, 2
  %pos = extractvalue %Search %s, 0
  %found = icmp eq i32 %cmp, 0
  br i1 %found, label %existing, label %new
existing:
  %item = extractvalue %Search %s, 1
  %vp2 = getelementptr %Item, ptr %item, i32 0, i32 1
  %v = load ptr, ptr %vp2
  br label %apply
new:
  %it = call ptr @insert(ptr %rec, i64 %pos)
  %hk = call ptr @hold(ptr %key)
  %kp = getelementptr %Item, ptr %it, i32 0, i32 0
  store ptr %hk, ptr %kp
  %qv = load ptr, ptr @Qvoid
  %hqv = call ptr @hold(ptr %qv)
  %vp3 = getelementptr %Item, ptr %it, i32 0, i32 1
  store ptr %hqv, ptr %vp3
  br label %apply
apply:
  %cur = phi ptr [ %v, %existing ], [ %hqv, %new ]
  %hfn = call ptr @hold(ptr %fn)
  %hval = call ptr @hold(ptr %cur)
  %app = call ptr @A(ptr %hfn, ptr %hval)
  %nv = call ptr @eval(ptr %app)
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  %count = load i64, ptr %cp
  %in = icmp ult i64 %pos, %count
  br i1 %in, label %storeit, label %done
storeit:
  %vecp = getelementptr %Record, ptr %rec, i32 0, i32 2
  %vec = load ptr, ptr %vecp
  %item2 = getelementptr %Item, ptr %vec, i64 %pos
  %vp4 = getelementptr %Item, ptr %item2, i32 0, i32 1
  %hv2 = call ptr @hold(ptr %nv)
  %old = load ptr, ptr %vp4
  call void @drop(ptr %old)
  store ptr %hv2, ptr %vp4
  br label %done
done:
  ret ptr %nv
}

define private ptr @type_rmod(ptr %f) {
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
  %LLLLRp = getelementptr %value, ptr %LLLL, i32 0, i32 3
  %objarg = load ptr, ptr %LLLLRp
  %obj = call ptr @arg(ptr %objarg)
  %otp = getelementptr %value, ptr %obj, i32 0, i32 1
  %ot = load ptr, ptr %otp
  %isrec = icmp eq ptr %ot, @type_record
  br i1 %isrec, label %inrec, label %void
inrec:
  %LLRp = getelementptr %value, ptr %LL, i32 0, i32 3
  %karg = load ptr, ptr %LLRp
  %key = call ptr @arg(ptr %karg)
  %ktp = getelementptr %value, ptr %key, i32 0, i32 1
  %kt = load ptr, ptr %ktp
  %ks = icmp eq ptr %kt, @type_str
  %kn = icmp eq ptr %kt, @type_num
  %kok = or i1 %ks, %kn
  br i1 %kok, label %doit, label %voidkey
doit:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %val = load ptr, ptr %LRp
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %fn = load ptr, ptr %rp
  %res = call ptr @rmod(ptr %obj, ptr %key, ptr %val, ptr %fn)
  br label %donekey
voidkey:
  %qv = load ptr, ptr @Qvoid
  %hqv = call ptr @hold(ptr %qv)
  br label %donekey
donekey:
  %rk = phi ptr [ %res, %doit ], [ %hqv, %voidkey ]
  call void @drop(ptr %key)
  br label %done
void:
  %qv2 = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv2)
  br label %done
done:
  %r = phi ptr [ %rk, %donekey ], [ %h2, %void ]
  call void @drop(ptr %obj)
  ret ptr %r
}

define ptr @type_load_record(ptr %f) {
entry:
  %q0 = call ptr @Q0(ptr @type_empty)
  call void @define(ptr @.s_empty, ptr %q0)
  %q1 = call ptr @Q(ptr @type_set)
  call void @define(ptr @.s_set, ptr %q1)
  %q2 = call ptr @Q(ptr @type_setf)
  call void @define(ptr @.s_setf, ptr %q2)
  %q3 = call ptr @Q(ptr @type_del)
  call void @define(ptr @.s_del, ptr %q3)
  %q4 = call ptr @Q(ptr @type_get)
  call void @define(ptr @.s_get, ptr %q4)
  %q5 = call ptr @Q(ptr @type_record_copy)
  call void @define(ptr @.s_record_copy, ptr %q5)
  %q6 = call ptr @Q(ptr @type_record_count)
  call void @define(ptr @.s_record_count, ptr %q6)
  %q7 = call ptr @Q(ptr @type_record_item)
  call void @define(ptr @.s_record_item, ptr %q7)
  %q8 = call ptr @Q(ptr @type_fetch)
  call void @define(ptr @.s_fetch, ptr %q8)
  %q9 = call ptr @Q(ptr @type_record_fill)
  call void @define(ptr @.s_record_fill, ptr %q9)
  %q10 = call ptr @Q(ptr @type_rmod)
  call void @define(ptr @.s_rmod, ptr %q10)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
