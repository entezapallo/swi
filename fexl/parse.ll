; fexl/parse.ll — parser de Fexl (antes src/parse.c).
; Produce arboles %value directamente. Las piezas que siguen en C (buf,
; stream, type_sym, type_num, type_str, report) se llaman con declare.
; value_types.ll se inyecta por concatenacion en el build.

%buffer = type { i64, i64, ptr }   ; len, size, data

@cur_label = global ptr null

@cur_ch   = external global i32
@cur_line = external global i64

@QI      = external global ptr
@Qnull   = external global ptr
@Qonce   = external global ptr
@Qtuple  = external global ptr

@.s_unclosed_str  = private constant [16 x i8] c"Unclosed string\00"
@.s_incomplete    = private constant [29 x i8] c"Incomplete string terminator\00"
@.s_unclosed_par  = private constant [21 x i8] c"Unclosed parenthesis\00"
@.s_unclosed_brace= private constant [15 x i8] c"Unclosed brace\00"
@.s_unclosed_brk  = private constant [17 x i8] c"Unclosed bracket\00"
@.s_missing_name  = private constant [23 x i8] c"Missing name after '\\'\00"
@.s_lambda_num    = private constant [31 x i8] c"Lambda name cannot be a number\00"
@.s_missing_def   = private constant [19 x i8] c"Missing definition\00"
@.s_missing_decl  = private constant [36 x i8] c"Missing name declaration before '='\00"
@.s_extraneous    = private constant [17 x i8] c"Extraneous input\00"

declare void @fatal_error(ptr, i64, ptr)
declare ptr  @str_data(ptr)
declare i32  @collect_to_ch(ptr, i8)
declare i32  @collect_tilde_string(ptr)
declare void @buf_keep(ptr)
declare ptr  @buf_clear(ptr)
declare void @buf_discard(ptr)
declare void @skip()
declare void @skip_filler()
declare void @str_free(ptr)

declare ptr @Qnum_str0(ptr)
declare ptr @Qstr(ptr)
declare ptr @ref(ptr, i64)
declare ptr @Qform(ptr, ptr)
declare ptr @quo(ptr)
declare ptr @join(ptr, ptr, ptr)
declare ptr @app(ptr, ptr)
declare ptr @lam(ptr, ptr, ptr)
declare ptr @pair(ptr, ptr)
declare ptr @hold(ptr)
declare void @drop(ptr)

declare ptr @type_quo(ptr)
declare ptr @type_list(ptr)
declare ptr @type_null(ptr)
declare ptr @type_tuple(ptr)
declare ptr @type_E(ptr)
declare ptr @type_D(ptr)

define private void @syntax_error(ptr %code, i64 %line) {
entry:
  %lab = load ptr, ptr @cur_label
  %txt = call ptr @str_data(ptr %lab)
  call void @fatal_error(ptr %code, i64 %line, ptr %txt)
  ret void
}

define private void @error_unclosed(i64 %line) {
entry:
  call void @syntax_error(ptr @.s_unclosed_str, i64 %line)
  ret void
}

; Parse un nombre, o null si no hay uno.
define private ptr @parse_name() {
entry:
  %buf = alloca %buffer, align 8
  store %buffer zeroinitializer, ptr %buf, align 8
  br label %loop
loop:
  %ch = load i32, ptr @cur_ch
  %gt = icmp sgt i32 %ch, 32
  %notbs = icmp ne i32 %ch, 92
  %notlp = icmp ne i32 %ch, 40
  %notrp = icmp ne i32 %ch, 41
  %notlb = icmp ne i32 %ch, 91
  %notrb = icmp ne i32 %ch, 93
  %notlc = icmp ne i32 %ch, 123
  %notrc = icmp ne i32 %ch, 125
  %notsc = icmp ne i32 %ch, 59
  %notqu = icmp ne i32 %ch, 34
  %notti = icmp ne i32 %ch, 126
  %nothash = icmp ne i32 %ch, 35
  %noteq = icmp ne i32 %ch, 61
  %a = and i1 %gt, %notbs
  %b = and i1 %a, %notlp
  %c = and i1 %b, %notrp
  %d = and i1 %c, %notlb
  %e = and i1 %d, %notrb
  %f = and i1 %e, %notlc
  %g = and i1 %f, %notrc
  %h = and i1 %g, %notsc
  %i = and i1 %h, %notqu
  %j = and i1 %i, %notti
  %k = and i1 %j, %nothash
  %ok = and i1 %k, %noteq
  br i1 %ok, label %body, label %done
body:
  call void @buf_keep(ptr %buf)
  br label %loop
done:
  %lenp = getelementptr %buffer, ptr %buf, i32 0, i32 0
  %len = load i64, ptr %lenp
  %empty = icmp eq i64 %len, 0
  br i1 %empty, label %none, label %some
none:
  ret ptr null
some:
  %s = call ptr @buf_clear(ptr %buf)
  ret ptr %s
}

