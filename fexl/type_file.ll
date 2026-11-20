; fexl/type_file.ll — archivos y sistema (antes src/type_file.c).
; value_types.ll se inyecta por concatenacion en el build.

@QI     = external global ptr
@Qvoid  = external global ptr
@Qnull  = external global ptr
@stdin  = external global ptr
@stdout = external global ptr
@stderr = external global ptr

@Qstdin  = internal global ptr null
@Qstdout = internal global ptr null
@Qstderr = internal global ptr null

@.s_stdin      = private constant [6 x i8] c"stdin\00"
@.s_stdout     = private constant [7 x i8] c"stdout\00"
@.s_stderr     = private constant [7 x i8] c"stderr\00"
@.s_fopen      = private constant [6 x i8] c"fopen\00"
@.s_fclose     = private constant [7 x i8] c"fclose\00"
@.s_fgetc      = private constant [6 x i8] c"fgetc\00"
@.s_fget       = private constant [5 x i8] c"fget\00"
@.s_clearerr   = private constant [9 x i8] c"clearerr\00"
@.s_feof       = private constant [5 x i8] c"feof\00"
@.s_flook      = private constant [6 x i8] c"flook\00"
@.s_remove     = private constant [7 x i8] c"remove\00"
@.s_is_newer   = private constant [9 x i8] c"is_newer\00"
@.s_is_file    = private constant [8 x i8] c"is_file\00"
@.s_is_dir     = private constant [7 x i8] c"is_dir\00"
@.s_flock_ex   = private constant [9 x i8] c"flock_ex\00"
@.s_flock_sh   = private constant [9 x i8] c"flock_sh\00"
@.s_flock_un   = private constant [9 x i8] c"flock_un\00"
@.s_readlink   = private constant [9 x i8] c"readlink\00"
@.s_mkdir      = private constant [6 x i8] c"mkdir\00"
@.s_rmdir      = private constant [6 x i8] c"rmdir\00"
@.s_ftruncate  = private constant [10 x i8] c"ftruncate\00"
@.s_fseek_set  = private constant [10 x i8] c"fseek_set\00"
@.s_fseek_cur  = private constant [10 x i8] c"fseek_cur\00"
@.s_fseek_end  = private constant [10 x i8] c"fseek_end\00"
@.s_ftell      = private constant [6 x i8] c"ftell\00"
@.s_fileno     = private constant [7 x i8] c"fileno\00"
@.s_fread      = private constant [6 x i8] c"fread\00"
@.s_mkfile     = private constant [7 x i8] c"mkfile\00"
@.s_dir_names  = private constant [10 x i8] c"dir_names\00"
@.s_mod_time   = private constant [9 x i8] c"mod_time\00"
@.s_file_size  = private constant [10 x i8] c"file_size\00"
@.s_symlink    = private constant [8 x i8] c"symlink\00"
@.s_rename     = private constant [7 x i8] c"rename\00"
@.s_rplus      = private constant [3 x i8] c"r+\00"
@.s_flock_msg  = private constant [6 x i8] c"flock\00"

