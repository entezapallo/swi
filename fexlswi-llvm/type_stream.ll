; fexl/type_stream.ll — primitivas del stream de parseo (antes type_stream.c).

@QI      = external global ptr
@Qvoid   = external global ptr
@cur_ch  = external global i32
@cur_line = external global i64

@.s_at_eof      = private constant [7 x i8] c"at_eof\00"
@.s_at_white    = private constant [9 x i8] c"at_white\00"
@.s_skip_white  = private constant [11 x i8] c"skip_white\00"
@.s_at_eol      = private constant [7 x i8] c"at_eol\00"
@.s_at_ch       = private constant [6 x i8] c"at_ch\00"
@.s_look        = private constant [5 x i8] c"look\00"
@.s_skip        = private constant [5 x i8] c"skip\00"
@.s_line        = private constant [5 x i8] c"line\00"
@.s_buf_keep    = private constant [9 x i8] c"buf_keep\00"
@.s_collect_ch  = private constant [14 x i8] c"collect_to_ch\00"
@.s_collect_tilde = private constant [21 x i8] c"collect_tilde_string\00"
@.s_read_stream = private constant [12 x i8] c"read_stream\00"

declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @boolean(i32)
declare ptr  @arg(ptr)
declare ptr  @Qstr(ptr)
declare ptr  @Qnum(double)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare void @define(ptr, ptr)
declare ptr  @str_data(ptr)
declare ptr  @str_new_data(ptr, i64)
declare i32  @at_white()
declare void @skip_white()
declare void @skip()
declare i32  @collect_to_ch(ptr, i8)
declare i32  @collect_tilde_string(ptr)
declare void @buf_keep(ptr)
declare ptr  @type_str(ptr)
declare ptr  @type_buf(ptr)
declare ptr  @type_read_stream(ptr)

define private ptr @type_at_eof(ptr %f) {
entry:
  %ch = load i32, ptr @cur_ch
  %eof = icmp eq i32 %ch, -1
  %ci = zext i1 %eof to i32
  %r = call ptr @boolean(i32 %ci)
  ret ptr %r
}

define private ptr @type_at_white(ptr %f) {
entry:
  %w = call i32 @at_white()
  %r = call ptr @boolean(i32 %w)
  ret ptr %r
}

define private ptr @type_skip_white(ptr %f) {
entry:
  call void @skip_white()
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define private ptr @type_at_eol(ptr %f) {
entry:
  %ch = load i32, ptr @cur_ch
  %nl = icmp eq i32 %ch, 10
  %cr = icmp eq i32 %ch, 13
  %eol = or i1 %nl, %cr
  %ci = zext i1 %eol to i32
  %r = call ptr @boolean(i32 %ci)
  ret ptr %r
}

define private ptr @type_at_ch(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %x = load ptr, ptr %rp
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %d = call ptr @str_data(ptr %x)
  %want = load i8, ptr %d
  %ch = load i32, ptr @cur_ch
  %want32 = sext i8 %want to i32
  %same = icmp eq i32 %ch, %want32
  %ci = zext i1 %same to i32
  %res = call ptr @boolean(i32 %ci)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  ret ptr %r
}

define private ptr @type_look(ptr %f) {
entry:
  %ch = load i32, ptr @cur_ch
  %neg = icmp slt i32 %ch, 0
  br i1 %neg, label %void, label %mk
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
  ret ptr %r
}

define private ptr @type_skip(ptr %f) {
entry:
  call void @skip()
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define private ptr @type_line(ptr %f) {
entry:
  %n = load i64, ptr @cur_line
  %d = sitofp i64 %n to double
  %r = call ptr @Qnum(double %d)
  ret ptr %r
}

define private ptr @type_buf_keep(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_buf
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %buf = load ptr, ptr %vp
  call void @buf_keep(ptr %buf)
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
  ret ptr %r
}

define private ptr @type_collect_to_ch(ptr %f) {
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
  %d = call ptr @str_data(ptr %y)
  %ch = load i8, ptr %d
  %resi = call i32 @collect_to_ch(ptr %buf, i8 %ch)
  %res = call ptr @boolean(i32 %resi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_collect_tilde_string(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_buf
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %buf = load ptr, ptr %vp
  %n = call i32 @collect_tilde_string(ptr %buf)
  %d = sitofp i32 %n to double
  %res = call ptr @Qnum(double %d)
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

define ptr @type_load_stream(ptr %f) {
entry:
  %q0 = call ptr @Q0(ptr @type_at_eof)
  call void @define(ptr @.s_at_eof, ptr %q0)
  %q1 = call ptr @Q0(ptr @type_at_white)
  call void @define(ptr @.s_at_white, ptr %q1)
  %q2 = call ptr @Q0(ptr @type_skip_white)
  call void @define(ptr @.s_skip_white, ptr %q2)
  %q3 = call ptr @Q0(ptr @type_at_eol)
  call void @define(ptr @.s_at_eol, ptr %q3)
  %q4 = call ptr @Q(ptr @type_at_ch)
  call void @define(ptr @.s_at_ch, ptr %q4)
  %q5 = call ptr @Q0(ptr @type_look)
  call void @define(ptr @.s_look, ptr %q5)
  %q6 = call ptr @Q0(ptr @type_skip)
  call void @define(ptr @.s_skip, ptr %q6)
  %q7 = call ptr @Q0(ptr @type_line)
  call void @define(ptr @.s_line, ptr %q7)
  %q8 = call ptr @Q(ptr @type_buf_keep)
  call void @define(ptr @.s_buf_keep, ptr %q8)
  %q9 = call ptr @Q(ptr @type_collect_to_ch)
  call void @define(ptr @.s_collect_ch, ptr %q9)
  %q10 = call ptr @Q(ptr @type_collect_tilde_string)
  call void @define(ptr @.s_collect_tilde, ptr %q10)
  %q11 = call ptr @Q(ptr @type_read_stream)
  call void @define(ptr @.s_read_stream, ptr %q11)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
