; fexl/type_sym.ll — simbolos, sustitucion y forms (antes src/type_sym.c).
; value_types.ll se inyecta por concatenacion en el build.

%Item   = type { ptr, ptr }
%Record = type { i64, i64, ptr }

@Qstd        = global ptr null
@cache_undef = internal global ptr null

@QI    = external global ptr
@QT    = external global ptr
@QF    = external global ptr
@Qvoid = external global ptr

@.s_std       = private constant [4 x i8] c"std\00"
@.s_is_closed = private constant [10 x i8] c"is_closed\00"
@.s_define    = private constant [7 x i8] c"define\00"
@.s_resolve   = private constant [8 x i8] c"resolve\00"
@.s_set_std   = private constant [8 x i8] c"set_std\00"

declare ptr  @type_void(ptr)
declare ptr  @boolean(i32)
declare ptr  @Q0(ptr)
declare ptr  @Q(ptr)
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @A(ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @arg(ptr)
declare ptr  @tail(ptr)
declare ptr  @new_value()
declare void @recycle(ptr)
declare ptr  @Qstr(ptr)
declare ptr  @Qstr0(ptr)
declare ptr  @str_copy(ptr)
declare i32  @str_eq(ptr, ptr)
declare ptr  @str_data(ptr)
declare void @str_free(ptr)
declare ptr  @record_empty()
declare ptr  @record_find(ptr, ptr)
declare void @record_set(ptr, ptr, ptr)
declare void @undefined_symbol(ptr, i64, ptr)
declare void @die(ptr)
declare ptr  @type_record(ptr)
declare ptr  @type_str(ptr)

define private void @clear_quo(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %r = load ptr, ptr %rp
  call void @drop(ptr %r)
  ret void
}
@clear_quo_sentinel = private constant %value { i64 0, ptr @clear_quo, ptr null, ptr null }

define private void @clear_ref(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %x = load ptr, ptr %rp
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %xvp
  call void @str_free(ptr %s)
  call void @recycle(ptr %x)
  ret void
}
@clear_ref_sentinel = private constant %value { i64 0, ptr @clear_ref, ptr null, ptr null }

define private ptr @type_std(ptr %f) {
entry:
  %q = load ptr, ptr @Qstd
  %r = call ptr @hold(ptr %q)
  ret ptr %r
}

define ptr @type_quo(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define ptr @type_ref(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define ptr @quo(ptr %val) {
entry:
  %r = call ptr @V(ptr @type_quo, ptr @clear_quo_sentinel, ptr %val)
  ret ptr %r
}

define ptr @ref(ptr %name, i64 %line) {
entry:
  %x = call ptr @new_value()
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  store ptr %name, ptr %vp
  %np = getelementptr %value, ptr %x, i32 0, i32 0
  store i64 %line, ptr %np
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  store ptr @type_str, ptr %tp
  %r = call ptr @V(ptr @type_ref, ptr @clear_ref_sentinel, ptr %x)
  ret ptr %r
}

define ptr @join(ptr %t, ptr %x, ptr %y) {
entry:
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xq = icmp eq ptr %xt, @type_quo
  %yq = icmp eq ptr %yt, @type_quo
  %both = and i1 %xq, %yq
  br i1 %both, label %wrap, label %plain
wrap:
  %tx = call ptr @tail(ptr %x)
  %ty = call ptr @tail(ptr %y)
  %inner = call ptr @V(ptr %t, ptr %tx, ptr %ty)
  %r = call ptr @quo(ptr %inner)
  ret ptr %r
plain:
  %r2 = call ptr @V(ptr %t, ptr %x, ptr %y)
  ret ptr %r2
}

define ptr @app(ptr %x, ptr %y) {
entry:
  %r = call ptr @join(ptr null, ptr %x, ptr %y)
  ret ptr %r
}

define private ptr @get_pattern(ptr %name, ptr %e) {
entry:
  %tp = getelementptr %value, ptr %e, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isquo = icmp eq ptr %t, @type_quo
  br i1 %isquo, label %quo, label %checkref
quo:
  %qf = load ptr, ptr @QF
  %h = call ptr @hold(ptr %qf)
  ret ptr %h
checkref:
  %isref = icmp eq ptr %t, @type_ref
  br i1 %isref, label %refcase, label %recurse
refcase:
  %rp = getelementptr %value, ptr %e, i32 0, i32 3
  %inner = load ptr, ptr %rp
  %vp = getelementptr %value, ptr %inner, i32 0, i32 3
  %s = load ptr, ptr %vp
  %eq = call i32 @str_eq(ptr %name, ptr %s)
  %yes = icmp eq i32 %eq, 1
  %q = select i1 %yes, ptr @QT, ptr @QF
  %qv = load ptr, ptr %q
  %h2 = call ptr @hold(ptr %qv)
  ret ptr %h2
recurse:
  %lp = getelementptr %value, ptr %e, i32 0, i32 2
  %l = load ptr, ptr %lp
  %rp2 = getelementptr %value, ptr %e, i32 0, i32 3
  %r = load ptr, ptr %rp2
  %pl = call ptr @get_pattern(ptr %name, ptr %l)
  %pr = call ptr @get_pattern(ptr %name, ptr %r)
  %qf2 = load ptr, ptr @QF
  %lq = icmp eq ptr %pl, %qf2
  %rq = icmp eq ptr %pr, %qf2
  %both = and i1 %lq, %rq
  br i1 %both, label %none, label %some
none:
  call void @drop(ptr %pl)
  call void @drop(ptr %pr)
  %h3 = call ptr @hold(ptr %qf2)
  ret ptr %h3
some:
  %res = call ptr @A(ptr %pl, ptr %pr)
  ret ptr %res
}

define private ptr @subf(ptr %p, ptr %e, ptr %x) {
entry:
  %qf = load ptr, ptr @QF
  %qt = load ptr, ptr @QT
  %isqf = icmp eq ptr %p, %qf
  br i1 %isqf, label %f, label %checkt
f:
  %he = call ptr @hold(ptr %e)
  ret ptr %he
checkt:
  %isqt = icmp eq ptr %p, %qt
  br i1 %isqt, label %t, label %recurse
t:
  %hx = call ptr @hold(ptr %x)
  ret ptr %hx
recurse:
  %etp = getelementptr %value, ptr %e, i32 0, i32 1
  %et = load ptr, ptr %etp
  %elp = getelementptr %value, ptr %e, i32 0, i32 2
  %el = load ptr, ptr %elp
  %erp = getelementptr %value, ptr %e, i32 0, i32 3
  %er = load ptr, ptr %erp
  %plp = getelementptr %value, ptr %p, i32 0, i32 2
  %pl = load ptr, ptr %plp
  %prp = getelementptr %value, ptr %p, i32 0, i32 3
  %pr = load ptr, ptr %prp
  %sl = call ptr @subf(ptr %pl, ptr %el, ptr %x)
  %sr = call ptr @subf(ptr %pr, ptr %er, ptr %x)
  %res = call ptr @join(ptr %et, ptr %sl, ptr %sr)
  ret ptr %res
}

define ptr @lam(ptr %ty, ptr %name, ptr %e) {
entry:
  %p = call ptr @get_pattern(ptr %name, ptr %e)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  %x = call ptr @quo(ptr %hqi)
  %f = call ptr @subf(ptr %p, ptr %e, ptr %x)
  call void @drop(ptr %x)
  %ftp = getelementptr %value, ptr %f, i32 0, i32 1
  %ft = load ptr, ptr %ftp
  %isquo = icmp eq ptr %ft, @type_quo
  br i1 %isquo, label %qcase, label %plain
qcase:
  %t = call ptr @tail(ptr %f)
  %inner = call ptr @V(ptr %ty, ptr %p, ptr %t)
  %res = call ptr @quo(ptr %inner)
  br label %done
plain:
  %qp = call ptr @quo(ptr %p)
  %res2 = call ptr @V(ptr %ty, ptr %qp, ptr %f)
  br label %done
done:
  %r = phi ptr [ %res, %qcase ], [ %res2, %plain ]
  call void @str_free(ptr %name)
  call void @drop(ptr %e)
  ret ptr %r
}

define ptr @type_form(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define ptr @Qform(ptr %label, ptr %exp) {
entry:
  %r = call ptr @V(ptr @type_form, ptr %label, ptr %exp)
  ret ptr %r
}

define private ptr @sub(ptr %p, ptr %e, ptr %x) {
entry:
  %qf = load ptr, ptr @QF
  %qt = load ptr, ptr @QT
  %isqf = icmp eq ptr %p, %qf
  br i1 %isqf, label %f, label %checkt
f:
  %he = call ptr @hold(ptr %e)
  ret ptr %he
checkt:
  %isqt = icmp eq ptr %p, %qt
  br i1 %isqt, label %t, label %recurse
t:
  %hx = call ptr @hold(ptr %x)
  ret ptr %hx
recurse:
  %etp = getelementptr %value, ptr %e, i32 0, i32 1
  %et = load ptr, ptr %etp
  %elp = getelementptr %value, ptr %e, i32 0, i32 2
  %el = load ptr, ptr %elp
  %erp = getelementptr %value, ptr %e, i32 0, i32 3
  %er = load ptr, ptr %erp
  %plp = getelementptr %value, ptr %p, i32 0, i32 2
  %pl = load ptr, ptr %plp
  %prp = getelementptr %value, ptr %p, i32 0, i32 3
  %pr = load ptr, ptr %prp
  %sl = call ptr @sub(ptr %pl, ptr %el, ptr %x)
  %sr = call ptr @sub(ptr %pr, ptr %er, ptr %x)
  %res = call ptr @V(ptr %et, ptr %sl, ptr %sr)
  ret ptr %res
}

define ptr @type_D(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %p = load ptr, ptr %LLp
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %e = load ptr, ptr %LRp
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %x = load ptr, ptr %rp
  %res = call ptr @sub(ptr %p, ptr %e, ptr %x)
  ret ptr %res
}

define ptr @type_E(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LLp = getelementptr %value, ptr %L, i32 0, i32 2
  %p = load ptr, ptr %LLp
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %e = load ptr, ptr %LRp
  %g = call ptr @sub(ptr %p, ptr %e, ptr %x)
  call void @drop(ptr %x)
  ret ptr %g
}

define private ptr @type_is_closed(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %form = call ptr @arg(ptr %rv)
  %ftp = getelementptr %value, ptr %form, i32 0, i32 1
  %ft = load ptr, ptr %ftp
  %is = icmp eq ptr %ft, @type_form
  br i1 %is, label %yes, label %void
yes:
  %frp = getelementptr %value, ptr %form, i32 0, i32 3
  %exp = load ptr, ptr %frp
  %etp = getelementptr %value, ptr %exp, i32 0, i32 1
  %et = load ptr, ptr %etp
  %isq = icmp eq ptr %et, @type_quo
  %ci = zext i1 %isq to i32
  %b = call ptr @boolean(i32 %ci)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %b, %yes ], [ %h, %void ]
  call void @drop(ptr %form)
  ret ptr %r
}

define private void @set_std(ptr %obj) {
entry:
  %old = load ptr, ptr @Qstd
  call void @drop(ptr %old)
  store ptr %obj, ptr @Qstd
  ret void
}

define void @define(ptr %name, ptr %val) {
entry:
  %key = call ptr @Qstr0(ptr %name)
  %std = load ptr, ptr @Qstd
  call void @record_set(ptr %std, ptr %key, ptr %val)
  call void @drop(ptr %key)
  ret void
}

define private ptr @type_define(ptr %f) {
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
  %karg = load ptr, ptr %LRp
  %key = call ptr @arg(ptr %karg)
  %ktp = getelementptr %value, ptr %key, i32 0, i32 1
  %kt = load ptr, ptr %ktp
  %is = icmp eq ptr %kt, @type_str
  br i1 %is, label %yes, label %void
yes:
  %std = load ptr, ptr @Qstd
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %v = load ptr, ptr %rp
  %hv = call ptr @hold(ptr %v)
  call void @record_set(ptr %std, ptr %key, ptr %hv)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %hqi, %yes ], [ %h, %void ]
  call void @drop(ptr %key)
  ret ptr %r
}

define private ptr @resolve(ptr %exp) {
entry:
  %tp = getelementptr %value, ptr %exp, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isq = icmp eq ptr %t, @type_quo
  br i1 %isq, label %quo, label %checkref
quo:
  %h = call ptr @hold(ptr %exp)
  ret ptr %h
checkref:
  %isr = icmp eq ptr %t, @type_ref
  br i1 %isr, label %refcase, label %recurse
refcase:
  %rp = getelementptr %value, ptr %exp, i32 0, i32 3
  %key = load ptr, ptr %rp
  %std = load ptr, ptr @Qstd
  %val = call ptr @record_find(ptr %std, ptr %key)
  %found = icmp ne ptr %val, null
  br i1 %found, label %yes, label %no
yes:
  %hv = call ptr @hold(ptr %val)
  %q = call ptr @quo(ptr %hv)
  ret ptr %q
no:
  %h2 = call ptr @hold(ptr %exp)
  ret ptr %h2
recurse:
  %lp = getelementptr %value, ptr %exp, i32 0, i32 2
  %l = load ptr, ptr %lp
  %rp2 = getelementptr %value, ptr %exp, i32 0, i32 3
  %r = load ptr, ptr %rp2
  %rl = call ptr @resolve(ptr %l)
  %rr = call ptr @resolve(ptr %r)
  %res = call ptr @join(ptr %t, ptr %rl, ptr %rr)
  ret ptr %res
}

define private ptr @type_resolve(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %form = call ptr @arg(ptr %rv)
  %ftp = getelementptr %value, ptr %form, i32 0, i32 1
  %ft = load ptr, ptr %ftp
  %is = icmp eq ptr %ft, @type_form
  br i1 %is, label %yes, label %void
yes:
  %frp = getelementptr %value, ptr %form, i32 0, i32 3
  %exp = load ptr, ptr %frp
  %r = call ptr @resolve(ptr %exp)
  %flp = getelementptr %value, ptr %form, i32 0, i32 2
  %lab = load ptr, ptr %flp
  %hl = call ptr @hold(ptr %lab)
  %res = call ptr @Qform(ptr %hl, ptr %r)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %rr = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %form)
  ret ptr %rr
}

define private void @collect_undef(ptr %exp) {
entry:
  %tp = getelementptr %value, ptr %exp, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isq = icmp eq ptr %t, @type_quo
  br i1 %isq, label %done, label %checkref
checkref:
  %isr = icmp eq ptr %t, @type_ref
  br i1 %isr, label %refcase, label %recurse
refcase:
  %rp = getelementptr %value, ptr %exp, i32 0, i32 3
  %key = load ptr, ptr %rp
  %cache = load ptr, ptr @cache_undef
  %found = call ptr @record_find(ptr %cache, ptr %key)
  %none = icmp eq ptr %found, null
  br i1 %none, label %add, label %done
add:
  %xvp = getelementptr %value, ptr %key, i32 0, i32 3
  %s = load ptr, ptr %xvp
  %cp = call ptr @str_copy(ptr %s)
  %newkey = call ptr @Qstr(ptr %cp)
  %he = call ptr @hold(ptr %exp)
  call void @record_set(ptr %cache, ptr %newkey, ptr %he)
  call void @drop(ptr %newkey)
  br label %done
recurse:
  %lp = getelementptr %value, ptr %exp, i32 0, i32 2
  %l = load ptr, ptr %lp
  %rp2 = getelementptr %value, ptr %exp, i32 0, i32 3
  %r = load ptr, ptr %rp2
  call void @collect_undef(ptr %l)
  call void @collect_undef(ptr %r)
  br label %done
done:
  ret void
}

define private void @report_undef(ptr %exp, ptr %label) {
entry:
  %rec = call ptr @record_empty()
  store ptr %rec, ptr @cache_undef
  call void @collect_undef(ptr %exp)
  %recval = load ptr, ptr @cache_undef
  %recptr = getelementptr %value, ptr %recval, i32 0, i32 3
  %recdata = load ptr, ptr %recptr
  %countp = getelementptr %Record, ptr %recdata, i32 0, i32 0
  %count = load i64, ptr %countp
  %vecp = getelementptr %Record, ptr %recdata, i32 0, i32 2
  %vec = load ptr, ptr %vecp
  br label %loop
loop:
  %pos = phi i64 [ 0, %entry ], [ %pos1, %body ]
  %cont = icmp ult i64 %pos, %count
  br i1 %cont, label %body, label %done
body:
  %item = getelementptr %Item, ptr %vec, i64 %pos
  %keyp = getelementptr %Item, ptr %item, i32 0, i32 0
  %keyval = load ptr, ptr %keyp
  %kvp = getelementptr %value, ptr %keyval, i32 0, i32 3
  %keystr = load ptr, ptr %kvp
  %kp = getelementptr i8, ptr %keystr, i64 8
  %valp = getelementptr %Item, ptr %item, i32 0, i32 1
  %expval = load ptr, ptr %valp
  %er = getelementptr %value, ptr %expval, i32 0, i32 3
  %inner = load ptr, ptr %er
  %np = getelementptr %value, ptr %inner, i32 0, i32 0
  %line = load i64, ptr %np
  call void @undefined_symbol(ptr %kp, i64 %line, ptr %label)
  %pos1 = add i64 %pos, 1
  br label %loop
done:
  %c = load ptr, ptr @cache_undef
  call void @drop(ptr %c)
  ret void
}

define ptr @type_evaluate(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %form = call ptr @arg(ptr %rv)
  %ftp = getelementptr %value, ptr %form, i32 0, i32 1
  %ft = load ptr, ptr %ftp
  %is = icmp eq ptr %ft, @type_form
  br i1 %is, label %yes, label %void
yes:
  %frp = getelementptr %value, ptr %form, i32 0, i32 3
  %exp = load ptr, ptr %frp
  %resolved = call ptr @resolve(ptr %exp)
  %rtp = getelementptr %value, ptr %resolved, i32 0, i32 1
  %rt = load ptr, ptr %rtp
  %isq = icmp eq ptr %rt, @type_quo
  br i1 %isq, label %getval, label %undef
getval:
  %v = call ptr @tail(ptr %resolved)
  br label %done
undef:
  %flp = getelementptr %value, ptr %form, i32 0, i32 2
  %lab = load ptr, ptr %flp
  %txt = call ptr @str_data(ptr %lab)
  call void @report_undef(ptr %resolved, ptr %txt)
  call void @drop(ptr %resolved)
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  call void @die(ptr null)
  br label %done
void:
  %qv2 = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv2)
  br label %done
done:
  %r = phi ptr [ %v, %getval ], [ %h, %undef ], [ %h2, %void ]
  call void @drop(ptr %form)
  ret ptr %r
}

define private ptr @type_set_std(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %is = icmp eq ptr %xt, @type_record
  br i1 %is, label %yes, label %void
yes:
  %h = call ptr @hold(ptr %x)
  call void @set_std(ptr %h)
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

define ptr @type_load_sym(ptr %f) {
entry:
  %q0 = call ptr @Q0(ptr @type_std)
  call void @define(ptr @.s_std, ptr %q0)
  %q1 = call ptr @Q(ptr @type_is_closed)
  call void @define(ptr @.s_is_closed, ptr %q1)
  %q2 = call ptr @Q(ptr @type_define)
  call void @define(ptr @.s_define, ptr %q2)
  %q3 = call ptr @Q(ptr @type_resolve)
  call void @define(ptr @.s_resolve, ptr %q3)
  %q4 = call ptr @Q(ptr @type_set_std)
  call void @define(ptr @.s_set_std, ptr %q4)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define void @beg_sym() {
entry:
  %r = call ptr @record_empty()
  store ptr %r, ptr @Qstd
  ret void
}

define void @end_sym() {
entry:
  %r = load ptr, ptr @Qstd
  call void @drop(ptr %r)
  ret void
}