define private ptr @parse_quote_string() {
entry:
  %first = load i64, ptr @cur_line
  %buf = alloca %buffer, align 8
  store %buffer zeroinitializer, ptr %buf, align 8
  call void @skip()
  %code = call i32 @collect_to_ch(ptr %buf, i32 34)
  %good = icmp eq i32 %code, 1
  br i1 %good, label %mk, label %bad
bad:
  call void @buf_discard(ptr %buf)
  call void @error_unclosed(i64 %first)
  unreachable
mk:
  %s = call ptr @buf_clear(ptr %buf)
  %q = call ptr @Qstr(ptr %s)
  %r = call ptr @quo(ptr %q)
  ret ptr %r
}

define private ptr @parse_tilde_string() {
entry:
  %first = load i64, ptr @cur_line
  %buf = alloca %buffer, align 8
  store %buffer zeroinitializer, ptr %buf, align 8
  %code = call i32 @collect_tilde_string(ptr %buf)
  %good = icmp eq i32 %code, 1
  br i1 %good, label %mk, label %bad
bad:
  call void @buf_discard(ptr %buf)
  %inc = icmp eq i32 %code, -1
  br i1 %inc, label %incomplete, label %unclosed
incomplete:
  call void @syntax_error(ptr @.s_incomplete, i64 %first)
  unreachable
unclosed:
  call void @error_unclosed(i64 %first)
  unreachable
mk:
  %s = call ptr @buf_clear(ptr %buf)
  %q = call ptr @Qstr(ptr %s)
  %r = call ptr @quo(ptr %q)
  ret ptr %r
}

define private ptr @parse_symbol() {
entry:
  %first = load i64, ptr @cur_line
  %name = call ptr @parse_name()
  %nonnull = icmp ne ptr %name, null
  br i1 %nonnull, label %body, label %none
none:
  ret ptr null
body:
  %dp = getelementptr i8, ptr %name, i64 8
  %n = call ptr @Qnum_str0(ptr %dp)
  %isnum = icmp ne ptr %n, null
  br i1 %isnum, label %number, label %symbol
number:
  call void @str_free(ptr %name)
  %q = call ptr @quo(ptr %n)
  ret ptr %q
symbol:
  %r2 = call ptr @ref(ptr %name, i64 %first)
  ret ptr %r2
}

define private ptr @parse_nested() {
entry:
  %first = load i64, ptr @cur_line
  call void @skip()
  %exp = call ptr @parse_exp()
  %ch = load i32, ptr @cur_ch
  %close = icmp eq i32 %ch, 41
  br i1 %close, label %ok, label %bad
bad:
  call void @syntax_error(ptr @.s_unclosed_par, i64 %first)
  unreachable
ok:
  call void @skip()
  ret ptr %exp
}

define private ptr @parse_items() {
entry:
  call void @skip_filler()
  %ch = load i32, ptr @cur_ch
  %issemi = icmp eq i32 %ch, 59
  br i1 %issemi, label %semibranch, label %termbranch
semibranch:
  call void @skip()
  %e = call ptr @parse_exp()
  ret ptr %e
termbranch:
  %term = call ptr @parse_term()
  %null = icmp eq ptr %term, null
  br i1 %null, label %empty, label %cons
empty:
  %qn = load ptr, ptr @Qnull
  %h = call ptr @hold(ptr %qn)
  %q = call ptr @quo(ptr %h)
  ret ptr %q
cons:
  %rest = call ptr @parse_items()
  %r = call ptr @join(ptr @type_list, ptr %term, ptr %rest)
  ret ptr %r
}

define private ptr @parse_seq(i32 %t_ch, ptr %msg) {
entry:
  %first = load i64, ptr @cur_line
  call void @skip()
  %exp = call ptr @parse_items()
  %ch = load i32, ptr @cur_ch
  %ok = icmp eq i32 %ch, %t_ch
  br i1 %ok, label %good, label %bad
bad:
  call void @syntax_error(ptr %msg, i64 %first)
  unreachable
good:
  call void @skip()
  ret ptr %exp
}

; see(p) = p->T == type_quo ? p->R : p
define private ptr @see(ptr %p) {
entry:
  %tp = getelementptr %value, ptr %p, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isquo = icmp eq ptr %t, @type_quo
  br i1 %isquo, label %yes, label %no
yes:
  %rp = getelementptr %value, ptr %p, i32 0, i32 3
  %r = load ptr, ptr %rp
  ret ptr %r
no:
  ret ptr %p
}

