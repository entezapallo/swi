; fexl/show.ll — impresion de valores (antes src/show.c).

@Qstd  = external global ptr
@QI    = external global ptr
@Qonce = external global ptr

@max_depth = internal global i64 0
@max_call  = internal global i64 0
@done      = internal global i32 0

@t_Y        = internal global ptr null
@t_yield    = internal global ptr null
@t_concat   = internal global ptr null
@t_say      = internal global ptr null
@t_add      = internal global ptr null
@t_mul      = internal global ptr null
@t_evaluate = internal global ptr null

@.s_at        = private constant [2 x i8]  c"@\00"
@.s_yield     = private constant [6 x i8]  c"yield\00"
@.s_concat    = private constant [2 x i8]  c".\00"
@.s_say       = private constant [4 x i8]  c"say\00"
@.s_add       = private constant [2 x i8]  c"+\00"
@.s_mul       = private constant [2 x i8]  c"*\00"
@.s_evaluate  = private constant [9 x i8]  c"evaluate\00"
@.s_A         = private constant [2 x i8]  c"A\00"
@.s_num       = private constant [4 x i8]  c"num\00"
@.s_str       = private constant [4 x i8]  c"str\00"
@.s_form      = private constant [5 x i8]  c"form\00"
@.s_quo       = private constant [4 x i8]  c"quo\00"
@.s_ref       = private constant [4 x i8]  c"ref\00"
@.s_list      = private constant [5 x i8]  c"list\00"
@.s_D         = private constant [2 x i8]  c"D\00"
@.s_E         = private constant [2 x i8]  c"E\00"
@.s_void      = private constant [5 x i8]  c"void\00"
@.s_pair      = private constant [5 x i8]  c"pair\00"
@.s_null      = private constant [5 x i8]  c"null\00"
@.s_tuple     = private constant [6 x i8]  c"tuple\00"
@.s_T         = private constant [2 x i8]  c"T\00"
@.s_F         = private constant [2 x i8]  c"F\00"
@.s_I         = private constant [2 x i8]  c"I\00"
@.s_once      = private constant [5 x i8]  c"once\00"
@.s_Y         = private constant [2 x i8]  c"Y\00"
@.s_addname   = private constant [4 x i8]  c"add\00"
@.s_mulname   = private constant [4 x i8]  c"mul\00"
@.s_TYPE      = private constant [5 x i8]  c"TYPE\00"
@.s_DATA      = private constant [5 x i8]  c"DATA\00"
@.s_lbracket  = private constant [2 x i8]  c"[\00"
@.s_rbracket  = private constant [2 x i8]  c"]\00"
@.s_space     = private constant [2 x i8]  c" \00"
@.s_uscore    = private constant [2 x i8]  c"_\00"
@.s_quote     = private constant [2 x i8]  c"\22\00"

declare void @put(ptr)
declare void @put_ch(i8)
declare void @put_ulong(i64)
declare void @put_double(double)
declare void @put_str(ptr)
declare void @nl()
declare ptr  @Qstr0(ptr)
declare void @drop(ptr)
declare ptr @hold(ptr)
declare ptr  @record_find(ptr, ptr)
declare ptr  @type_num(ptr)
declare ptr  @type_str(ptr)
declare ptr  @type_form(ptr)
declare ptr  @type_quo(ptr)
declare ptr  @type_ref(ptr)
declare ptr  @type_list(ptr)
declare ptr  @type_D(ptr)
declare ptr  @type_E(ptr)
declare ptr  @type_void(ptr)
declare ptr  @type_pair(ptr)
declare ptr  @type_null(ptr)
declare ptr  @type_tuple(ptr)
declare ptr  @type_T(ptr)
declare ptr  @type_F(ptr)

@.once_t = internal global ptr null

