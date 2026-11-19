; tui/fexl_ui.ll — driver Fexl persistente y parser de frames (migrado de C).
;
; El motor guarda el estado; Fexl decide layout y atajos. Este modulo no
; contiene el interprete: lanza fexlswi0 con fork/exec y habla por pipes.
;
; UiFrame (espejo en abi/tui_abi.h y tui/fexl_ui.h): 4116 bytes.

%FmtSpan = type { i32, i32, i32 }
%FuiBind = type { [16 x i8], [32 x i8] }
%UiFrame = type { i32, i32, i32, [64 x i8], [256 x i8], [128 x i8],
                  [256 x %FmtSpan], i32, [12 x %FuiBind], i32 }

declare ptr   @memset(ptr, i32, i64)
declare ptr   @memcpy(ptr, ptr, i64)
declare ptr   @strncpy(ptr, ptr, i64)
declare i64   @strncmp(ptr, ptr, i64)
declare ptr   @strstr(ptr, ptr)
declare i64   @strtol(ptr, ptr, i32)
declare i32   @sscanf(ptr, ptr, ...)

declare i32   @pipe(ptr)
declare i32   @fork()
declare i32   @dup2(i32, i32)
declare i32   @close(i32)
declare i32   @execl(ptr, ptr, ptr, ptr)
declare void  @_exit(i32)
declare ptr   @fdopen(i32, ptr)
declare i32   @fclose(ptr)
declare i64   @fwrite(ptr, i64, i64, ptr)
declare i32   @fflush(ptr)
declare ptr   @fgets(ptr, i32, ptr)
declare i32   @kill(i32, i32)
declare i32   @waitpid(i32, ptr, i32)
declare void  @signal(i32, ptr)

@FUI_PID    = private global i32 -1
@FUI_IN     = private global ptr null
@FUI_OUT    = private global ptr null
@FUI_BIN    = private global [512 x i8] zeroinitializer
@FUI_SCRIPT = private global [512 x i8] zeroinitializer
@FUI_GOOD   = private global [4116 x i8] zeroinitializer
@FUI_HAS    = private global i32 0

@FMT_WB = private constant [3 x i8] c"wb\00"
@FMT_RB = private constant [3 x i8] c"rb\00"
@FMT_CH = private constant [13 x i8] c"CONSOLE_H %d\00"
@FMT_TC = private constant [12 x i8] c"TABS_COL %d\00"
@FMT_FW = private constant [13 x i8] c"FILEMAN_W %d\00"
@FMT_ST = private constant [12 x i8] c"STATUS %63s\00"
@FMT_LG = private constant [10 x i8] c"LOG %255s\00"
@UNDEF  = private constant [17 x i8] c"Undefined symbol\00"
@SYNTAX = private constant [13 x i8] c"syntax error\00"
@SPANSK = private constant [7 x i8] c"SPANS \00"
@BINDK  = private constant [6 x i8] c"BIND \00"

; ---------------------------------------------------------------- helpers

; Copia un token hasta espacio/NL/NUL, con clamp de max-1, y devuelve el
; puntero justo despues del token.
define internal ptr @fui_token(ptr %dst, ptr %src, i64 %max) {
entry:
  %end = alloca i64
  store i64 0, ptr %end
  br label %loop
loop:
  %i = load i64, ptr %end
  %lim = sub i64 %max, 1
  %more = icmp slt i64 %i, %lim
  br i1 %more, label %body, label %term
body:
  %cp = getelementptr i8, ptr %src, i64 %i
  %c = load i8, ptr %cp
  %nul = icmp eq i8 %c, 0
  %nl = icmp eq i8 %c, 10
  %cr = icmp eq i8 %c, 13
  %sp = icmp eq i8 %c, 32
  %s1 = or i1 %nul, %nl
  %s2 = or i1 %cr, %sp
  %stop = or i1 %s1, %s2
  br i1 %stop, label %term, label %copy
copy:
  %dp = getelementptr i8, ptr %dst, i64 %i
  store i8 %c, ptr %dp
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %end
  br label %loop
term:
  %final = load i64, ptr %end
  %z = getelementptr i8, ptr %dst, i64 %final
  store i8 0, ptr %z
  %res = getelementptr i8, ptr %src, i64 %final
  ret ptr %res
}

