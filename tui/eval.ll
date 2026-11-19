; tui/eval.ll — puente de la consola al interprete Fexl (migrado de eval.c).
;
; El script de sesion se ACUMULA: cada linea se agrega y se re-evalua completo,
; asi las definiciones (\mi_fn=...) sobreviven entre comandos.
; SWI_FEXL_BIN se fija desde main.c con swi_eval_set_bin().

declare i32  @snprintf(ptr, i64, ptr, ...)
declare i32  @getpid()
declare i32  @remove(ptr)
declare ptr  @fopen(ptr, ptr)
declare i32  @fclose(ptr)
declare i32  @fseek(ptr, i64, i32)
declare i64  @ftell(ptr)
declare i64  @fwrite(ptr, i64, i64, ptr)
declare i64  @fread(ptr, i64, i64, ptr)
declare ptr  @strncpy(ptr, ptr, i64)
declare i64  @strlen(ptr)
declare i32  @fork()
declare i32  @open(ptr, i32, i32)
declare i32  @dup2(i32, i32)
declare i32  @close(i32)
declare i32  @execl(ptr, ptr, ptr, ptr)
declare void @_exit(i32)
declare i32  @waitpid(i32, ptr, i32)

@EVAL_BIN     = private global [512 x i8] zeroinitializer
@EVAL_SESSION = private global [128 x i8] zeroinitializer
@EVAL_OUT     = private global [128 x i8] zeroinitializer
@EVAL_RESULT  = private global [4096 x i8] zeroinitializer
@EVAL_READY   = private global i32 0

@FMT_SESSION = private constant [29 x i8] c"/tmp/swi_fexl_session_%d.fxl\00"
@FMT_OUT     = private constant [21 x i8] c"/tmp/swi_eval_%d.out\00"
@MODE_APB    = private constant [4 x i8] c"a+b\00"
@MODE_RB     = private constant [3 x i8] c"rb\00"
@NL          = private constant [2 x i8] c"\0A\00"

; load_* + evaluate \; para fexlswi0 (sin builtins preloadados).
@PRELOAD = private constant [99 x i8] c"load_basic\0Aload_output\0Aload_cmp\0Aload_file\0Aload_str\0Aload_extend\0Aload_regex\0Aload_script\0Aevaluate \5C;\0A\00"

define void @swi_eval_set_bin(ptr %bin) {
entry:
  %bp = getelementptr [512 x i8], ptr @EVAL_BIN, i32 0, i32 0
  call ptr @strncpy(ptr %bp, ptr %bin, i64 511)
  ret void
}

define ptr @swi_eval_output() {
entry:
  %p = getelementptr [4096 x i8], ptr @EVAL_RESULT, i32 0, i32 0
  ret ptr %p
}

define internal void @eval_paths_init() {
entry:
  %pid = call i32 @getpid()
  %sp = getelementptr [128 x i8], ptr @EVAL_SESSION, i32 0, i32 0
  %r1 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %sp, i64 128,
                                                ptr @FMT_SESSION, i32 %pid)
  %op = getelementptr [128 x i8], ptr @EVAL_OUT, i32 0, i32 0
  %r2 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %op, i64 128,
                                                ptr @FMT_OUT, i32 %pid)
  ret void
}

define void @swi_eval_reset() {
entry:
  %ready = load i32, ptr @EVAL_READY
  %is0 = icmp eq i32 %ready, 0
  br i1 %is0, label %init, label %remove_session
init:
  call void @eval_paths_init()
  br label %remove_session
remove_session:
  %sp = getelementptr [128 x i8], ptr @EVAL_SESSION, i32 0, i32 0
  call i32 @remove(ptr %sp)
  store i32 0, ptr @EVAL_READY
  %rp = getelementptr [4096 x i8], ptr @EVAL_RESULT, i32 0, i32 0
  store i8 0, ptr %rp
  ret void
}