define private ptr @type_name(ptr %t) {
entry:
  %is0 = icmp eq ptr %t, null
  br i1 %is0, label %A, label %c1
c1:
  %is1 = icmp eq ptr %t, @type_num
  br i1 %is1, label %num, label %c2
c2:
  %is2 = icmp eq ptr %t, @type_str
  br i1 %is2, label %str, label %c3
c3:
  %is3 = icmp eq ptr %t, @type_form
  br i1 %is3, label %form, label %c4
c4:
  %is4 = icmp eq ptr %t, @type_quo
  br i1 %is4, label %quo, label %c5
c5:
  %is5 = icmp eq ptr %t, @type_ref
  br i1 %is5, label %ref, label %c6
c6:
  %is6 = icmp eq ptr %t, @type_list
  br i1 %is6, label %list, label %c7
c7:
  %is7 = icmp eq ptr %t, @type_D
  br i1 %is7, label %D, label %c8
c8:
  %is8 = icmp eq ptr %t, @type_E
  br i1 %is8, label %E, label %c9
c9:
  %is9 = icmp eq ptr %t, @type_void
  br i1 %is9, label %void, label %c10
c10:
  %is10 = icmp eq ptr %t, @type_pair
  br i1 %is10, label %pair, label %c11
c11:
  %is11 = icmp eq ptr %t, @type_null
  br i1 %is11, label %null, label %c12
c12:
  %is12 = icmp eq ptr %t, @type_tuple
  br i1 %is12, label %tuple, label %c13
c13:
  %is13 = icmp eq ptr %t, @type_T
  br i1 %is13, label %T, label %c14
c14:
  %is14 = icmp eq ptr %t, @type_F
  br i1 %is14, label %F, label %c15
c15:
  %qi = load ptr, ptr @QI
  %qitp = getelementptr %value, ptr %qi, i32 0, i32 1
  %qit = load ptr, ptr %qitp
  %is15 = icmp eq ptr %t, %qit
  br i1 %is15, label %I, label %c16
c16:
  %g16 = load ptr, ptr @.once_t
  %is16 = icmp eq ptr %t, %g16
  br i1 %is16, label %once, label %c17
c17:
  %g17 = load ptr, ptr @t_Y
  %is17 = icmp eq ptr %t, %g17
  br i1 %is17, label %Y, label %c18
c18:
  %g18 = load ptr, ptr @t_yield
  %is18 = icmp eq ptr %t, %g18
  br i1 %is18, label %yield, label %c19
c19:
  %g19 = load ptr, ptr @t_concat
  %is19 = icmp eq ptr %t, %g19
  br i1 %is19, label %concat, label %c20
c20:
  %g20 = load ptr, ptr @t_say
  %is20 = icmp eq ptr %t, %g20
  br i1 %is20, label %say, label %c21
c21:
  %g21 = load ptr, ptr @t_add
  %is21 = icmp eq ptr %t, %g21
  br i1 %is21, label %addname, label %c22
c22:
  %g22 = load ptr, ptr @t_mul
  %is22 = icmp eq ptr %t, %g22
  br i1 %is22, label %mulname, label %TYPE
A:
  ret ptr @.s_A
num:
  ret ptr @.s_num
str:
  ret ptr @.s_str
form:
  ret ptr @.s_form
quo:
  ret ptr @.s_quo
ref:
  ret ptr @.s_ref
list:
  ret ptr @.s_list
D:
  ret ptr @.s_D
E:
  ret ptr @.s_E
void:
  ret ptr @.s_void
pair:
  ret ptr @.s_pair
null:
  ret ptr @.s_null
tuple:
  ret ptr @.s_tuple
T:
  ret ptr @.s_T
F:
  ret ptr @.s_F
I:
  ret ptr @.s_I
once:
  ret ptr @.s_once
Y:
  ret ptr @.s_Y
yield:
  ret ptr @.s_yield
concat:
  ret ptr @.s_concat
say:
  ret ptr @.s_say
addname:
  ret ptr @.s_addname
mulname:
  ret ptr @.s_mulname
TYPE:
  ret ptr @.s_TYPE
}

define private void @put_quote(ptr %x) {
entry:
  call void @put_ch(i8 34)
  call void @put_str(ptr %x)
  call void @put_ch(i8 34)
  ret void
}

define private void @put_data(ptr %f) {
entry:
  %tp = getelementptr %value, ptr %f, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isnum = icmp eq ptr %t, @type_num
  br i1 %isnum, label %num, label %cstr
num:
  %dp = getelementptr %value, ptr %f, i32 0, i32 3
  %d = load double, ptr %dp
  call void @put_double(double %d)
  ret void
cstr:
  %isstr = icmp eq ptr %t, @type_str
  br i1 %isstr, label %str, label %cquo
str:
  %vp = getelementptr %value, ptr %f, i32 0, i32 3
  %s = load ptr, ptr %vp
  call void @put_quote(ptr %s)
  ret void
cquo:
  %isquo = icmp eq ptr %t, @type_quo
  br i1 %isquo, label %quo, label %cref
quo:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %r = load ptr, ptr %rp
  call void @limit_show(ptr %r)
  ret void
cref:
  %isref = icmp eq ptr %t, @type_ref
  br i1 %isref, label %ref, label %data
ref:
  %rp2 = getelementptr %value, ptr %f, i32 0, i32 3
  %inner = load ptr, ptr %rp2
  %ivp = getelementptr %value, ptr %inner, i32 0, i32 3
  %rs = load ptr, ptr %ivp
  call void @put_quote(ptr %rs)
  ret void
data:
  call void @put(ptr @.s_DATA)
  ret void
}

