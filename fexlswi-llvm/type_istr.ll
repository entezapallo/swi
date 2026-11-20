; fexl/type_istr.ll — iterador sobre strings (antes src/type_istr.c).

%Istr = type { i64, ptr }   ; pos, str (value)

@QI    = external global ptr
@Qvoid = external global ptr

@.s_readstr = private constant [8 x i8] c"readstr\00"
@.s_sgetc   = private constant [6 x i8] c"sgetc\00"
@.s_sget    = private constant [5 x i8] c"sget\00"
@.s_slook   = private constant [6 x i8] c"slook\00"

declare ptr  @type_void(ptr)
declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @Qstr(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare void @define(ptr, ptr)
declare ptr  @new_memory(i64)
declare void @free_memory(ptr, i64)
declare ptr  @str_new_data(ptr, i64)
declare ptr  @op_getc(ptr, ptr, ptr)
declare ptr  @op_get(ptr, ptr, ptr)
declare ptr  @type_str(ptr)

define private ptr @istr_new(ptr %x) {
entry:
  %in = call ptr @new_memory(i64 16)
  %pp = getelementptr %Istr, ptr %in, i32 0, i32 0
  store i64 0, ptr %pp
  %sp = getelementptr %Istr, ptr %in, i32 0, i32 1
  store ptr %x, ptr %sp
  ret ptr %in
}

define private void @clear_istr(ptr %f) {
entry:
  %vp = getelementptr %value, ptr %f, i32 0, i32 3
  %in = load ptr, ptr %vp
  %sp = getelementptr %Istr, ptr %in, i32 0, i32 1
  %s = load ptr, ptr %sp
  call void @drop(ptr %s)
  call void @free_memory(ptr %in, i64 16)
  ret void
}
@clear_istr_sentinel = private constant %value { i64 0, ptr @clear_istr, ptr null, ptr null }

define ptr @type_istr(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define private ptr @Qistr(ptr %x) {
entry:
  %in = call ptr @istr_new(ptr %x)
  %r = call ptr @V(ptr @type_istr, ptr @clear_istr_sentinel, ptr %in)
  ret ptr %r
}

define i32 @sgetc(ptr %in) {
entry:
  %sp = getelementptr %Istr, ptr %in, i32 0, i32 1
  %strval = load ptr, ptr %sp
  %svp = getelementptr %value, ptr %strval, i32 0, i32 3
  %str = load ptr, ptr %svp
  %lp = getelementptr i8, ptr %str, i64 0
  %len = load i64, ptr %lp
  %pp = getelementptr %Istr, ptr %in, i32 0, i32 0
  %pos = load i64, ptr %pp
  %has = icmp ult i64 %pos, %len
  br i1 %has, label %read, label %eof
read:
  %dp = getelementptr i8, ptr %str, i64 8
  %at = getelementptr i8, ptr %dp, i64 %pos
  %c = load i8, ptr %at
  %cu = zext i8 %c to i32
  %pos1 = add i64 %pos, 1
  store i64 %pos1, ptr %pp
  ret i32 %cu
eof:
  ret i32 -1
}

define private i32 @slook(ptr %in) {
entry:
  %sp = getelementptr %Istr, ptr %in, i32 0, i32 1
  %strval = load ptr, ptr %sp
  %svp = getelementptr %value, ptr %strval, i32 0, i32 3
  %str = load ptr, ptr %svp
  %lp = getelementptr i8, ptr %str, i64 0
  %len = load i64, ptr %lp
  %pp = getelementptr %Istr, ptr %in, i32 0, i32 0
  %pos = load i64, ptr %pp
  %has = icmp ult i64 %pos, %len
  br i1 %has, label %read, label %eof
read:
  %dp = getelementptr i8, ptr %str, i64 8
  %at = getelementptr i8, ptr %dp, i64 %pos
  %c = load i8, ptr %at
  %cu = zext i8 %c to i32
  ret i32 %cu
eof:
  ret i32 -1
}

define private ptr @type_readstr(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %h = call ptr @hold(ptr %x)
  %res = call ptr @Qistr(ptr %h)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h2, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_sgetc(ptr %f) {
entry:
  %r = call ptr @op_getc(ptr %f, ptr @type_istr, ptr @sgetc)
  ret ptr %r
}

define private ptr @type_sget(ptr %f) {
entry:
  %r = call ptr @op_get(ptr %f, ptr @type_istr, ptr @sgetc)
  ret ptr %r
}

define private ptr @type_slook(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_istr
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %in = load ptr, ptr %vp
  %ch = call i32 @slook(ptr %in)
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

define ptr @type_load_istr(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_readstr)
  call void @define(ptr @.s_readstr, ptr %q0)
  %q1 = call ptr @Q(ptr @type_sgetc)
  call void @define(ptr @.s_sgetc, ptr %q1)
  %q2 = call ptr @Q(ptr @type_sget)
  call void @define(ptr @.s_sget, ptr %q2)
  %q3 = call ptr @Q(ptr @type_slook)
  call void @define(ptr @.s_slook, ptr %q3)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
