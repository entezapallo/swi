; fexl/fexl.ll — driver del interprete (antes src/fexl.c).
; value_types.ll se inyecta por concatenacion en el build.

@main_argc = external global i32
@main_argv = external global ptr

@.s_evaluate     = private constant [9 x i8]  c"evaluate\00"
@.s_load_argv    = private constant [10 x i8] c"load_argv\00"
@.s_load_basic   = private constant [11 x i8] c"load_basic\00"
@.s_load_bn      = private constant [8 x i8]  c"load_bn\00"
@.s_load_buf     = private constant [9 x i8] c"load_buf\00"
@.s_load_cmp     = private constant [9 x i8] c"load_cmp\00"
@.s_load_crypto  = private constant [12 x i8] c"load_crypto\00"
@.s_load_extend  = private constant [12 x i8] c"load_extend\00"
@.s_load_fexl    = private constant [10 x i8] c"load_fexl\00"
@.s_load_file    = private constant [10 x i8] c"load_file\00"
@.s_load_hex     = private constant [9 x i8] c"load_hex\00"
@.s_load_istr    = private constant [10 x i8] c"load_istr\00"
@.s_load_limit   = private constant [11 x i8] c"load_limit\00"
@.s_load_main    = private constant [10 x i8] c"load_main\00"
@.s_load_math    = private constant [10 x i8] c"load_math\00"
@.s_load_num     = private constant [9 x i8] c"load_num\00"
@.s_load_output  = private constant [12 x i8] c"load_output\00"
@.s_load_parse   = private constant [11 x i8] c"load_parse\00"
@.s_load_rand    = private constant [10 x i8] c"load_rand\00"
@.s_load_record  = private constant [12 x i8] c"load_record\00"
@.s_load_regex   = private constant [11 x i8] c"load_regex\00"
@.s_load_script  = private constant [12 x i8] c"load_script\00"
@.s_load_run     = private constant [9 x i8] c"load_run\00"
@.s_load_signal  = private constant [12 x i8] c"load_signal\00"
@.s_load_str     = private constant [9 x i8] c"load_str\00"
@.s_load_stream  = private constant [12 x i8] c"load_stream\00"
@.s_load_sym     = private constant [9 x i8] c"load_sym\00"
@.s_load_test    = private constant [10 x i8] c"load_test\00"
@.s_load_time    = private constant [10 x i8] c"load_time\00"
@.s_load_tuple   = private constant [11 x i8] c"load_tuple\00"
@.s_load_var     = private constant [9 x i8] c"load_var\00"
@.s_aot          = private constant [9 x i8] c"aot_eval\00"

declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare void @define(ptr, ptr)
declare void @beg_argv()
declare void @beg_basic()
declare void @beg_crypto()
declare void @beg_file()
declare void @beg_output()
declare void @beg_signal()
declare void @beg_sym()
declare void @beg_tuple()
declare void @end_argv()
declare void @end_basic()
declare void @end_crypto()
declare void @end_file()
declare void @end_output()
declare void @end_signal()
declare void @end_sym()
declare void @end_tuple()
declare void @load_main()
declare void @use_file(ptr)
declare void @end_value()
declare i64  @strlen(ptr)

declare ptr @type_evaluate(ptr)
declare ptr @type_load_argv(ptr)
declare ptr @type_load_basic(ptr)
declare ptr @type_load_bn(ptr)
declare ptr @type_load_buf(ptr)
declare ptr @type_load_cmp(ptr)
declare ptr @type_load_crypto(ptr)
declare ptr @type_load_extend(ptr)
declare ptr @type_load_fexl(ptr)
declare ptr @type_load_file(ptr)
declare ptr @type_load_hex(ptr)
declare ptr @type_load_istr(ptr)
declare ptr @type_load_limit(ptr)
declare ptr @type_load_main(ptr)
declare ptr @type_load_math(ptr)
declare ptr @type_load_num(ptr)
declare ptr @type_load_output(ptr)
declare ptr @type_load_parse(ptr)
declare ptr @type_load_rand(ptr)
declare ptr @type_load_record(ptr)
declare ptr @type_load_regex(ptr)
declare ptr @type_load_script(ptr)
declare ptr @type_load_run(ptr)
declare ptr @type_load_signal(ptr)
declare ptr @type_load_str(ptr)
declare ptr @type_load_stream(ptr)
declare ptr @type_load_sym(ptr)
declare ptr @type_load_test(ptr)
declare ptr @type_load_time(ptr)
declare ptr @type_load_tuple(ptr)
declare ptr @type_load_var(ptr)
declare ptr @aot_eval(ptr)

define private void @beg_const() {
entry:
  call void @beg_argv()
  call void @beg_basic()
  call void @beg_crypto()
  call void @beg_file()
  call void @beg_output()
  call void @beg_signal()
  call void @beg_sym()
  call void @beg_tuple()
  ret void
}

define private void @end_const() {
entry:
  call void @end_argv()
  call void @end_basic()
  call void @end_crypto()
  call void @end_file()
  call void @end_output()
  call void @end_signal()
  call void @end_sym()
  call void @end_tuple()
  ret void
}

