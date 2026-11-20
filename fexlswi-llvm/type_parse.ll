; fexl/type_parse.ll — entry points de parseo (antes src/type_parse.c).

%Istr        = type { i64, ptr }
%StreamState = type { i32, i64, ptr, ptr }

@QI        = external global ptr
@Qvoid     = external global ptr
@cur_label = external global ptr
@stdin     = external global ptr

@.s_parse      = private constant [6 x i8] c"parse\00"
@.s_parse_file = private constant [11 x i8] c"parse_file\00"
@.s_mode_r     = private constant [2 x i8] c"r\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare void @define(ptr, ptr)
declare ptr  @eval(ptr)
declare ptr  @parse_top()
declare void @beg_stream(ptr, ptr, ptr)
declare void @end_stream(ptr)
declare i32  @fgetc(ptr)
declare i32  @sgetc(ptr)
declare ptr  @fopen(ptr, ptr)
declare void @bad_name(ptr, ptr)
declare ptr  @Qfile(ptr)
declare ptr  @str_data(ptr)
declare ptr  @type_file(ptr)
declare ptr  @type_istr(ptr)
declare ptr  @type_str(ptr)

define private ptr @read_input(ptr %get, ptr %source, ptr %read) {
entry:
  %state = alloca %StreamState, align 8
  call void @beg_stream(ptr %state, ptr %get, ptr %source)
  %exp = call ptr @eval(ptr %read)
  call void @end_stream(ptr %state)
  ret ptr %exp
}

define private ptr @read_stream(ptr %stream, ptr %read) {
entry:
  %tp = getelementptr %value, ptr %stream, i32 0, i32 1
  %t = load ptr, ptr %tp
  %isf = icmp eq ptr %t, @type_file
  br i1 %isf, label %file, label %checkistr
file:
  %vp = getelementptr %value, ptr %stream, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %r = call ptr @read_input(ptr @fgetc, ptr %fh, ptr %read)
  ret ptr %r
checkistr:
  %isi = icmp eq ptr %t, @type_istr
  br i1 %isi, label %istr, label %checkstr
istr:
  %vpi = getelementptr %value, ptr %stream, i32 0, i32 3
  %in = load ptr, ptr %vpi
  %r2 = call ptr @read_input(ptr @sgetc, ptr %in, ptr %read)
  ret ptr %r2
checkstr:
  %iss = icmp eq ptr %t, @type_str
  br i1 %iss, label %strcase, label %bad
strcase:
  %local = alloca %Istr, align 8
  %pp = getelementptr %Istr, ptr %local, i32 0, i32 0
  store i64 0, ptr %pp
  %sp = getelementptr %Istr, ptr %local, i32 0, i32 1
  store ptr %stream, ptr %sp
  %r3 = call ptr @read_input(ptr @sgetc, ptr %local, ptr %read)
  ret ptr %r3
bad:
  call void @drop(ptr %read)
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  ret ptr %h
}

define private ptr @type_parse_top(ptr %f) {
entry:
  %r = call ptr @parse_top()
  ret ptr %r
}

define private ptr @parse(ptr %stream, ptr %name) {
entry:
  %old = load ptr, ptr @cur_label
  store ptr %name, ptr @cur_label
  %read = call ptr @Q0(ptr @type_parse_top)
  %exp = call ptr @read_stream(ptr %stream, ptr %read)
  store ptr %old, ptr @cur_label
  call void @drop(ptr %stream)
  ret ptr %exp
}

define private ptr @open_file(ptr %name) {
entry:
  %fh = call ptr @fopen(ptr %name, ptr @.s_mode_r)
  %isnull = icmp eq ptr %fh, null
  br i1 %isnull, label %bad, label %ok
bad:
  call void @bad_name(ptr @.s_could_not_open, ptr %name)
  unreachable
ok:
  ret ptr %fh
}

define ptr @type_parse_file(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %name = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %name, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %name)
  %first = load i8, ptr %s
  %nonempty = icmp ne i8 %first, 0
  br i1 %nonempty, label %openit, label %usestdin
openit:
  %fh = call ptr @open_file(ptr %s)
  br label %mkstream
usestdin:
  %fh2 = load ptr, ptr @stdin
  br label %mkstream
mkstream:
  %fp = phi ptr [ %fh, %openit ], [ %fh2, %usestdin ]
  %stream = call ptr @Qfile(ptr %fp)
  %res = call ptr @parse(ptr %stream, ptr %name)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %mkstream ], [ %h, %void ]
  call void @drop(ptr %name)
  ret ptr %r
}

define private ptr @type_parse(ptr %f) {
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
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %narg = load ptr, ptr %rp
  %name = call ptr @arg(ptr %narg)
  %ntp = getelementptr %value, ptr %name, i32 0, i32 1
  %nt = load ptr, ptr %ntp
  %is = icmp eq ptr %nt, @type_str
  br i1 %is, label %yes, label %void
yes:
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %sarg = load ptr, ptr %LRp
  %stream = call ptr @arg(ptr %sarg)
  %res = call ptr @parse(ptr %stream, ptr %name)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %name)
  ret ptr %r
}

define ptr @type_read_stream(ptr %f) {
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
  %sarg = load ptr, ptr %LRp
  %stream = call ptr @arg(ptr %sarg)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %read = call ptr @hold(ptr %rp)
  %res = call ptr @read_stream(ptr %stream, ptr %read)
  call void @drop(ptr %stream)
  ret ptr %res
}

define ptr @type_load_parse(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_parse)
  call void @define(ptr @.s_parse, ptr %q0)
  %q1 = call ptr @Q(ptr @type_parse_file)
  call void @define(ptr @.s_parse_file, ptr %q1)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

@.s_could_not_open = private constant [28 x i8] c"Could not open source file \00"