; ---------------------------------------------------------------- ciclo de vida

define i32 @fexl_ui_alive() {
entry:
  %p = load i32, ptr @FUI_PID
  %ok = icmp sgt i32 %p, 0
  %r = zext i1 %ok to i32
  ret i32 %r
}

define i32 @fexl_ui_start(ptr %bin, ptr %script) {
entry:
  %bn = icmp eq ptr %bin, null
  %sn = icmp eq ptr %script, null
  %bad = or i1 %bn, %sn
  br i1 %bad, label %fail, label %init
init:
  call void @signal(i32 13, ptr inttoptr (i64 1 to ptr))
  %bp = getelementptr [512 x i8], ptr @FUI_BIN, i32 0, i32 0
  call ptr @strncpy(ptr %bp, ptr %bin, i64 511)
  %sp = getelementptr [512 x i8], ptr @FUI_SCRIPT, i32 0, i32 0
  call ptr @strncpy(ptr %sp, ptr %script, i64 511)
  %to = alloca [2 x i32]
  %from = alloca [2 x i32]
  %tp = getelementptr [2 x i32], ptr %to, i32 0, i32 0
  %fp = getelementptr [2 x i32], ptr %from, i32 0, i32 0
  %rc1 = call i32 @pipe(ptr %tp)
  %p1 = icmp ne i32 %rc1, 0
  br i1 %p1, label %fail, label %pipe2
pipe2:
  %rc2 = call i32 @pipe(ptr %fp)
  %p2 = icmp ne i32 %rc2, 0
  br i1 %p2, label %close_to, label %do_fork
close_to:
  %t0a = getelementptr [2 x i32], ptr %to, i32 0, i32 0
  %t1a = getelementptr [2 x i32], ptr %to, i32 0, i32 1
  %v0a = load i32, ptr %t0a
  %v1a = load i32, ptr %t1a
  call i32 @close(i32 %v0a)
  call i32 @close(i32 %v1a)
  br label %fail
do_fork:
  %pid = call i32 @fork()
  %neg = icmp slt i32 %pid, 0
  br i1 %neg, label %fork_fail, label %is_child
is_child:
  %zero = icmp eq i32 %pid, 0
  br i1 %zero, label %child, label %parent
child:
  %t0c = getelementptr [2 x i32], ptr %to, i32 0, i32 0
  %t1c = getelementptr [2 x i32], ptr %to, i32 0, i32 1
  %f0c = getelementptr [2 x i32], ptr %from, i32 0, i32 0
  %f1c = getelementptr [2 x i32], ptr %from, i32 0, i32 1
  %v0c = load i32, ptr %t0c
  %v1c = load i32, ptr %t1c
  %f0v = load i32, ptr %f0c
  %f1v = load i32, ptr %f1c
  call i32 @dup2(i32 %v0c, i32 0)
  call i32 @dup2(i32 %f1v, i32 1)
  call i32 @dup2(i32 %f1v, i32 2)
  call i32 @close(i32 %v0c)
  call i32 @close(i32 %v1c)
  call i32 @close(i32 %f0v)
  call i32 @close(i32 %f1v)
  call i32 @execl(ptr %bin, ptr %bin, ptr %script, ptr null)
  call void @_exit(i32 127)
  ret i32 0
parent:
  store i32 %pid, ptr @FUI_PID
  %t0p = getelementptr [2 x i32], ptr %to, i32 0, i32 0
  %t1p = getelementptr [2 x i32], ptr %to, i32 0, i32 1
  %f0p = getelementptr [2 x i32], ptr %from, i32 0, i32 0
  %f1p = getelementptr [2 x i32], ptr %from, i32 0, i32 1
  %v0p = load i32, ptr %t0p
  %v1p = load i32, ptr %t1p
  %f0v2 = load i32, ptr %f0p
  %f1v2 = load i32, ptr %f1p
  call i32 @close(i32 %v0p)
  call i32 @close(i32 %f1v2)
  %in = call ptr @fdopen(i32 %v1p, ptr @FMT_WB)
  %out = call ptr @fdopen(i32 %f0v2, ptr @FMT_RB)
  store ptr %in, ptr @FUI_IN
  store ptr %out, ptr @FUI_OUT
  %inbad = icmp eq ptr %in, null
  %outbad = icmp eq ptr %out, null
  %badio = or i1 %inbad, %outbad
  br i1 %badio, label %io_fail, label %ok
io_fail:
  call void @fexl_ui_stop()
  br label %fail
ok:
  ret i32 1
fork_fail:
  %t0f = getelementptr [2 x i32], ptr %to, i32 0, i32 0
  %t1f = getelementptr [2 x i32], ptr %to, i32 0, i32 1
  %f0f = getelementptr [2 x i32], ptr %from, i32 0, i32 0
  %f1f = getelementptr [2 x i32], ptr %from, i32 0, i32 1
  %v0f = load i32, ptr %t0f
  %v1f = load i32, ptr %t1f
  %f0vf = load i32, ptr %f0f
  %f1vf = load i32, ptr %f1f
  call i32 @close(i32 %v0f)
  call i32 @close(i32 %v1f)
  call i32 @close(i32 %f0vf)
  call i32 @close(i32 %f1vf)
  store i32 -1, ptr @FUI_PID
  br label %fail
fail:
  ret i32 0
}