define private void @load_core() {
entry:
  %q0 = call ptr @Q(ptr @type_evaluate)
  call void @define(ptr @.s_evaluate, ptr %q0)
  %q1 = call ptr @Q0(ptr @type_load_argv)
  call void @define(ptr @.s_load_argv, ptr %q1)
  %q2 = call ptr @Q0(ptr @type_load_basic)
  call void @define(ptr @.s_load_basic, ptr %q2)
  %q3 = call ptr @Q0(ptr @type_load_bn)
  call void @define(ptr @.s_load_bn, ptr %q3)
  %q4 = call ptr @Q0(ptr @type_load_buf)
  call void @define(ptr @.s_load_buf, ptr %q4)
  %q5 = call ptr @Q0(ptr @type_load_cmp)
  call void @define(ptr @.s_load_cmp, ptr %q5)
  %q6 = call ptr @Q0(ptr @type_load_crypto)
  call void @define(ptr @.s_load_crypto, ptr %q6)
  %q7 = call ptr @Q0(ptr @type_load_extend)
  call void @define(ptr @.s_load_extend, ptr %q7)
  %q8 = call ptr @Q0(ptr @type_load_fexl)
  call void @define(ptr @.s_load_fexl, ptr %q8)
  %q9 = call ptr @Q0(ptr @type_load_file)
  call void @define(ptr @.s_load_file, ptr %q9)
  %q10 = call ptr @Q0(ptr @type_load_hex)
  call void @define(ptr @.s_load_hex, ptr %q10)
  %q11 = call ptr @Q0(ptr @type_load_istr)
  call void @define(ptr @.s_load_istr, ptr %q11)
  %q12 = call ptr @Q0(ptr @type_load_limit)
  call void @define(ptr @.s_load_limit, ptr %q12)
  %q13 = call ptr @Q0(ptr @type_load_main)
  call void @define(ptr @.s_load_main, ptr %q13)
  %q14 = call ptr @Q0(ptr @type_load_math)
  call void @define(ptr @.s_load_math, ptr %q14)
  %q15 = call ptr @Q0(ptr @type_load_num)
  call void @define(ptr @.s_load_num, ptr %q15)
  %q16 = call ptr @Q0(ptr @type_load_output)
  call void @define(ptr @.s_load_output, ptr %q16)
  %q17 = call ptr @Q0(ptr @type_load_parse)
  call void @define(ptr @.s_load_parse, ptr %q17)
  %q18 = call ptr @Q0(ptr @type_load_rand)
  call void @define(ptr @.s_load_rand, ptr %q18)
  %q19 = call ptr @Q0(ptr @type_load_record)
  call void @define(ptr @.s_load_record, ptr %q19)
  %q20 = call ptr @Q0(ptr @type_load_regex)
  call void @define(ptr @.s_load_regex, ptr %q20)
  %q21 = call ptr @Q0(ptr @type_load_script)
  call void @define(ptr @.s_load_script, ptr %q21)
  %q22 = call ptr @Q0(ptr @type_load_run)
  call void @define(ptr @.s_load_run, ptr %q22)
  %q23 = call ptr @Q0(ptr @type_load_signal)
  call void @define(ptr @.s_load_signal, ptr %q23)
  %q24 = call ptr @Q0(ptr @type_load_str)
  call void @define(ptr @.s_load_str, ptr %q24)
  %q25 = call ptr @Q0(ptr @type_load_stream)
  call void @define(ptr @.s_load_stream, ptr %q25)
  %q26 = call ptr @Q0(ptr @type_load_sym)
  call void @define(ptr @.s_load_sym, ptr %q26)
  %q27 = call ptr @Q0(ptr @type_load_test)
  call void @define(ptr @.s_load_test, ptr %q27)
  %q28 = call ptr @Q0(ptr @type_load_time)
  call void @define(ptr @.s_load_time, ptr %q28)
  %q29 = call ptr @Q0(ptr @type_load_tuple)
  call void @define(ptr @.s_load_tuple, ptr %q29)
  %q30 = call ptr @Q0(ptr @type_load_var)
  call void @define(ptr @.s_load_var, ptr %q30)
  %qa = call ptr @Q(ptr @aot_eval)
  call void @define(ptr @.s_aot, ptr %qa)
  ret void
}

define private void @eval_script() {
entry:
  %argv = load ptr, ptr @main_argv
  %p0 = getelementptr ptr, ptr %argv, i64 0
  %path = load ptr, ptr %p0
  %len = call i64 @strlen(ptr %path)
  %zero = icmp eq i64 %len, 0
  br i1 %zero, label %noch, label %last
last:
  %im1 = sub i64 %len, 1
  %lastp = getelementptr i8, ptr %path, i64 %im1
  %ch = load i8, ptr %lastp
  br label %loaded
noch:
  br label %loaded
loaded:
  %c = phi i8 [ %ch, %last ], [ 0, %noch ]
  call void @load_core()
  %iszero = icmp eq i8 %c, 0
  br i1 %iszero, label %domain, label %check0
check0:
  %is0char = icmp eq i8 %c, 48
  br i1 %is0char, label %done, label %domain
domain:
  call void @load_main()
  br label %done
done:
  %argc = load i32, ptr @main_argc
  %gt1 = icmp sgt i32 %argc, 1
  br i1 %gt1, label %arg1, label %empty
arg1:
  %p1 = getelementptr ptr, ptr %argv, i64 1
  %s = load ptr, ptr %p1
  br label %use
empty:
  br label %use
use:
  %name = phi ptr [ %s, %arg1 ], [ @.empty, %empty ]
  call void @use_file(ptr %name)
  ret void
}

@.empty = private constant [1 x i8] c"\00"

define i32 @fexl_main(i32 %argc, ptr %argv) {
entry:
  store i32 %argc, ptr @main_argc
  store ptr %argv, ptr @main_argv
  call void @beg_const()
  call void @eval_script()
  call void @end_const()
  call void @end_value()
  ret i32 0
}