define i32 @swi_eval(ptr %line, i64 %len) {
entry:
  %ln = icmp eq ptr %line, null
  %neg = icmp slt i64 %len, 0
  %bad = or i1 %ln, %neg
  br i1 %bad, label %fail, label %check_ready
check_ready:
  %ready = load i32, ptr @EVAL_READY
  %is0 = icmp eq i32 %ready, 0
  br i1 %is0, label %init, label %clear_result
init:
  call void @eval_paths_init()
  br label %clear_result
clear_result:
  %rp = getelementptr [4096 x i8], ptr @EVAL_RESULT, i32 0, i32 0
  store i8 0, ptr %rp
  %sp = getelementptr [128 x i8], ptr @EVAL_SESSION, i32 0, i32 0
  %f = call ptr @fopen(ptr %sp, ptr @MODE_APB)
  %fn = icmp eq ptr %f, null
  br i1 %fn, label %fail, label %seek
seek:
  %sk = call i32 @fseek(ptr %f, i64 0, i32 2)
  %pos = call i64 @ftell(ptr %f)
  %isnew = icmp eq i64 %pos, 0
  br i1 %isnew, label %write_preload, label %write_line
write_preload:
  %plen = call i64 @strlen(ptr @PRELOAD)
  %n0 = call i64 @fwrite(ptr @PRELOAD, i64 1, i64 %plen, ptr %f)
  br label %write_line
write_line:
  %n1 = call i64 @fwrite(ptr %line, i64 1, i64 %len, ptr %f)
  %n2 = call i64 @fwrite(ptr @NL, i64 1, i64 1, ptr %f)
  %fc = call i32 @fclose(ptr %f)
  store i32 1, ptr @EVAL_READY
  br label %do_fork
do_fork:
  %pid = call i32 @fork()
  %fneg = icmp slt i32 %pid, 0
  br i1 %fneg, label %fail, label %child_check
child_check:
  %zero = icmp eq i32 %pid, 0
  br i1 %zero, label %child, label %parent
child:
  %op = getelementptr [128 x i8], ptr @EVAL_OUT, i32 0, i32 0
  ; O_WRONLY|O_CREAT|O_TRUNC = 1|64|512 = 577, modo 0600 = 384
  %fd = call i32 @open(ptr %op, i32 577, i32 384)
  %fdneg = icmp slt i32 %fd, 0
  br i1 %fdneg, label %child_exit, label %child_dup
child_dup:
  %d1 = call i32 @dup2(i32 %fd, i32 1)
  %d2 = call i32 @dup2(i32 %fd, i32 2)
  %dc = call i32 @close(i32 %fd)
  %bp = getelementptr [512 x i8], ptr @EVAL_BIN, i32 0, i32 0
  call i32 @execl(ptr %bp, ptr %bp, ptr %sp, ptr null)
  br label %child_exit
child_exit:
  call void @_exit(i32 127)
  ret i32 0
parent:
  %status = alloca i32
  store i32 -1, ptr %status
  %w = call i32 @waitpid(i32 %pid, ptr %status, i32 0)
  br label %read_output
read_output:
  %op2 = getelementptr [128 x i8], ptr @EVAL_OUT, i32 0, i32 0
  %ofd = call ptr @fopen(ptr %op2, ptr @MODE_RB)
  %ofn = icmp eq ptr %ofd, null
  br i1 %ofn, label %cleanup, label %do_read
do_read:
  %rp2 = getelementptr [4096 x i8], ptr @EVAL_RESULT, i32 0, i32 0
  %nread = call i64 @fread(ptr %rp2, i64 1, i64 4095, ptr %ofd)
  %term = getelementptr i8, ptr %rp2, i64 %nread
  store i8 0, ptr %term
  %oc = call i32 @fclose(ptr %ofd)
  br label %cleanup
cleanup:
  %op3 = getelementptr [128 x i8], ptr @EVAL_OUT, i32 0, i32 0
  %rm = call i32 @remove(ptr %op3)
  %st = load i32, ptr %status
  %exited = icmp eq i32 %st, 0
  br i1 %exited, label %yes, label %no
yes:
  ret i32 1
no:
  ret i32 0
fail:
  ret i32 -1
}
