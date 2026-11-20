; fexl/type_input.ll — lectura de caracteres de streams (antes type_input.c).

@Qvoid = external global ptr

declare ptr  @arg(ptr)
declare ptr  @Qstr(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @str_new_data(ptr, i64)
declare i8   @char_width(i8)

define ptr @op_getc(ptr %f, ptr %t, ptr %get) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %tp
  %is = icmp eq ptr %xt, %t
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %source = load ptr, ptr %vp
  %ch = call i32 %get(ptr %source)
  %eof = icmp eq i32 %ch, -1
  br i1 %eof, label %void, label %mk
mk:
  %c = trunc i32 %ch to i8
  %p = alloca i8, align 1
  store i8 %c, ptr %p, align 1
  %s = call ptr @str_new_data(ptr %p, i64 1)
  %res = call ptr @Qstr(ptr %s)
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

define private ptr @get_utf8(ptr %get, ptr %source) {
entry:
  %ch = call i32 %get(ptr %source)
  %eof = icmp eq i32 %ch, -1
  br i1 %eof, label %none, label %start
start:
  %buf = alloca [6 x i8], align 1
  %c0 = trunc i32 %ch to i8
  %w = call i8 @char_width(i8 %c0)
  %wu = zext i8 %w to i64
  %lt6 = icmp ult i64 %wu, 6
  %len = select i1 %lt6, i64 %wu, i64 6
  br label %loop
loop:
  %pos = phi i64 [ 0, %start ], [ %pos1, %more ]
  %cur = phi i32 [ %ch, %start ], [ %next, %more ]
  %at = getelementptr [6 x i8], ptr %buf, i64 0, i64 %pos
  %cb = trunc i32 %cur to i8
  store i8 %cb, ptr %at
  %pos1 = add i64 %pos, 1
  %full = icmp uge i64 %pos1, %len
  br i1 %full, label %finish, label %more
more:
  %next = call i32 %get(ptr %source)
  %neof = icmp eq i32 %next, -1
  br i1 %neof, label %none, label %loop
finish:
  %r = call ptr @str_new_data(ptr %buf, i64 %len)
  ret ptr %r
none:
  ret ptr null
}

define ptr @op_get(ptr %f, ptr %t, ptr %get) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %xt = load ptr, ptr %tp
  %is = icmp eq ptr %xt, %t
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %source = load ptr, ptr %vp
  %s = call ptr @get_utf8(ptr %get, ptr %source)
  %nonnull = icmp ne ptr %s, null
  br i1 %nonnull, label %mk, label %void
mk:
  %res = call ptr @Qstr(ptr %s)
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