define void @limit_show(ptr %f) {
entry:
  %calls = load i64, ptr @max_call
  %depth = load i64, ptr @max_depth
  %no = icmp eq i64 %calls, 0
  %no2 = icmp eq i64 %depth, 0
  %stop = or i1 %no, %no2
  br i1 %stop, label %under, label %body
under:
  call void @put_ch(i8 95)
  ret void
body:
  %c1 = sub i64 %calls, 1
  store i64 %c1, ptr @max_call
  %d1 = sub i64 %depth, 1
  store i64 %d1, ptr @max_depth
  call void @put_ch(i8 91)
  %tp = getelementptr %value, ptr %f, i32 0, i32 1
  %t = load ptr, ptr %tp
  %nm = call ptr @type_name(ptr %t)
  call void @put(ptr %nm)
  %lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %lp
  %hasL = icmp ne ptr %L, null
  br i1 %hasL, label %showL, label %close
showL:
  call void @put_ch(i8 32)
  %lnp = getelementptr %value, ptr %L, i32 0, i32 0
  %LN = load i64, ptr %lnp
  %tree = icmp ne i64 %LN, 0
  br i1 %tree, label %showtree, label %showdata
showdata:
  call void @put_data(ptr %f)
  br label %close
showtree:
  %isform = icmp eq ptr %t, @type_form
  br i1 %isform, label %showR, label %showLR
showLR:
  call void @limit_show(ptr %L)
  call void @put_ch(i8 32)
  br label %showR
showR:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %R = load ptr, ptr %rp
  call void @limit_show(ptr %R)
  br label %close
close:
  call void @put_ch(i8 93)
  %d2 = add i64 %d1, 1
  store i64 %d2, ptr @max_depth
  ret void
}

define void @show_exp(ptr %f) {
entry:
  store i64 12, ptr @max_depth
  store i64 200, ptr @max_call
  call void @limit_show(ptr %f)
  ret void
}

define void @show(ptr %name, ptr %f) {
entry:
  call void @put(ptr %name)
  call void @show_exp(ptr %f)
  call void @nl()
  ret void
}

define private ptr @get_type(ptr %name) {
entry:
  %key = call ptr @Qstr0(ptr %name)
  %std = load ptr, ptr @Qstd
  %val = call ptr @record_find(ptr %std, ptr %key)
  call void @drop(ptr %key)
  %none = icmp eq ptr %val, null
  br i1 %none, label %zero, label %found
found:
  %tp = getelementptr %value, ptr %val, i32 0, i32 1
  %t = load ptr, ptr %tp
  ret ptr %t
zero:
  ret ptr null
}

define ptr @type_show(ptr %f) {
entry:
  %d = load i32, ptr @done
  %first = icmp eq i32 %d, 0
  br i1 %first, label %init, label %print
init:
  store i32 1, ptr @done
  %a = call ptr @get_type(ptr @.s_at)
  store ptr %a, ptr @t_Y
  %b = call ptr @get_type(ptr @.s_yield)
  store ptr %b, ptr @t_yield
  %c = call ptr @get_type(ptr @.s_concat)
  store ptr %c, ptr @t_concat
  %d2 = call ptr @get_type(ptr @.s_say)
  store ptr %d2, ptr @t_say
  %e = call ptr @get_type(ptr @.s_add)
  store ptr %e, ptr @t_add
  %g = call ptr @get_type(ptr @.s_mul)
  store ptr %g, ptr @t_mul
  %h = call ptr @get_type(ptr @.s_evaluate)
  store ptr %h, ptr @t_evaluate
  %qonce = load ptr, ptr @Qonce
  %qotp = getelementptr %value, ptr %qonce, i32 0, i32 1
  %qot = load ptr, ptr %qotp
  store ptr %qot, ptr @.once_t
  br label %print
print:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %x = load ptr, ptr %rp
  call void @show_exp(ptr %x)
  call void @nl()
  %qi = load ptr, ptr @QI
  %hres = call ptr @hold(ptr %qi)
  ret ptr %hres
}
