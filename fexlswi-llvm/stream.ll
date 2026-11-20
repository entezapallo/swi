; fexl/stream.ll — estado del stream de parseo (antes src/stream.c).

%StreamState = type { i32, i64, ptr, ptr }

@cur_ch     = global i32 -1
@cur_line   = global i64 1
@cur_get    = global ptr @empty
@cur_source = global ptr null

declare void @buf_add(ptr, i8)
declare void @buf_addn(ptr, ptr, i64)
declare ptr  @buf_clear(ptr)
declare void @str_free(ptr)

@.nl = private constant [2 x i8] c"\0a\00"
@.hash = private constant [2 x i8] c"#\00"

define private i32 @empty(ptr %source) {
entry:
  ret i32 -1
}

define void @skip() {
entry:
  %get = load ptr, ptr @cur_get
  %src = load ptr, ptr @cur_source
  %ch = call i32 %get(ptr %src)
  store i32 %ch, ptr @cur_ch
  %isnl = icmp eq i32 %ch, 10
  br i1 %isnl, label %incline, label %done
incline:
  %line = load i64, ptr @cur_line
  %line1 = add i64 %line, 1
  store i64 %line1, ptr @cur_line
  br label %done
done:
  ret void
}

define i32 @at_white() {
entry:
  %ch = load i32, ptr @cur_ch
  %le = icmp sle i32 %ch, 32
  %eof = icmp ne i32 %ch, -1
  %white = and i1 %le, %eof
  %r = zext i1 %white to i32
  ret i32 %r
}

define void @skip_white() {
entry:
  br label %loop
loop:
  %w = call i32 @at_white()
  %yes = icmp ne i32 %w, 0
  br i1 %yes, label %body, label %done
body:
  call void @skip()
  br label %loop
done:
  ret void
}

define void @buf_keep(ptr %buf) {
entry:
  %ch = load i32, ptr @cur_ch
  %c = trunc i32 %ch to i8
  call void @buf_add(ptr %buf, i8 %c)
  call void @skip()
  ret void
}

define private void @skip_line() {
entry:
  br label %loop
loop:
  %ch = load i32, ptr @cur_ch
  %nl = icmp eq i32 %ch, 10
  %eof = icmp eq i32 %ch, -1
  %stop = or i1 %nl, %eof
  br i1 %stop, label %done, label %body
body:
  call void @skip()
  br label %loop
done:
  ret void
}

define void @skip_filler() {
entry:
  br label %loop
loop:
  %w = call i32 @at_white()
  %yes = icmp ne i32 %w, 0
  br i1 %yes, label %white, label %checkhash
white:
  call void @skip()
  br label %loop
checkhash:
  %ch = load i32, ptr @cur_ch
  %ishash = icmp eq i32 %ch, 35
  br i1 %ishash, label %comment, label %done
comment:
  call void @skip_line()
  br label %loop
done:
  ret void
}

define i32 @collect_to_white(ptr %buf) {
entry:
  br label %loop
loop:
  %ch = load i32, ptr @cur_ch
  %gt = icmp sgt i32 %ch, 32
  br i1 %gt, label %body, label %check
body:
  call void @buf_keep(ptr %buf)
  br label %loop
check:
  %eof = icmp eq i32 %ch, -1
  br i1 %eof, label %no, label %yes
no:
  ret i32 0
yes:
  call void @skip()
  ret i32 1
}

define i32 @collect_to_ch(ptr %buf, i8 %t_ch) {
entry:
  br label %loop
loop:
  %ch = load i32, ptr @cur_ch
  %want = sext i8 %t_ch to i32
  %match = icmp eq i32 %ch, %want
  br i1 %match, label %yes, label %check
yes:
  call void @skip()
  ret i32 1
check:
  %eof = icmp eq i32 %ch, -1
  br i1 %eof, label %no, label %body
no:
  ret i32 0
body:
  call void @buf_keep(ptr %buf)
  br label %loop
}

define private i32 @collect_string(ptr %buf, ptr %end, i64 %len) {
entry:
  %one = icmp eq i64 %len, 1
  br i1 %one, label %single, label %multi
single:
  %c = load i8, ptr %end
  %r = call i32 @collect_to_ch(ptr %buf, i8 %c)
  ret i32 %r
multi:
  br label %loop
loop:
  %pos = phi i64 [ 0, %multi ], [ %pos1, %match ], [ 0, %reset ], [ %pos, %keep ]
  %cont = icmp ult i64 %pos, %len
  br i1 %cont, label %check, label %found
check:
  %ch = load i32, ptr @cur_ch
  %at = getelementptr i8, ptr %end, i64 %pos
  %want = load i8, ptr %at
  %want32 = sext i8 %want to i32
  %eq = icmp eq i32 %ch, %want32
  br i1 %eq, label %match, label %checkpos
match:
  call void @skip()
  %pos1 = add i64 %pos, 1
  br label %loop
checkpos:
  %posgt = icmp ugt i64 %pos, 0
  br i1 %posgt, label %reset, label %check2
reset:
  call void @buf_addn(ptr %buf, ptr %end, i64 %pos)
  br label %loop
check2:
  %eof = icmp eq i32 %ch, -1
  br i1 %eof, label %no, label %keep
keep:
  call void @buf_keep(ptr %buf)
  br label %loop
no:
  ret i32 0
found:
  ret i32 1
}

define i32 @collect_tilde_string(ptr %buf) {
entry:
  %ok = call i32 @collect_to_white(ptr %buf)
  %good = icmp eq i32 %ok, 1
  br i1 %good, label %body, label %no
no:
  ret i32 -1
body:
  %end = call ptr @buf_clear(ptr %buf)
  %lp = getelementptr i8, ptr %end, i64 0
  %len = load i64, ptr %lp
  %dp = getelementptr i8, ptr %end, i64 8
  %r = call i32 @collect_string(ptr %buf, ptr %dp, i64 %len)
  call void @str_free(ptr %end)
  ret i32 %r
}

define void @beg_stream(ptr %sret, ptr %get, ptr %source) {
entry:
  %ch = load i32, ptr @cur_ch
  %line = load i64, ptr @cur_line
  %oldget = load ptr, ptr @cur_get
  %oldsrc = load ptr, ptr @cur_source
  %p0 = getelementptr %StreamState, ptr %sret, i32 0, i32 0
  store i32 %ch, ptr %p0
  %p1 = getelementptr %StreamState, ptr %sret, i32 0, i32 1
  store i64 %line, ptr %p1
  %p2 = getelementptr %StreamState, ptr %sret, i32 0, i32 2
  store ptr %oldget, ptr %p2
  %p3 = getelementptr %StreamState, ptr %sret, i32 0, i32 3
  store ptr %oldsrc, ptr %p3
  store ptr %get, ptr @cur_get
  store i64 1, ptr @cur_line
  store ptr %source, ptr @cur_source
  call void @skip()
  ret void
}

define void @end_stream(ptr %s) {
entry:
  %p0 = getelementptr %StreamState, ptr %s, i32 0, i32 0
  %ch = load i32, ptr %p0
  store i32 %ch, ptr @cur_ch
  %p1 = getelementptr %StreamState, ptr %s, i32 0, i32 1
  %line = load i64, ptr %p1
  store i64 %line, ptr @cur_line
  %p2 = getelementptr %StreamState, ptr %s, i32 0, i32 2
  %get = load ptr, ptr %p2
  store ptr %get, ptr @cur_get
  %p3 = getelementptr %StreamState, ptr %s, i32 0, i32 3
  %src = load ptr, ptr %p3
  store ptr %src, ptr @cur_source
  ret void
}