define private ptr @check_pair(ptr %list) {
entry:
  %p0 = call ptr @see(ptr %list)
  %t0p = getelementptr %value, ptr %p0, i32 0, i32 1
  %t0 = load ptr, ptr %t0p
  %islist0 = icmp eq ptr %t0, @type_list
  br i1 %islist0, label %second, label %no
second:
  %r0p = getelementptr %value, ptr %p0, i32 0, i32 3
  %r0 = load ptr, ptr %r0p
  %p1 = call ptr @see(ptr %r0)
  %t1p = getelementptr %value, ptr %p1, i32 0, i32 1
  %t1 = load ptr, ptr %t1p
  %islist1 = icmp eq ptr %t1, @type_list
  br i1 %islist1, label %third, label %no
third:
  %r1p = getelementptr %value, ptr %p1, i32 0, i32 3
  %r1 = load ptr, ptr %r1p
  %p2 = call ptr @see(ptr %r1)
  %t2p = getelementptr %value, ptr %p2, i32 0, i32 1
  %t2 = load ptr, ptr %t2p
  %isnull = icmp eq ptr %t2, @type_null
  br i1 %isnull, label %mkpair, label %no
mkpair:
  %l0p = getelementptr %value, ptr %p0, i32 0, i32 2
  %l0 = load ptr, ptr %l0p
  %x = call ptr @hold(ptr %l0)
  %l1p = getelementptr %value, ptr %p1, i32 0, i32 2
  %l1 = load ptr, ptr %l1p
  %y = call ptr @hold(ptr %l1)
  %ltp = getelementptr %value, ptr %list, i32 0, i32 1
  %lt = load ptr, ptr %ltp
  %isquo = icmp eq ptr %lt, @type_quo
  br i1 %isquo, label %bothquo, label %checkr
bothquo:
  %pr = call ptr @pair(ptr %x, ptr %y)
  %q = call ptr @quo(ptr %pr)
  ret ptr %q
checkr:
  %lr = getelementptr %value, ptr %list, i32 0, i32 3
  %r = load ptr, ptr %lr
  %rtp = getelementptr %value, ptr %r, i32 0, i32 1
  %rt = load ptr, ptr %rtp
  %rquo = icmp eq ptr %rt, @type_quo
  br i1 %rquo, label %quo_right, label %plain
quo_right:
  %qy = call ptr @quo(ptr %y)
  %pr2 = call ptr @pair(ptr %x, ptr %qy)
  ret ptr %pr2
plain:
  %pr3 = call ptr @pair(ptr %x, ptr %y)
  ret ptr %pr3
no:
  ret ptr null
}

define private ptr @parse_tuple() {
entry:
  %list = call ptr @parse_seq(i32 125, ptr @.s_unclosed_brace)
  %pair = call ptr @check_pair(ptr %list)
  %nonnull = icmp ne ptr %pair, null
  br i1 %nonnull, label %found, label %fallback
found:
  call void @drop(ptr %list)
  ret ptr %pair
fallback:
  %qt = load ptr, ptr @Qtuple
  %h = call ptr @hold(ptr %qt)
  %q = call ptr @quo(ptr %h)
  %r = call ptr @join(ptr @type_tuple, ptr %q, ptr %list)
  ret ptr %r
}

define private ptr @parse_list() {
entry:
  %r = call ptr @parse_seq(i32 93, ptr @.s_unclosed_brk)
  ret ptr %r
}

define private ptr @parse_term() {
entry:
  %ch = load i32, ptr @cur_ch
  switch i32 %ch, label %symbol [
    i32 40, label %nested
    i32 91, label %list
    i32 123, label %tuple
    i32 34, label %quote
    i32 126, label %tilde
  ]
nested:
  %a = call ptr @parse_nested()
  ret ptr %a
list:
  %b = call ptr @parse_list()
  ret ptr %b
tuple:
  %c = call ptr @parse_tuple()
  ret ptr %c
quote:
  %d = call ptr @parse_quote_string()
  ret ptr %d
tilde:
  %e = call ptr @parse_tilde_string()
  ret ptr %e
symbol:
  %f = call ptr @parse_symbol()
  ret ptr %f
}

