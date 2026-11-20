; fexl/test.ll — builtins de prueba (antes src/test.c).

@QI = external global ptr

@.s_test_argv = private constant [10 x i8] c"test_argv\00"
@.s_show      = private constant [5 x i8] c"show\00"

declare ptr  @Q(ptr)
declare ptr  @hold(ptr)
declare void @define(ptr, ptr)
declare void @put(ptr)
declare void @nl()
declare void @put_ulong(i64)
declare ptr  @op_argv(ptr, ptr)
declare ptr  @type_show(ptr)

define private ptr @test_argv(ptr %argv) {
entry:
  call void @put(ptr @.s_hdr)
  call void @nl()
  call void @put(ptr @.s_bracket)
  call void @nl()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %slot = getelementptr ptr, ptr %argv, i64 %i
  %s = load ptr, ptr %slot
  %nonnull = icmp ne ptr %s, null
  br i1 %nonnull, label %body, label %done
body:
  call void @put_ulong(i64 %i)
  call void @put(ptr @.s_sep)
  call void @put(ptr %s)
  call void @nl()
  %i1 = add i64 %i, 1
  br label %loop
done:
  call void @put(ptr @.s_bracket_close)
  call void @nl()
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define private ptr @type_test_argv(ptr %f) {
entry:
  %r = call ptr @op_argv(ptr %f, ptr @test_argv)
  ret ptr %r
}

define ptr @type_load_test(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_test_argv)
  call void @define(ptr @.s_test_argv, ptr %q0)
  %q1 = call ptr @Q(ptr @type_show)
  call void @define(ptr @.s_show, ptr %q1)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

@.s_hdr     = private constant [12 x i8] c"= test_argv\00"
@.s_bracket = private constant [2 x i8] c"[\00"
@.s_bracket_close = private constant [2 x i8] c"]\00"
@.s_sep     = private constant [4 x i8] c" : \00"
