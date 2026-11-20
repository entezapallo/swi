; fexl/type_buf.ll — buffers desde Fexl (antes src/type_buf.c).

%Buffer = type { i64, i64, ptr }

@QI    = external global ptr
@Qvoid = external global ptr

declare ptr  @type_void(ptr)
declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @Qstr(ptr)
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare void @define(ptr, ptr)
declare ptr  @new_memory(i64)
declare void @free_memory(ptr, i64)
declare void @buf_discard(ptr)
declare void @buf_put(ptr, ptr)
declare ptr  @buf_clear(ptr)
declare ptr  @type_str(ptr)

define private void @clear_buf(ptr %f) {
entry:
  %vp = getelementptr %value, ptr %f, i32 0, i32 3
  %buf = load ptr, ptr %vp
  call void @buf_discard(ptr %buf)
  call void @free_memory(ptr %buf, i64 24)
  ret void
}
@clear_buf_sentinel = private constant %value { i64 0, ptr @clear_buf, ptr null, ptr null }

define ptr @type_buf(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define private ptr @type_buf_new(ptr %f) {
entry:
  %buf = call ptr @new_memory(i64 24)
  %lp = getelementptr %Buffer, ptr %buf, i32 0, i32 0
  store i64 0, ptr %lp
  %sp = getelementptr %Buffer, ptr %buf, i32 0, i32 1
  store i64 0, ptr %sp
  %dp = getelementptr %Buffer, ptr %buf, i32 0, i32 2
  store ptr null, ptr %dp
  %r = call ptr @V(ptr @type_buf, ptr @clear_buf_sentinel, ptr %buf)
  ret ptr %r
}

define private ptr @type_buf_put(ptr %f) {
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
  %xb = icmp eq ptr %xt, @type_buf
  %ys = icmp eq ptr %yt, @type_str
  %both = and i1 %xb, %ys
  br i1 %both, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %buf = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %s = load ptr, ptr %yvp
  call void @buf_put(ptr %buf, ptr %s)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %hqi, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_buf_get(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_buf
  br i1 %is, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %buf = load ptr, ptr %xvp
  %s = call ptr @buf_clear(ptr %buf)
  %res = call ptr @Qstr(ptr %s)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define ptr @type_load_buf(ptr %f) {
entry:
  %q0 = call ptr @Q0(ptr @type_buf_new)
  call void @define(ptr @.s_new, ptr %q0)
  %q1 = call ptr @Q(ptr @type_buf_put)
  call void @define(ptr @.s_put, ptr %q1)
  %q2 = call ptr @Q(ptr @type_buf_get)
  call void @define(ptr @.s_get, ptr %q2)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

@.s_new = private constant [8 x i8] c"buf_new\00"
@.s_put = private constant [8 x i8] c"buf_put\00"
@.s_get = private constant [8 x i8] c"buf_get\00"