define void @fexl_ui_stop() {
entry:
  %pid = load i32, ptr @FUI_PID
  %live = icmp sgt i32 %pid, 0
  br i1 %live, label %kill_it, label %close_out
kill_it:
  %in = load ptr, ptr @FUI_IN
  %notnul = icmp ne ptr %in, null
  br i1 %notnul, label %do_close_in, label %do_kill
do_close_in:
  call i32 @fclose(ptr %in)
  br label %do_kill
do_kill:
  call i32 @kill(i32 %pid, i32 15)
  call i32 @waitpid(i32 %pid, ptr null, i32 0)
  store i32 -1, ptr @FUI_PID
  br label %close_out
close_out:
  store ptr null, ptr @FUI_IN
  %out = load ptr, ptr @FUI_OUT
  %on = icmp ne ptr %out, null
  br i1 %on, label %do_close_out, label %done
do_close_out:
  call i32 @fclose(ptr %out)
  store ptr null, ptr @FUI_OUT
  br label %done
done:
  ret void
}

; ---------------------------------------------------------------- un frame

; Devuelve 1 si el frame termino con '.', 0 si el pipe murio.
define internal i32 @fui_frame(i32 %ev, i32 %a, i32 %b, i32 %c,
                               ptr %out, ptr %errbuf, ptr %got_dot) {
entry:
  call ptr @memset(ptr %out, i32 0, i64 4116)
  %chp = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 0
  store i32 3, ptr %chp

  %pkt = alloca [4 x i8]
  %p0 = getelementptr [4 x i8], ptr %pkt, i32 0, i32 0
  %p1 = getelementptr [4 x i8], ptr %pkt, i32 0, i32 1
  %p2 = getelementptr [4 x i8], ptr %pkt, i32 0, i32 2
  %p3 = getelementptr [4 x i8], ptr %pkt, i32 0, i32 3
  %b0 = trunc i32 %ev to i8
  %b1 = trunc i32 %a to i8
  %b2 = trunc i32 %b to i8
  %b3 = trunc i32 %c to i8
  store i8 %b0, ptr %p0
  store i8 %b1, ptr %p1
  store i8 %b2, ptr %p2
  store i8 %b3, ptr %p3

  %pid = load i32, ptr @FUI_PID
  %live = icmp sgt i32 %pid, 0
  %in = load ptr, ptr @FUI_IN
  %outf = load ptr, ptr @FUI_OUT
  %inn = icmp eq ptr %in, null
  %outn = icmp eq ptr %outf, null
  %badio = or i1 %inn, %outn
  %goodio = xor i1 %badio, true
  %go = and i1 %live, %goodio
  br i1 %go, label %write, label %frame_done
write:
  %n = call i64 @fwrite(ptr %p0, i64 1, i64 4, ptr %in)
  %nok = icmp eq i64 %n, 4
  br i1 %nok, label %flush, label %frame_done
flush:
  %frc = call i32 @fflush(ptr %in)
  %fok = icmp eq i32 %frc, 0
  br i1 %fok, label %read_loop_init, label %frame_done

read_loop_init:
  %line = alloca [512 x i8]
  %lp = getelementptr [512 x i8], ptr %line, i32 0, i32 0
  br label %read_loop

read_loop:
  %got = call ptr @fgets(ptr %lp, i32 512, ptr %outf)
  %eof = icmp eq ptr %got, null
  br i1 %eof, label %frame_done, label %check_dot

check_dot:
  %l0 = load i8, ptr %lp
  %dot = icmp eq i8 %l0, 46
  br i1 %dot, label %check_nl, label %check_err
check_nl:
  %l1p = getelementptr i8, ptr %lp, i64 1
  %l1 = load i8, ptr %l1p
  %nl = icmp eq i8 %l1, 10
  %nul = icmp eq i8 %l1, 0
  %isdot = or i1 %nl, %nul
  br i1 %isdot, label %found_dot, label %check_err
found_dot:
  store i32 1, ptr %got_dot
  br label %frame_done

check_err:
  %u = call i64 @strncmp(ptr %lp, ptr @UNDEF, i64 16)
  %uis = icmp eq i64 %u, 0
  %sres = call ptr @strstr(ptr %lp, ptr @SYNTAX)
  %sis = icmp ne ptr %sres, null
  %iserr = or i1 %uis, %sis
  br i1 %iserr, label %save_err, label %parse_ch
save_err:
  call ptr @strncpy(ptr %errbuf, ptr %lp, i64 127)
  br label %read_loop

parse_ch:
  %r1 = call i32 (ptr, ptr, ...) @sscanf(ptr %lp, ptr @FMT_CH, ptr %chp)
  %o1 = icmp eq i32 %r1, 1
  br i1 %o1, label %read_loop, label %parse_tc
parse_tc:
  %tcp = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 1
  %r2 = call i32 (ptr, ptr, ...) @sscanf(ptr %lp, ptr @FMT_TC, ptr %tcp)
  %o2 = icmp eq i32 %r2, 1
  br i1 %o2, label %read_loop, label %parse_fw
parse_fw:
  %fwp = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 2
  %r3 = call i32 (ptr, ptr, ...) @sscanf(ptr %lp, ptr @FMT_FW, ptr %fwp)
  %o3 = icmp eq i32 %r3, 1
  br i1 %o3, label %read_loop, label %parse_status
parse_status:
  %stp = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 3, i32 0
  %r4 = call i32 (ptr, ptr, ...) @sscanf(ptr %lp, ptr @FMT_ST, ptr %stp)
  %o4 = icmp eq i32 %r4, 1
  br i1 %o4, label %read_loop, label %parse_log
parse_log:
  %lgp = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 4, i32 0
  %r5 = call i32 (ptr, ptr, ...) @sscanf(ptr %lp, ptr @FMT_LG, ptr %lgp)
  %o5 = icmp eq i32 %r5, 1
  br i1 %o5, label %read_loop, label %parse_spans

parse_spans:
  %sk = call i64 @strncmp(ptr %lp, ptr @SPANSK, i64 6)
  %issp = icmp eq i64 %sk, 0
  br i1 %issp, label %spans_init, label %parse_bind
spans_init:
  %p0s = getelementptr i8, ptr %lp, i64 6
  %endp = alloca ptr
  %style = call i64 @strtol(ptr %p0s, ptr %endp, i32 10)
  %e0 = load ptr, ptr %endp
  %same0 = icmp eq ptr %e0, %p0s
  br i1 %same0, label %read_loop, label %spans_skip
spans_skip:
  %sc = load i8, ptr %e0
  %isspc = icmp eq i8 %sc, 32
  %pnext = getelementptr i8, ptr %e0, i64 1
  %p = select i1 %isspc, ptr %pnext, ptr %e0
  br label %span_loop
span_loop:
  %nsSlot = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 7
  %ns = load i32, ptr %nsSlot
  %cap = icmp slt i32 %ns, 256
  br i1 %cap, label %span_body, label %read_loop
span_body:
  %sval = call i64 @strtol(ptr %p, ptr %endp, i32 10)
  %e1 = load ptr, ptr %endp
  %same1 = icmp eq ptr %e1, %p
  br i1 %same1, label %read_loop, label %span_comma
span_comma:
  %cch = load i8, ptr %e1
  %comma = icmp eq i8 %cch, 44
  br i1 %comma, label %span_second, label %read_loop
span_second:
  %pafter = getelementptr i8, ptr %e1, i64 1
  %eval = call i64 @strtol(ptr %pafter, ptr %endp, i32 10)
  %e2 = load ptr, ptr %endp
  %same2 = icmp eq ptr %e2, %pafter
  br i1 %same2, label %read_loop, label %span_store
span_store:
  %spanp = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 6, i32 %ns
  %stf = getelementptr inbounds %FmtSpan, ptr %spanp, i32 0, i32 0
  %lnf = getelementptr inbounds %FmtSpan, ptr %spanp, i32 0, i32 1
  %syf = getelementptr inbounds %FmtSpan, ptr %spanp, i32 0, i32 2
  %sv32 = trunc i64 %sval to i32
  %ev32 = trunc i64 %eval to i32
  %len = sub i32 %ev32, %sv32
  store i32 %sv32, ptr %stf
  store i32 %len, ptr %lnf
  %sy32 = trunc i64 %style to i32
  store i32 %sy32, ptr %syf
  %ns1 = add i32 %ns, 1
  store i32 %ns1, ptr %nsSlot
  %sep = load i8, ptr %e2
  %semi = icmp eq i8 %sep, 59
  br i1 %semi, label %span_advance, label %read_loop
span_advance:
  %padv = getelementptr i8, ptr %e2, i64 1
  br label %span_loop

parse_bind:
  %bk = call i64 @strncmp(ptr %lp, ptr @BINDK, i64 5)
  %isbd = icmp eq i64 %bk, 0
  br i1 %isbd, label %bind_chk, label %read_loop
bind_chk:
  %nbp = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 9
  %nb = load i32, ptr %nbp
  %bcap = icmp slt i32 %nb, 12
  br i1 %bcap, label %bind_body, label %read_loop
bind_body:
  %bstart = getelementptr i8, ptr %lp, i64 5
  %bidx = sext i32 %nb to i64
  %bp = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 8, i64 %bidx
  %kp = getelementptr inbounds %FuiBind, ptr %bp, i32 0, i32 0, i32 0
  %ap = getelementptr inbounds %FuiBind, ptr %bp, i32 0, i32 1, i32 0
  %afterk = call ptr @fui_token(ptr %kp, ptr %bstart, i64 16)
  %spc = load i8, ptr %afterk
  %iss = icmp eq i8 %spc, 32
  %askip = getelementptr i8, ptr %afterk, i64 1
  %actstart = select i1 %iss, ptr %askip, ptr %afterk
  call ptr @fui_token(ptr %ap, ptr %actstart, i64 32)
  %nb1 = add i32 %nb, 1
  store i32 %nb1, ptr %nbp
  br label %read_loop

frame_done:
  %dotv = load i32, ptr %got_dot
  ret i32 %dotv
}