; Parse un lambda tras el '\' inicial.
define private ptr @parse_lambda(i64 %first, ptr %ty) {
entry:
  %name = call ptr @parse_name()
  %nonnull = icmp ne ptr %name, null
  br i1 %nonnull, label %body, label %bad
bad:
  call void @syntax_error(ptr @.s_missing_name, i64 %first)
  unreachable
body:
  %dp = getelementptr i8, ptr %name, i64 8
  %n = call ptr @Qnum_str0(ptr %dp)
  %isnum = icmp ne ptr %n, null
  br i1 %isnum, label %badnum, label %skipf
badnum:
  call void @syntax_error(ptr @.s_lambda_num, i64 %first)
  unreachable
skipf:
  call void @skip_filler()
  %ch = load i32, ptr @cur_ch
  %iseq = icmp eq i32 %ch, 61
  br i1 %iseq, label %withdef, label %nodef
nodef:
  %exp = call ptr @parse_exp()
  %r = call ptr @lam(ptr %ty, ptr %name, ptr %exp)
  ret ptr %r
withdef:
  %first2 = load i64, ptr @cur_line
  call void @skip()
  call void @skip_filler()
  %def = call ptr @parse_term()
  %dn = icmp eq ptr %def, null
  br i1 %dn, label %baddef, label %mk
baddef:
  call void @syntax_error(ptr @.s_missing_def, i64 %first2)
  unreachable
mk:
  %exp2 = call ptr @parse_exp()
  %lm = call ptr @lam(ptr %ty, ptr %name, ptr %exp2)
  %app = call ptr @app(ptr %lm, ptr %def)
  ret ptr %app
}

define private ptr @parse_form() {
entry:
  %lab = load ptr, ptr @cur_label
  %h = call ptr @hold(ptr %lab)
  %exp = call ptr @parse_exp()
  %r = call ptr @Qform(ptr %h, ptr %exp)
  ret ptr %r
}

define private ptr @parse_factor() {
entry:
  call void @skip_filler()
  %ch = load i32, ptr @cur_ch
  %eof = icmp eq i32 %ch, -1
  br i1 %eof, label %none, label %dispatch
none:
  ret ptr null
dispatch:
  %isbs = icmp eq i32 %ch, 92
  %issemi = icmp eq i32 %ch, 59
  br i1 %isbs, label %backslash, label %semiorterm
semiorterm:
  br i1 %issemi, label %semibranch, label %termbranch
semibranch:
  call void @skip()
  %e = call ptr @parse_exp()
  ret ptr %e
termbranch:
  %f = call ptr @parse_term()
  %eq = load i32, ptr @cur_ch
  %iseq = icmp eq i32 %eq, 61
  br i1 %iseq, label %bad, label %ok
bad:
  %ln = load i64, ptr @cur_line
  call void @syntax_error(ptr @.s_missing_decl, i64 %ln)
  unreachable
ok:
  ret ptr %f
backslash:
  %first = load i64, ptr @cur_line
  call void @skip()
  %c2 = load i32, ptr @cur_ch
  %ishash = icmp eq i32 %c2, 35
  %issemi2 = icmp eq i32 %c2, 59
  %iseq2 = icmp eq i32 %c2, 61
  br i1 %ishash, label %hash, label %chk2
hash:
  store i32 -1, ptr @cur_ch
  ret ptr null
chk2:
  br i1 %issemi2, label %semiform, label %chk3
semiform:
  call void @skip()
  %fm = call ptr @parse_form()
  %q = call ptr @quo(ptr %fm)
  ret ptr %q
chk3:
  br i1 %iseq2, label %once, label %lambda
once:
  call void @skip()
  %qo = load ptr, ptr @Qonce
  %h = call ptr @hold(ptr %qo)
  %qq = call ptr @quo(ptr %h)
  %e2 = call ptr @parse_exp()
  %a = call ptr @app(ptr %qq, ptr %e2)
  ret ptr %a
lambda:
  %isbs2 = icmp eq i32 %c2, 92
  br i1 %isbs2, label %direct, label %eager
direct:
  call void @skip()
  br label %afterty
eager:
  br label %afterty
afterty:
  %ty = phi ptr [ @type_E, %eager ], [ @type_D, %direct ]
  call void @skip_filler()
  %r = call ptr @parse_lambda(i64 %first, ptr %ty)
  ret ptr %r
}

define private ptr @parse_exp() {
entry:
  %e = call ptr @parse_factor()
  %null = icmp eq ptr %e, null
  br i1 %null, label %empty, label %loop
empty:
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  %q = call ptr @quo(ptr %h)
  ret ptr %q
loop:
  %acc = phi ptr [ %e, %entry ], [ %next, %have ]
  %f = call ptr @parse_factor()
  %done = icmp eq ptr %f, null
  br i1 %done, label %ret, label %have
have:
  %next = call ptr @app(ptr %acc, ptr %f)
  br label %loop
ret:
  ret ptr %acc
}

define ptr @parse_top() {
entry:
  %exp = call ptr @parse_form()
  %ch = load i32, ptr @cur_ch
  %eof = icmp eq i32 %ch, -1
  br i1 %eof, label %ok, label %bad
bad:
  %ln = load i64, ptr @cur_line
  call void @syntax_error(ptr @.s_extraneous, i64 %ln)
  unreachable
ok:
  ret ptr %exp
}
