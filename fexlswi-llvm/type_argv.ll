; fexl/type_argv.ll — argumentos y carga de librerias (antes type_argv.c).

%Item   = type { ptr, ptr }
%Record = type { i64, i64, ptr }

@QI        = external global ptr
@Qstd      = external global ptr
@main_argc = global i32 0
@main_argv = global ptr null

@Qdir_base = internal global ptr null
@Qdir_lib  = internal global ptr null

@.s_argv    = private constant [5 x i8]  c"argv\00"
@.s_dirbase = private constant [9 x i8] c"dir_base\00"
@.s_dirlib  = private constant [8 x i8]  c"dir_lib\00"
@.s_extend  = private constant [11 x i8] c"extend.fxl\00"
@.s_main    = private constant [9 x i8]  c"main.fxl\00"
@.s_libdir  = private constant [9 x i8]  c"src/lib/\00"
@.s_slash   = private constant [2 x i8]  c"/\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @A(ptr, ptr)
declare ptr  @Qstr(ptr)
declare ptr  @Qstr0(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare void @define(ptr, ptr)
declare ptr  @eval(ptr)
declare ptr  @str_concat(ptr, ptr)
declare ptr  @dirname(ptr)
declare ptr  @str_new_data0(ptr)
declare ptr  @record_copy(ptr)
declare ptr  @record_empty()
declare void @record_set(ptr, ptr, ptr)
declare void @record_fill(ptr, ptr)
declare ptr  @type_evaluate(ptr)
declare ptr  @type_parse_file(ptr)
declare ptr  @type_num(ptr)

define private ptr @type_argv(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_num
  br i1 %is, label %yes, label %void
yes:
  %dp = getelementptr %value, ptr %x, i32 0, i32 3
  %d = load double, ptr %dp
  %i = fptosi double %d to i64
  %argc32 = load i32, ptr @main_argc
  %argc = sext i32 %argc32 to i64
  %ge0 = icmp sge i64 %i, 0
  %ltargc = icmp slt i64 %i, %argc
  %in = and i1 %ge0, %ltargc
  br i1 %in, label %mk, label %void
mk:
  %argv = load ptr, ptr @main_argv
  %slot = getelementptr ptr, ptr %argv, i64 %i
  %s = load ptr, ptr %slot
  %res = call ptr @Qstr0(ptr %s)
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

@Qvoid = external global ptr

define private ptr @concat(ptr %x, ptr %y) {
entry:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %xs = load ptr, ptr %xvp
  %yvp = getelementptr %value, ptr %y, i32 0, i32 3
  %ys = load ptr, ptr %yvp
  %s = call ptr @str_concat(ptr %xs, ptr %ys)
  %res = call ptr @Qstr(ptr %s)
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %res
}

define private ptr @Qdirname(ptr %x) {
entry:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %vp
  %d = call ptr @dirname(ptr %s)
  %res = call ptr @Qstr(ptr %d)
  call void @drop(ptr %x)
  ret ptr %res
}

define private ptr @eval_file(ptr %name) {
entry:
  %qev = call ptr @Q(ptr @type_evaluate)
  %qpf = call ptr @Q(ptr @type_parse_file)
  %a1 = call ptr @A(ptr %qpf, ptr %name)
  %a2 = call ptr @A(ptr %qev, ptr %a1)
  %r = call ptr @eval(ptr %a2)
  ret ptr %r
}

define private void @use(ptr %name) {
entry:
  %r = call ptr @eval_file(ptr %name)
  call void @drop(ptr %r)
  ret void
}

define void @use_file(ptr %name) {
entry:
  %n = call ptr @Qstr0(ptr %name)
  call void @use(ptr %n)
  ret void
}

define private ptr @eval_lib(ptr %name) {
entry:
  %lib = load ptr, ptr @Qdir_lib
  %hl = call ptr @hold(ptr %lib)
  %n = call ptr @Qstr0(ptr %name)
  %path = call ptr @concat(ptr %hl, ptr %n)
  %r = call ptr @eval_file(ptr %path)
  ret ptr %r
}

define private void @import_record(ptr %cx) {
entry:
  %vp = getelementptr %value, ptr %cx, i32 0, i32 3
  %rec = load ptr, ptr %vp
  %cp = getelementptr %Record, ptr %rec, i32 0, i32 0
  %count = load i64, ptr %cp
  %vecp = getelementptr %Record, ptr %rec, i32 0, i32 2
  %vec = load ptr, ptr %vecp
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %cont = icmp ult i64 %i, %count
  br i1 %cont, label %body, label %done
body:
  %item = getelementptr %Item, ptr %vec, i64 %i
  %kp = getelementptr %Item, ptr %item, i32 0, i32 0
  %k = load ptr, ptr %kp
  %vp2 = getelementptr %Item, ptr %item, i32 0, i32 1
  %v = load ptr, ptr %vp2
  %hv = call ptr @hold(ptr %v)
  %std = load ptr, ptr @Qstd
  call void @record_set(ptr %std, ptr %k, ptr %hv)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

define ptr @type_load_extend(ptr %f) {
entry:
  %save = load ptr, ptr @Qstd
  %copy = call ptr @record_copy(ptr %save)
  store ptr %copy, ptr @Qstd
  %list = call ptr @eval_lib(ptr @.s_extend)
  %cx = call ptr @record_empty()
  call void @record_fill(ptr %cx, ptr %list)
  %cur = load ptr, ptr @Qstd
  call void @drop(ptr %cur)
  store ptr %save, ptr @Qstd
  call void @import_record(ptr %cx)
  call void @drop(ptr %cx)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define void @load_main() {
entry:
  %r = call ptr @eval_lib(ptr @.s_main)
  call void @drop(ptr %r)
  ret void
}

define ptr @type_load_argv(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_argv)
  call void @define(ptr @.s_argv, ptr %q0)
  %base = load ptr, ptr @Qdir_base
  %hb = call ptr @hold(ptr %base)
  call void @define(ptr @.s_dirbase, ptr %hb)
  %lib = load ptr, ptr @Qdir_lib
  %hl = call ptr @hold(ptr %lib)
  call void @define(ptr @.s_dirlib, ptr %hl)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define ptr @type_load_main(ptr %f) {
entry:
  call void @load_main()
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define void @beg_argv() {
entry:
  %argv = load ptr, ptr @main_argv
  %p0 = getelementptr ptr, ptr %argv, i64 0
  %s0 = load ptr, ptr %p0
  %q0 = call ptr @Qstr0(ptr %s0)
  %d1 = call ptr @Qdirname(ptr %q0)
  %d2 = call ptr @Qdirname(ptr %d1)
  %slash = call ptr @Qstr0(ptr @.s_slash)
  %base = call ptr @concat(ptr %d2, ptr %slash)
  store ptr %base, ptr @Qdir_base
  %lib = call ptr @Qstr0(ptr @.s_libdir)
  %hbase = call ptr @hold(ptr %base)
  %libpath = call ptr @concat(ptr %hbase, ptr %lib)
  store ptr %libpath, ptr @Qdir_lib
  ret void
}

define void @end_argv() {
entry:
  %base = load ptr, ptr @Qdir_base
  call void @drop(ptr %base)
  %lib = load ptr, ptr @Qdir_lib
  call void @drop(ptr %lib)
  ret void
}