declare ptr  @type_void(ptr)
declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Qnum(double)
declare ptr  @Qstr(ptr)
declare ptr  @Qstr0(ptr)
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @cons(ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @keep(ptr)
declare ptr  @boolean(i32)
declare void @define(ptr, ptr)
declare ptr  @str_data(ptr)
declare ptr  @str_new(i64)
declare ptr  @str_new_data(ptr, i64)
declare void @str_free(ptr)
declare i64  @get_ulong(ptr)
declare ptr  @op_getc(ptr, ptr, ptr)
declare ptr  @op_get(ptr, ptr, ptr)
declare ptr  @type_num(ptr)
declare ptr  @type_str(ptr)
declare ptr  @new_memory(i64)
declare void @free_memory(ptr, i64)
declare void @die(ptr)
declare void @perror(ptr)

declare ptr  @fopen(ptr, ptr)
declare i32  @fclose(ptr)
declare i32  @fileno(ptr)
declare i32  @fgetc(ptr)
declare i32  @ungetc(i32, ptr)
declare void @clearerr(ptr)
declare i32  @feof(ptr)
declare i32  @remove(ptr)
declare i32  @stat(ptr, ptr)
declare i32  @flock(i32, i32)
declare i64  @readlink(ptr, ptr, i64)
declare i32  @mkdir(ptr, i32)
declare i32  @rmdir(ptr)
declare i32  @ftruncate(i32, i64)
declare i32  @fseek(ptr, i64, i32)
declare i64  @ftell(ptr)
declare i64  @fread(ptr, i64, i64, ptr)
declare i32  @open(ptr, i32, i32)
declare ptr  @fdopen(i32, ptr)
declare ptr  @opendir(ptr)
declare ptr  @readdir(ptr)
declare i32  @closedir(ptr)
declare i32  @symlink(ptr, ptr)
declare i32  @rename(ptr, ptr)

define private void @fh_free(ptr %fh) {
entry:
  %fd = call i32 @fileno(ptr %fh)
  %std = icmp sle i32 %fd, 2
  br i1 %std, label %done, label %close
close:
  %r = call i32 @fclose(ptr %fh)
  br label %done
done:
  ret void
}

define private void @clear_file(ptr %f) {
entry:
  %vp = getelementptr %value, ptr %f, i32 0, i32 3
  %fh = load ptr, ptr %vp
  call void @fh_free(ptr %fh)
  ret void
}
@clear_file_sentinel = private constant %value { i64 0, ptr @clear_file, ptr null, ptr null }

define ptr @type_file(ptr %f) {
entry:
  %r = call ptr @type_void(ptr %f)
  ret ptr %r
}

define ptr @Qfile(ptr %fh) {
entry:
  %r = call ptr @V(ptr @type_file, ptr @clear_file_sentinel, ptr %fh)
  ret ptr %r
}

define private ptr @type_fopen(ptr %f) {
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
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %both = and i1 %xs, %ys
  br i1 %both, label %openit, label %void
openit:
  %path = call ptr @str_data(ptr %x)
  %mode = call ptr @str_data(ptr %y)
  %fh = call ptr @fopen(ptr %path, ptr %mode)
  %nonnull = icmp ne ptr %fh, null
  br i1 %nonnull, label %mk, label %void
mk:
  %res = call ptr @Qfile(ptr %fh)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %mk ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_fclose(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %out = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %out, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_file
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %out, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %c = call i32 @fclose(ptr %fh)
  %tp2 = getelementptr %value, ptr %out, i32 0, i32 1
  store ptr @type_void, ptr %tp2
  %lp = getelementptr %value, ptr %out, i32 0, i32 2
  store ptr null, ptr %lp
  %rp2 = getelementptr %value, ptr %out, i32 0, i32 3
  store ptr null, ptr %rp2
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %h, %yes ], [ %h2, %void ]
  call void @drop(ptr %out)
  ret ptr %r
}

define private ptr @type_fgetc(ptr %f) {
entry:
  %r = call ptr @op_getc(ptr %f, ptr @type_file, ptr @fgetc)
  ret ptr %r
}
define private ptr @type_fget(ptr %f) {
entry:
  %r = call ptr @op_get(ptr %f, ptr @type_file, ptr @fgetc)
  ret ptr %r
}

define private ptr @type_clearerr(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_file
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  call void @clearerr(ptr %fh)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %h, %yes ], [ %h2, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_feof(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_file
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %n = call i32 @feof(ptr %fh)
  %res = call ptr @boolean(i32 %n)
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

define private ptr @type_flook(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_file
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %ch = call i32 @fgetc(ptr %fh)
  %eof = icmp eq i32 %ch, -1
  br i1 %eof, label %void, label %mk
mk:
  %c = trunc i32 %ch to i8
  %p = alloca i8, align 1
  store i8 %c, ptr %p, align 1
  %u = call i32 @ungetc(i32 %ch, ptr %fh)
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

define private ptr @type_remove(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %code = call i32 @remove(ptr %s)
  %d = sitofp i32 %code to double
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

define private i32 @is_newer(ptr %p1, ptr %p2) {
entry:
  %s1 = alloca [144 x i8], align 8
  %s2 = alloca [144 x i8], align 8
  %r1 = call i32 @stat(ptr %p1, ptr %s1)
  %bad1 = icmp ne i32 %r1, 0
  br i1 %bad1, label %yes, label %stat2
stat2:
  %r2 = call i32 @stat(ptr %p2, ptr %s2)
  %bad2 = icmp ne i32 %r2, 0
  br i1 %bad2, label %yes, label %cmp
yes:
  ret i32 1
cmp:
  %t1p = getelementptr i8, ptr %s1, i64 88
  %t2p = getelementptr i8, ptr %s2, i64 88
  %t1 = load i64, ptr %t1p
  %t2 = load i64, ptr %t2p
  %newer = icmp sgt i64 %t1, %t2
  %r = zext i1 %newer to i32
  ret i32 %r
}

define private ptr @type_is_newer(ptr %f) {
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
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %both = and i1 %xs, %ys
  br i1 %both, label %yes, label %void
yes:
  %s1 = call ptr @str_data(ptr %x)
  %s2 = call ptr @str_data(ptr %y)
  %c = call i32 @is_newer(ptr %s1, ptr %s2)
  %res = call ptr @boolean(i32 %c)
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

define private ptr @op_stat_type(ptr %f, i32 %mask) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %st = alloca [144 x i8], align 8
  %r = call i32 @stat(ptr %s, ptr %st)
  %ok = icmp eq i32 %r, -1
  br i1 %ok, label %false, label %check
check:
  %modep = getelementptr i8, ptr %st, i64 24
  %mode = load i32, ptr %modep
  %fm = and i32 %mode, 61440
  %eq = icmp eq i32 %fm, %mask
  %ci = zext i1 %eq to i32
  %res = call ptr @boolean(i32 %ci)
  br label %done
false:
  %bf = call ptr @boolean(i32 0)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %result = phi ptr [ %res, %check ], [ %bf, %false ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %result
}

define private ptr @type_is_file(ptr %f) {
entry:
  %r = call ptr @op_stat_type(ptr %f, i32 32768)
  ret ptr %r
}
define private ptr @type_is_dir(ptr %f) {
entry:
  %r = call ptr @op_stat_type(ptr %f, i32 16384)
  ret ptr %r
}

define private ptr @op_flock(ptr %f, i32 %op) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_file
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %fd = call i32 @fileno(ptr %fh)
  %code = call i32 @flock(i32 %fd, i32 %op)
  %bad = icmp slt i32 %code, 0
  br i1 %bad, label %die, label %ok
die:
  call void @perror(ptr @.s_flock_msg)
  call void @die(ptr null)
  unreachable
ok:
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %h, %ok ], [ %h2, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_flock_ex(ptr %f) { entry: %r = call ptr @op_flock(ptr %f, i32 2) ret ptr %r }
define private ptr @type_flock_sh(ptr %f) { entry: %r = call ptr @op_flock(ptr %f, i32 1) ret ptr %r }
define private ptr @type_flock_un(ptr %f) { entry: %r = call ptr @op_flock(ptr %f, i32 8) ret ptr %r }

define private ptr @safe_readlink(ptr %path) {
entry:
  br label %loop
loop:
  %size = phi i64 [ 256, %entry ], [ %size2, %grow ]
  %buf = call ptr @new_memory(i64 %size)
  %len = call i64 @readlink(ptr %path, ptr %buf, i64 %size)
  %full = icmp eq i64 %len, %size
  br i1 %full, label %grow, label %finish
grow:
  call void @free_memory(ptr %buf, i64 %size)
  %size2 = shl i64 %size, 1
  br label %loop
finish:
  %nonneg = icmp sge i64 %len, 0
  %actual = select i1 %nonneg, i64 %len, i64 0
  %r = call ptr @str_new_data(ptr %buf, i64 %actual)
  call void @free_memory(ptr %buf, i64 %size)
  ret ptr %r
}

define private ptr @type_readlink(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %r = call ptr @safe_readlink(ptr %s)
  %res = call ptr @Qstr(ptr %r)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %result = phi ptr [ %res, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %result
}

define private ptr @type_mkdir(ptr %f) {
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
  %xs = icmp eq ptr %xt, @type_str
  %yn = icmp eq ptr %yt, @type_num
  %both = and i1 %xs, %yn
  br i1 %both, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %mode = call i64 @get_ulong(ptr %y)
  %m = trunc i64 %mode to i32
  %code = call i32 @mkdir(ptr %s, i32 %m)
  %d = sitofp i32 %code to double
  %res = call ptr @Qnum(double %d)
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

define private ptr @type_rmdir(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %code = call i32 @rmdir(ptr %s)
  %d = sitofp i32 %code to double
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

define private ptr @type_ftruncate(ptr %f) {
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
  %xf = icmp eq ptr %xt, @type_file
  %yn = icmp eq ptr %yt, @type_num
  %both = and i1 %xf, %yn
  br i1 %both, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %fd = call i32 @fileno(ptr %fh)
  %len = call i64 @get_ulong(ptr %y)
  %code = call i32 @ftruncate(i32 %fd, i64 %len)
  %d = sitofp i32 %code to double
  %res = call ptr @Qnum(double %d)
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

define private ptr @op_seek(ptr %f, i32 %whence) {
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
  %xf = icmp eq ptr %xt, @type_file
  %yn = icmp eq ptr %yt, @type_num
  %both = and i1 %xf, %yn
  br i1 %both, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %dp = getelementptr %value, ptr %y, i32 0, i32 3
  %d = load double, ptr %dp
  %off = fptosi double %d to i64
  %code = call i32 @fseek(ptr %fh, i64 %off, i32 %whence)
  %cd = sitofp i32 %code to double
  %res = call ptr @Qnum(double %cd)
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

define private ptr @type_fseek_set(ptr %f) { entry: %r = call ptr @op_seek(ptr %f, i32 0) ret ptr %r }
define private ptr @type_fseek_cur(ptr %f) { entry: %r = call ptr @op_seek(ptr %f, i32 1) ret ptr %r }
define private ptr @type_fseek_end(ptr %f) { entry: %r = call ptr @op_seek(ptr %f, i32 2) ret ptr %r }

define private ptr @type_ftell(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_file
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %n = call i64 @ftell(ptr %fh)
  %d = sitofp i64 %n to double
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

define private ptr @type_fileno(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_file
  br i1 %is, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %n = call i32 @fileno(ptr %fh)
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

define private ptr @type_fread(ptr %f) {
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
  %xf = icmp eq ptr %xt, @type_file
  %yn = icmp eq ptr %yt, @type_num
  %both = and i1 %xf, %yn
  br i1 %both, label %yes, label %void
yes:
  %vp = getelementptr %value, ptr %x, i32 0, i32 3
  %fh = load ptr, ptr %vp
  %size = call i64 @get_ulong(ptr %y)
  %s = call ptr @str_new(i64 %size)
  %dp = getelementptr i8, ptr %s, i64 8
  %count = call i64 @fread(ptr %dp, i64 1, i64 %size, ptr %fh)
  %short = icmp ult i64 %count, %size
  br i1 %short, label %shrink, label %wrap
shrink:
  %s2 = call ptr @str_new_data(ptr %dp, i64 %count)
  call void @str_free(ptr %s)
  br label %wrap
wrap:
  %final = phi ptr [ %s, %yes ], [ %s2, %shrink ]
  %res = call ptr @Qstr(ptr %final)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %wrap ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @type_mkfile(ptr %f) {
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
  %xs = icmp eq ptr %xt, @type_str
  %yn = icmp eq ptr %yt, @type_num
  %both = and i1 %xs, %yn
  br i1 %both, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %mode = call i64 @get_ulong(ptr %y)
  %m = trunc i64 %mode to i32
  %fd = call i32 @open(ptr %s, i32 194, i32 %m)
  %ok = icmp ne i32 %fd, -1
  br i1 %ok, label %dop, label %void
dop:
  %fh = call ptr @fdopen(i32 %fd, ptr @.s_rplus)
  %nonnull = icmp ne ptr %fh, null
  br i1 %nonnull, label %mk, label %void
mk:
  %res = call ptr @Qfile(ptr %fh)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %mk ], [ %h, %void ]
  call void @drop(ptr %x)
  call void @drop(ptr %y)
  ret ptr %r
}

define private ptr @dir_names(ptr %dir) {
entry:
  %de = call ptr @readdir(ptr %dir)
  %null = icmp eq ptr %de, null
  br i1 %null, label %empty, label %cons
cons:
  %namep = getelementptr i8, ptr %de, i64 19
  %s = call ptr @Qstr0(ptr %namep)
  %rest = call ptr @dir_names(ptr %dir)
  %res = call ptr @cons(ptr %s, ptr %rest)
  ret ptr %res
empty:
  %qn = load ptr, ptr @Qnull
  %h = call ptr @hold(ptr %qn)
  ret ptr %h
}

define private ptr @type_dir_names(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %dir = call ptr @opendir(ptr %s)
  %nonnull = icmp ne ptr %dir, null
  br i1 %nonnull, label %read, label %void
read:
  %res = call ptr @dir_names(ptr %dir)
  %c = call i32 @closedir(ptr %dir)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %res, %read ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private i64 @get_st_mtime(ptr %st) {
entry:
  %p = getelementptr i8, ptr %st, i64 88
  %n = load i64, ptr %p
  ret i64 %n
}
define private i64 @get_st_size(ptr %st) {
entry:
  %p = getelementptr i8, ptr %st, i64 48
  %n = load i64, ptr %p
  ret i64 %n
}

define private ptr @op_stat(ptr %f, ptr %op) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %argp = load ptr, ptr %rp
  %x = call ptr @arg(ptr %argp)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %s = call ptr @str_data(ptr %x)
  %st = alloca [144 x i8], align 8
  %r = call i32 @stat(ptr %s, ptr %st)
  %bad = icmp eq i32 %r, -1
  br i1 %bad, label %void, label %get
get:
  %n = call i64 %op(ptr %st)
  %d = sitofp i64 %n to double
  %res = call ptr @Qnum(double %d)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %result = phi ptr [ %res, %get ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %result
}

define private ptr @type_mod_time(ptr %f) {
entry:
  %r = call ptr @op_stat(ptr %f, ptr @get_st_mtime)
  ret ptr %r
}
define private ptr @type_file_size(ptr %f) {
entry:
  %r = call ptr @op_stat(ptr %f, ptr @get_st_size)
  ret ptr %r
}

define private ptr @type_symlink(ptr %f) {
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
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %both = and i1 %xs, %ys
  br i1 %both, label %yes, label %void
yes:
  %s1 = call ptr @str_data(ptr %x)
  %s2 = call ptr @str_data(ptr %y)
  %code = call i32 @symlink(ptr %s1, ptr %s2)
  %d = sitofp i32 %code to double
  %res = call ptr @Qnum(double %d)
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

define private ptr @type_rename(ptr %f) {
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
  %xs = icmp eq ptr %xt, @type_str
  %ys = icmp eq ptr %yt, @type_str
  %both = and i1 %xs, %ys
  br i1 %both, label %yes, label %void
yes:
  %s1 = call ptr @str_data(ptr %x)
  %s2 = call ptr @str_data(ptr %y)
  %code = call i32 @rename(ptr %s1, ptr %s2)
  %d = sitofp i32 %code to double
  %res = call ptr @Qnum(double %d)
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

define ptr @type_load_file(ptr %f) {
entry:
  %a = load ptr, ptr @Qstdin
  %ha = call ptr @hold(ptr %a)
  call void @define(ptr @.s_stdin, ptr %ha)
  %b = load ptr, ptr @Qstdout
  %hb = call ptr @hold(ptr %b)
  call void @define(ptr @.s_stdout, ptr %hb)
  %c = load ptr, ptr @Qstderr
  %hc = call ptr @hold(ptr %c)
  call void @define(ptr @.s_stderr, ptr %hc)
  %q0 = call ptr @Q(ptr @type_fopen)
  call void @define(ptr @.s_fopen, ptr %q0)
  %q1 = call ptr @Q(ptr @type_fclose)
  call void @define(ptr @.s_fclose, ptr %q1)
  %q2 = call ptr @Q(ptr @type_fgetc)
  call void @define(ptr @.s_fgetc, ptr %q2)
  %q3 = call ptr @Q(ptr @type_fget)
  call void @define(ptr @.s_fget, ptr %q3)
  %q4 = call ptr @Q(ptr @type_clearerr)
  call void @define(ptr @.s_clearerr, ptr %q4)
  %q5 = call ptr @Q(ptr @type_feof)
  call void @define(ptr @.s_feof, ptr %q5)
  %q6 = call ptr @Q(ptr @type_flook)
  call void @define(ptr @.s_flook, ptr %q6)
  %q7 = call ptr @Q(ptr @type_remove)
  call void @define(ptr @.s_remove, ptr %q7)
  %q8 = call ptr @Q(ptr @type_is_newer)
  call void @define(ptr @.s_is_newer, ptr %q8)
  %q9 = call ptr @Q(ptr @type_is_file)
  call void @define(ptr @.s_is_file, ptr %q9)
  %q10 = call ptr @Q(ptr @type_is_dir)
  call void @define(ptr @.s_is_dir, ptr %q10)
  %q11 = call ptr @Q(ptr @type_flock_ex)
  call void @define(ptr @.s_flock_ex, ptr %q11)
  %q12 = call ptr @Q(ptr @type_flock_sh)
  call void @define(ptr @.s_flock_sh, ptr %q12)
  %q13 = call ptr @Q(ptr @type_flock_un)
  call void @define(ptr @.s_flock_un, ptr %q13)
  %q14 = call ptr @Q(ptr @type_readlink)
  call void @define(ptr @.s_readlink, ptr %q14)
  %q15 = call ptr @Q(ptr @type_mkdir)
  call void @define(ptr @.s_mkdir, ptr %q15)
  %q16 = call ptr @Q(ptr @type_rmdir)
  call void @define(ptr @.s_rmdir, ptr %q16)
  %q17 = call ptr @Q(ptr @type_ftruncate)
  call void @define(ptr @.s_ftruncate, ptr %q17)
  %q18 = call ptr @Q(ptr @type_fseek_set)
  call void @define(ptr @.s_fseek_set, ptr %q18)
  %q19 = call ptr @Q(ptr @type_fseek_cur)
  call void @define(ptr @.s_fseek_cur, ptr %q19)
  %q20 = call ptr @Q(ptr @type_fseek_end)
  call void @define(ptr @.s_fseek_end, ptr %q20)
  %q21 = call ptr @Q(ptr @type_ftell)
  call void @define(ptr @.s_ftell, ptr %q21)
  %q22 = call ptr @Q(ptr @type_fileno)
  call void @define(ptr @.s_fileno, ptr %q22)
  %q23 = call ptr @Q(ptr @type_fread)
  call void @define(ptr @.s_fread, ptr %q23)
  %q24 = call ptr @Q(ptr @type_mkfile)
  call void @define(ptr @.s_mkfile, ptr %q24)
  %q25 = call ptr @Q(ptr @type_dir_names)
  call void @define(ptr @.s_dir_names, ptr %q25)
  %q26 = call ptr @Q(ptr @type_mod_time)
  call void @define(ptr @.s_mod_time, ptr %q26)
  %q27 = call ptr @Q(ptr @type_file_size)
  call void @define(ptr @.s_file_size, ptr %q27)
  %q28 = call ptr @Q(ptr @type_symlink)
  call void @define(ptr @.s_symlink, ptr %q28)
  %q29 = call ptr @Q(ptr @type_rename)
  call void @define(ptr @.s_rename, ptr %q29)
  %qi = load ptr, ptr @QI
  %hqi = call ptr @hold(ptr %qi)
  ret ptr %hqi
}

define void @beg_file() {
entry:
  %a = load ptr, ptr @stdin
  %qa = call ptr @Qfile(ptr %a)
  store ptr %qa, ptr @Qstdin
  %b = load ptr, ptr @stdout
  %qb = call ptr @Qfile(ptr %b)
  store ptr %qb, ptr @Qstdout
  %c = load ptr, ptr @stderr
  %qc = call ptr @Qfile(ptr %c)
  store ptr %qc, ptr @Qstderr
  ret void
}

define void @end_file() {
entry:
  %a = load ptr, ptr @Qstdin
  call void @drop(ptr %a)
  %b = load ptr, ptr @Qstdout
  call void @drop(ptr %b)
  %c = load ptr, ptr @Qstderr
  call void @drop(ptr %c)
  ret void
}