; ---------------------------------------------------------------- eventos

define void @fexl_ui_event(i32 %ev, i32 %a, i32 %b, i32 %c, ptr %out) {
entry:
  %nul = icmp eq ptr %out, null
  br i1 %nul, label %done, label %init
init:
  %got = alloca i32
  store i32 0, ptr %got
  %errbuf = alloca [128 x i8]
  %ep = getelementptr [128 x i8], ptr %errbuf, i32 0, i32 0
  store i8 0, ptr %ep
  %binp = getelementptr [512 x i8], ptr @FUI_BIN, i32 0, i32 0
  %scrp = getelementptr [512 x i8], ptr @FUI_SCRIPT, i32 0, i32 0
  br label %attempt

attempt:
  %ok = call i32 @fui_frame(i32 %ev, i32 %a, i32 %b, i32 %c,
                             ptr %out, ptr %ep, ptr %got)
  %good = icmp eq i32 %ok, 1
  br i1 %good, label %save_good, label %failed

save_good:
  call ptr @memcpy(ptr @FUI_GOOD, ptr %out, i64 4116)
  store i32 1, ptr @FUI_HAS
  br label %done

failed:
  %e0 = load i8, ptr %ep
  %haserr = icmp ne i8 %e0, 0
  %oep = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 5, i32 0
  %oe = load i8, ptr %oep
  %oezero = icmp eq i8 %oe, 0
  %seterr = and i1 %haserr, %oezero
  br i1 %seterr, label %do_seterr, label %retry
do_seterr:
  call ptr @strncpy(ptr %oep, ptr %ep, i64 127)
  br label %retry

retry:
  %h = load i32, ptr @FUI_HAS
  %hash = icmp eq i32 %h, 1
  br i1 %hash, label %restore, label %restart
restore:
  call ptr @memcpy(ptr %out, ptr @FUI_GOOD, i64 4116)
  %dsterr = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 5, i32 0
  call ptr @strncpy(ptr %dsterr, ptr %ep, i64 127)
  br label %restart

restart:
  call void @fexl_ui_stop()
  %b0 = load i8, ptr %binp
  %bempty = icmp eq i8 %b0, 0
  br i1 %bempty, label %done, label %do_start
do_start:
  %r = call i32 @fexl_ui_start(ptr %binp, ptr %scrp)
  %started = icmp eq i32 %r, 1
  br i1 %started, label %attempt2, label %done

attempt2:
  store i32 0, ptr %got
  store i8 0, ptr %ep
  %ok2 = call i32 @fui_frame(i32 %ev, i32 %a, i32 %b, i32 %c,
                              ptr %out, ptr %ep, ptr %got)
  %good2 = icmp eq i32 %ok2, 1
  br i1 %good2, label %save_good2, label %failed2
failed2:
  %e2 = load i8, ptr %ep
  %haserr2 = icmp ne i8 %e2, 0
  %oep2 = getelementptr inbounds %UiFrame, ptr %out, i32 0, i32 5, i32 0
  %oe2 = load i8, ptr %oep2
  %oz2 = icmp eq i8 %oe2, 0
  %set2 = and i1 %haserr2, %oz2
  br i1 %set2, label %do_seterr2, label %done
do_seterr2:
  call ptr @strncpy(ptr %oep2, ptr %ep, i64 127)
  br label %done
save_good2:
  call ptr @memcpy(ptr @FUI_GOOD, ptr %out, i64 4116)
  store i32 1, ptr @FUI_HAS
  br label %done

done:
  ret void
}
