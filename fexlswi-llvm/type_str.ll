; fexl/type_str.ll — tipo string del interprete Fexl (antes type_str.c).
; value_types.ll se inyecta por concatenacion en el build.

@QI    = external global ptr
@QT    = external global ptr
@Qvoid = external global ptr
@Qnull = external global ptr

@.s_dot          = private constant [2 x i8]  c".\00"
@.s_length       = private constant [7 x i8]  c"length\00"
@.s_slice        = private constant [6 x i8]  c"slice\00"
@.s_search       = private constant [7 x i8]  c"search\00"
@.s_str_num      = private constant [8 x i8]  c"str_num\00"
@.s_ord          = private constant [4 x i8]  c"ord\00"
@.s_chr          = private constant [4 x i8]  c"chr\00"
@.s_char_width   = private constant [11 x i8] c"char_width\00"
@.s_dirname      = private constant [8 x i8]  c"dirname\00"
@.s_basename     = private constant [9 x i8]  c"basename\00"
@.s_length_common= private constant [14 x i8] c"length_common\00"
@.s_compare_at   = private constant [11 x i8] c"compare_at\00"
@.s_is_str       = private constant [7 x i8]  c"is_str\00"

declare ptr  @type_void(ptr)
declare ptr  @boolean(i32)
declare ptr  @op_is_type(ptr, ptr)
declare ptr  @Qnum(double)
declare i64  @get_ulong(ptr)
declare ptr  @Q(ptr)
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @cons(ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @arg(ptr)
declare ptr  @eval(ptr)
declare void @define(ptr, ptr)
declare ptr  @new_memory(i64)
declare void @free_memory(ptr, i64)

declare ptr  @str_new_data(ptr, i64)
declare ptr  @str_new_data0(ptr)
declare void @str_free(ptr)
declare ptr  @str_concat(ptr, ptr)
declare ptr  @str_slice(ptr, i64, i64)
declare i64  @str_search(ptr, ptr, i64)
declare ptr  @dirname(ptr)
declare ptr  @basename(ptr)
declare i64  @length_common(ptr, ptr)
declare i8   @char_width(i8)
declare i32  @str0_double(ptr, ptr)
declare ptr  @type_list(ptr)
declare ptr  @type_num(ptr)

define private void @clear_str(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %s = load ptr, ptr %rp
  call void @str_free(ptr %s)
  ret void
}
@clear_str_sentinel = private constant %value { i64 0, ptr @clear_str, ptr null, ptr null }

define ptr @type_str(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define ptr @Qstr(ptr %x) {
entry:
  %r = call ptr @V(ptr @type_str, ptr @clear_str_sentinel, ptr %x)
  ret ptr %r
}

define ptr @Qstr0(ptr %data) {
entry:
  %s = call ptr @str_new_data0(ptr %data)
  %r = call ptr @Qstr(ptr %s)
  ret ptr %r
}

define ptr @str_data(ptr %x) {
entry:
  %rp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %rp
  %d = getelementptr i8, ptr %s, i64 8
  ret ptr %d
}

define private ptr @is_str_value(ptr %v) {
entry:
  %tp = getelementptr %value, ptr %v, i32 0, i32 1
  %t = load ptr, ptr %tp
  %ok = icmp eq ptr %t, @type_str
  ret ptr %v
}

define ptr @op_str(ptr %f, ptr %op) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %is = icmp eq ptr %xt, @type_str
  br i1 %is, label %dos, label %void
dos:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %result = call ptr %op(ptr %xv)
  %nonnull = icmp ne ptr %result, null
  br i1 %nonnull, label %wrap, label %void
wrap:
  %q = call ptr @Qstr(ptr %result)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %wrap ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define ptr @op_str2(ptr %f, ptr %op) {
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
  %lx = load ptr, ptr %LRp
  %x = call ptr @arg(ptr %lx)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %y = call ptr @arg(ptr %rv)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %both = and i1 %xs, %ys
  br i1 %both, label %dos, label %void
dos:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %result = call ptr %op(ptr %xv, ptr %yv)
  %nonnull = icmp ne ptr %result, null
  br i1 %nonnull, label %wrap, label %void
wrap:
  %q = call ptr @Qstr(ptr %result)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %wrap ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define ptr @op_str3(ptr %f, ptr %op) {
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
  %xarg = load ptr, ptr %LLRp
  %x = call ptr @arg(ptr %xarg)
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %yarg = load ptr, ptr %LRp
  %y = call ptr @arg(ptr %yarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %zarg = load ptr, ptr %rp
  %z = call ptr @arg(ptr %zarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %ztp = getelementptr %value, ptr %z, i32 0, i32 1
  %zt = load ptr, ptr %ztp
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %zs = icmp eq ptr %zt, @type_str
  %a = and i1 %xs, %ys
  %all = and i1 %a, %zs
  br i1 %all, label %dos, label %void
dos:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %zvp = getelementptr %value, ptr %z, i32 0, i32 3
  %zv = load ptr, ptr %zvp
  %result = call ptr %op(ptr %xv, ptr %yv, ptr %zv)
  %nonnull = icmp ne ptr %result, null
  br i1 %nonnull, label %wrap, label %void
wrap:
  %q = call ptr @Qstr(ptr %result)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %wrap ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  call void @drop(ptr %z)
  ret ptr %r
}

define private ptr @type_concat(ptr %f) {
entry:
  %r = call ptr @op_str2(ptr %f, ptr @str_concat)
  ret ptr %r
}

define private ptr @type_length(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %is = icmp eq ptr %xt, @type_str
  br i1 %is, label %num, label %void
num:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %xvp
  %lp = getelementptr i8, ptr %s, i64 0
  %len = load i64, ptr %lp
  %d = sitofp i64 %len to double
  %q = call ptr @Qnum(double %d)
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

define private ptr @type_slice(ptr %f) {
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
  %xarg = load ptr, ptr %LLRp
  %x = call ptr @arg(ptr %xarg)
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %yarg = load ptr, ptr %LRp
  %y = call ptr @arg(ptr %yarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %zarg = load ptr, ptr %rp
  %z = call ptr @arg(ptr %zarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %ztp = getelementptr %value, ptr %z, i32 0, i32 1
  %zt = load ptr, ptr %ztp
  %xs = icmp eq ptr %xt, @type_str
  %yn = icmp eq ptr %yt, @type_num
  %zn = icmp eq ptr %zt, @type_num
  %a = and i1 %xs, %yn
  %all = and i1 %a, %zn
  br i1 %all, label %check, label %void
check:
  %ydp = getelementptr %value, ptr %y, i32 0, i32 3
  %yd = load double, ptr %ydp
  %zdp = getelementptr %value, ptr %z, i32 0, i32 3
  %zd = load double, ptr %zdp
  %yok = fcmp oge double %yd, 0.0
  %zok = fcmp oge double %zd, 0.0
  %ok = and i1 %yok, %zok
  br i1 %ok, label %dos, label %void
dos:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %xvp
  %yi = fptosi double %yd to i64
  %zi = fptosi double %zd to i64
  %result = call ptr @str_slice(ptr %s, i64 %yi, i64 %zi)
  %q = call ptr @Qstr(ptr %result)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %dos ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  call void @drop(ptr %z)
  ret ptr %r
}

define private ptr @type_search(ptr %f) {
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
  %xarg = load ptr, ptr %LLRp
  %x = call ptr @arg(ptr %xarg)
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %yarg = load ptr, ptr %LRp
  %y = call ptr @arg(ptr %yarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %zarg = load ptr, ptr %rp
  %z = call ptr @arg(ptr %zarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %ztp = getelementptr %value, ptr %z, i32 0, i32 1
  %zt = load ptr, ptr %ztp
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %zn = icmp eq ptr %zt, @type_num
  %a = and i1 %xs, %ys
  %all = and i1 %a, %zn
  br i1 %all, label %check, label %void
check:
  %zdp = getelementptr %value, ptr %z, i32 0, i32 3
  %zd = load double, ptr %zdp
  %ok = fcmp oge double %zd, 0.0
  br i1 %ok, label %dos, label %void
dos:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xs2 = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %ys2 = load ptr, ptr %yvp
  %zi = fptosi double %zd to i64
  %pos = call i64 @str_search(ptr %xs2, ptr %ys2, i64 %zi)
  %lp = getelementptr i8, ptr %xs2, i64 0
  %xlen = load i64, ptr %lp
  %found = icmp ult i64 %pos, %xlen
  br i1 %found, label %num, label %void
num:
  %d = sitofp i64 %pos to double
  %q = call ptr @Qnum(double %d)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %num ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  call void @drop(ptr %z)
  ret ptr %r
}

define private ptr @type_str_num(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %is = icmp eq ptr %xt, @type_str
  br i1 %is, label %conv, label %void
conv:
  %d = alloca double, align 8
  %txt = call ptr @str_data(ptr %x)
  %ok = call i32 @str0_double(ptr %txt, ptr %d)
  %good = icmp eq i32 %ok, 1
  br i1 %good, label %num, label %void
num:
  %v = load double, ptr %d, align 8
  %q = call ptr @Qnum(double %v)
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

define private ptr @type_ord(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %is = icmp eq ptr %xt, @type_str
  br i1 %is, label %num, label %void
num:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %xvp
  %lp = getelementptr i8, ptr %s, i64 0
  %len = load i64, ptr %lp
  %nz = icmp ne i64 %len, 0
  br i1 %nz, label %read, label %zero
read:
  %dp = getelementptr i8, ptr %s, i64 8
  %c = load i8, ptr %dp
  %cu = zext i8 %c to i64
  %d = sitofp i64 %cu to double
  br label %mk
zero:
  %d0 = sitofp i64 0 to double
  br label %mk
mk:
  %dv = phi double [ %d, %read ], [ %d0, %zero ]
  %q = call ptr @Qnum(double %dv)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %mk ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_chr(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %is = icmp eq ptr %xt, @type_num
  br i1 %is, label %mk, label %void
mk:
  %dp = getelementptr %value, ptr %x, i32 0, i32 3
  %d = load double, ptr %dp
  %i = fptosi double %d to i8
  %ch = alloca i8, align 1
  store i8 %i, ptr %ch, align 1
  %s = call ptr @str_new_data(ptr %ch, i64 1)
  %q = call ptr @Qstr(ptr %s)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %mk ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_char_width(ptr %f) {
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
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %yarg = load ptr, ptr %rp
  %y = call ptr @arg(ptr %yarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xs = icmp eq ptr %xt, @type_str
  %yn = icmp eq ptr %yt, @type_num
  %both = and i1 %xs, %yn
  br i1 %both, label %check, label %void
check:
  %ydp = getelementptr %value, ptr %y, i32 0, i32 3
  %yd = load double, ptr %ydp
  %ok = fcmp oge double %yd, 0.0
  br i1 %ok, label %read, label %void
read:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %xvp
  %lp = getelementptr i8, ptr %s, i64 0
  %len = load i64, ptr %lp
  %pos = fptosi double %yd to i64
  %in = icmp ult i64 %pos, %len
  br i1 %in, label %mk, label %void
mk:
  %dp = getelementptr i8, ptr %s, i64 8
  %at = getelementptr i8, ptr %dp, i64 %pos
  %c = load i8, ptr %at
  %w = call i8 @char_width(i8 %c)
  %wi = zext i8 %w to i64
  %d = sitofp i64 %wi to double
  %q = call ptr @Qnum(double %d)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %mk ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_dirname(ptr %f) {
entry:
  %r = call ptr @op_str(ptr %f, ptr @dirname)
  ret ptr %r
}
define private ptr @type_basename(ptr %f) {
entry:
  %r = call ptr @op_str(ptr %f, ptr @basename)
  ret ptr %r
}

define private ptr @type_length_common(ptr %f) {
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
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %yarg = load ptr, ptr %rp
  %y = call ptr @arg(ptr %yarg)
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %both = and i1 %xs, %ys
  br i1 %both, label %num, label %void
num:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xv = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %yv = load ptr, ptr %yvp
  %n = call i64 @length_common(ptr %xv, ptr %yv)
  %d = sitofp i64 %n to double
  %q = call ptr @Qnum(double %d)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %q, %num ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_compare_at(ptr %f) {
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
  br i1 %p3, label %keepf, label %lv4
lv4:
  %LLLLLp = getelementptr %value, ptr %LLLL, i32 0, i32 2
  %LLLLL = load ptr, ptr %LLLLLp
  %p4 = icmp eq ptr %LLLLL, null
  br i1 %p4, label %keepf, label %lv5
lv5:
  %LLLLLLp = getelementptr %value, ptr %LLLLL, i32 0, i32 2
  %LLLLLL = load ptr, ptr %LLLLLLp
  %p5 = icmp eq ptr %LLLLLL, null
  br i1 %p5, label %keepf, label %body
keepf:
  %k = call ptr @keep(ptr %f)
  ret ptr %k
body:
  %posp = getelementptr %value, ptr %LLLLL, i32 0, i32 3
  %posarg = load ptr, ptr %posp
  %pos = call ptr @arg(ptr %posarg)
  %xp = getelementptr %value, ptr %LLLL, i32 0, i32 3
  %xarg = load ptr, ptr %xp
  %x = call ptr @arg(ptr %xarg)
  %yp = getelementptr %value, ptr %LLL, i32 0, i32 3
  %yarg = load ptr, ptr %yp
  %y = call ptr @arg(ptr %yarg)
  %postp = getelementptr %value, ptr %pos, i32 0, i32 1
  %post = load ptr, ptr %postp
  %xtp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %xtp
  %ytp = getelementptr %value, ptr %y, i32 0, i32 1
  %yt = load ptr, ptr %ytp
  %pn = icmp eq ptr %post, @type_num
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %a = and i1 %pn, %xs
  %all = and i1 %a, %ys
  br i1 %all, label %cmp, label %void
cmp:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xs2 = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %ys2 = load ptr, ptr %yvp
  %n = call i64 @get_ulong(ptr %pos)
  %xlp = getelementptr i8, ptr %xs2, i64 0
  %xlen = load i64, ptr %xlp
  %in = icmp ult i64 %n, %xlen
  br i1 %in, label %readx, label %cxneg
readx:
  %xdp = getelementptr i8, ptr %xs2, i64 8
  %xa = getelementptr i8, ptr %xdp, i64 %n
  %xc = load i8, ptr %xa
  %xcx = sext i8 %xc to i32
  br label %cxdone
cxneg:
  br label %cxdone
cxdone:
  %cx = phi i32 [ %xcx, %readx ], [ -1, %cxneg ]
  %ylp = getelementptr i8, ptr %ys2, i64 0
  %ylen = load i64, ptr %ylp
  %iny = icmp ult i64 %n, %ylen
  br i1 %iny, label %ready, label %cyneg
ready:
  %ydp = getelementptr i8, ptr %ys2, i64 8
  %ya = getelementptr i8, ptr %ydp, i64 %n
  %yc = load i8, ptr %ya
  %ycx = sext i8 %yc to i32
  br label %cydone
cyneg:
  br label %cydone
cydone:
  %cy = phi i32 [ %ycx, %ready ], [ -1, %cyneg ]
  %lt = icmp slt i32 %cx, %cy
  %eqv = icmp eq i32 %cx, %cy
  br i1 %lt, label %less, label %checkeq
checkeq:
  br i1 %eqv, label %equal, label %greater
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
less:
  %LLRp = getelementptr %value, ptr %LL, i32 0, i32 3
  %lr = load ptr, ptr %LLRp
  %hl = call ptr @hold(ptr %lr)
  br label %done
equal:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %lr2 = load ptr, ptr %LRp
  %he = call ptr @hold(ptr %lr2)
  br label %done
greater:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %hg = call ptr @hold(ptr %rv)
  br label %done
done:
  %r = phi ptr [ %h, %void ], [ %hl, %less ], [ %he, %equal ], [ %hg, %greater ]
  call void @drop(ptr %pos)
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_is_str(ptr %f) {
entry:
  %r = call ptr @op_is_type(ptr %f, ptr @type_str)
  ret ptr %r
}

define private i64 @list_length(ptr %p) {
entry:
  br label %loop
loop:
  %cur = phi ptr [ %p, %entry ], [ %next, %body ]
  %n = phi i64 [ 0, %entry ], [ %n1, %body ]
  %tp = getelementptr %value, ptr %cur, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_list
  br i1 %is, label %body, label %done
body:
  %rp = getelementptr %value, ptr %cur, i32 0, i32 3
  %next = load ptr, ptr %rp
  %n1 = add i64 %n, 1
  br label %loop
done:
  ret i64 %n
}

define private ptr @expand(ptr %list) {
entry:
  %v = call ptr @eval(ptr %list)
  %tp = getelementptr %value, ptr %v, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_list
  br i1 %is, label %body, label %done
body:
  %lp = getelementptr %value, ptr %v, i32 0, i32 2
  %headarg = load ptr, ptr %lp
  %head = call ptr @arg(ptr %headarg)
  %htp = getelementptr %value, ptr %head, i32 0, i32 1
  %ht = load ptr, ptr %htp
  %isstr = icmp eq ptr %ht, @type_str
  br i1 %isstr, label %yes, label %no
yes:
  %rp = getelementptr %value, ptr %v, i32 0, i32 3
  %tail = call ptr @hold(ptr %rp)
  call void @drop(ptr %v)
  %rest = call ptr @expand(ptr %tail)
  %res = call ptr @cons(ptr %head, ptr %rest)
  ret ptr %res
no:
  call void @drop(ptr %head)
  call void @drop(ptr %v)
  %qn = load ptr, ptr @Qnull
  %h = call ptr @hold(ptr %qn)
  ret ptr %h
done:
  ret ptr %v
}

define ptr @op_argv(ptr %f, ptr %op) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %h = call ptr @hold(ptr %rv)
  %items = call ptr @expand(ptr %h)
  %len = call i64 @list_length(ptr %items)
  %n1 = add i64 %len, 1
  %size = shl i64 %n1, 3
  %argv = call ptr @new_memory(i64 %size)
  br label %loop
loop:
  %p = phi ptr [ %items, %entry ], [ %next, %body ]
  %pos = phi i64 [ 0, %entry ], [ %pos1, %body ]
  %tp = getelementptr %value, ptr %p, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_list
  br i1 %is, label %body, label %end
body:
  %lp = getelementptr %value, ptr %p, i32 0, i32 2
  %lr = load ptr, ptr %lp
  %s = call ptr @str_data(ptr %lr)
  %slot = getelementptr ptr, ptr %argv, i64 %pos
  store ptr %s, ptr %slot
  %rp2 = getelementptr %value, ptr %p, i32 0, i32 3
  %next = load ptr, ptr %rp2
  %pos1 = add i64 %pos, 1
  br label %loop
end:
  %sentinel = getelementptr ptr, ptr %argv, i64 %pos
  store ptr null, ptr %sentinel
  %result = call ptr %op(ptr %argv)
  call void @free_memory(ptr %argv, i64 %size)
  call void @drop(ptr %items)
  ret ptr %result
}

define ptr @type_load_str(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_concat)
  call void @define(ptr @.s_dot, ptr %q0)
  %q1 = call ptr @Q(ptr @type_length)
  call void @define(ptr @.s_length, ptr %q1)
  %q2 = call ptr @Q(ptr @type_slice)
  call void @define(ptr @.s_slice, ptr %q2)
  %q3 = call ptr @Q(ptr @type_search)
  call void @define(ptr @.s_search, ptr %q3)
  %q4 = call ptr @Q(ptr @type_str_num)
  call void @define(ptr @.s_str_num, ptr %q4)
  %q5 = call ptr @Q(ptr @type_ord)
  call void @define(ptr @.s_ord, ptr %q5)
  %q6 = call ptr @Q(ptr @type_chr)
  call void @define(ptr @.s_chr, ptr %q6)
  %q7 = call ptr @Q(ptr @type_char_width)
  call void @define(ptr @.s_char_width, ptr %q7)
  %q8 = call ptr @Q(ptr @type_dirname)
  call void @define(ptr @.s_dirname, ptr %q8)
  %q9 = call ptr @Q(ptr @type_basename)
  call void @define(ptr @.s_basename, ptr %q9)
  %q10 = call ptr @Q(ptr @type_length_common)
  call void @define(ptr @.s_length_common, ptr %q10)
  %q11 = call ptr @Q(ptr @type_compare_at)
  call void @define(ptr @.s_compare_at, ptr %q11)
  %q12 = call ptr @Q(ptr @type_is_str)
  call void @define(ptr @.s_is_str, ptr %q12)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
