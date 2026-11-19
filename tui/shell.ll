; tui/shell.ll — chrome y estado de la TUI migrados de main.c.
;
; Los globals siguen en C (main.c) y se comparten como `external global`:
; eso mantiene una sola copia del estado y evita getters. main.c conserva
; solo main(), el loop, el hot reload, dispatch, send_event y el selftest.

%UiFrame = type { i32, i32, i32, [64 x i8], [256 x i8], [128 x i8],
                  [256 x %FmtSpan], i32, [12 x %FuiBind], i32 }
%FmtSpan = type { i32, i32, i32 }
%FuiBind = type { [16 x i8], [32 x i8] }
%SwiRect = type { i32, i32, i32, i32 }

; --- globals definidos en main.c ---
@g_ui              = external global %UiFrame
@g_tabs            = external global [16 x ptr]
@g_tab_focus       = external global [16 x i32]
@g_ntabs           = external global i32
@g_active          = external global i32
@g_focus           = external global i32
@g_clog            = external global [24 x [200 x i8]]
@g_clog_n          = external global i32
@g_cmd             = external global [256 x i8]
@g_cmd_len         = external global i32
@g_last_pattern    = external global [256 x i8]
@g_eval_msg        = external global [512 x i8]
@g_fm_rows         = external global i32
@g_fileman         = external global ptr
@g_script_mtime    = external global i64
@g_script_mtime_ns = external global i64

; --- C / libc ---
declare ptr   @malloc(i64)
declare void  @free(ptr)
declare ptr   @memset(ptr, i32, i64)
declare ptr   @memcpy(ptr, ptr, i64)
declare ptr   @strncpy(ptr, ptr, i64)
declare i64   @strlen(ptr)
declare i32   @strcmp(ptr, ptr)
declare ptr   @strrchr(ptr, i32)
declare i32   @snprintf(ptr, i64, ptr, ...)
declare i32   @getpid()
declare i32   @stat(ptr, ptr)
declare i64   @time(ptr)
declare ptr   @fopen(ptr, ptr)
declare i32   @fclose(ptr)
declare i64   @fwrite(ptr, i64, i64, ptr)

declare i32   @out_fill(i32, i32, i32, i32, i32, i32, i32, i32)
declare i32   @out_text(i32, i32, ptr, i32, i32, i32)
declare i32   @out_clear()
declare i32   @out_present()
declare i32   @out_cursor(i32, i32)
declare i32   @out_width()
declare i32   @out_height()

; --- motor IR ---
declare i32   @fexl_ui_alive()
declare void  @fexl_ui_event(i32, i32, i32, i32, ptr)
declare i32   @fexl_ui_start(ptr, ptr)
declare void  @fexl_ui_stop()
declare i32   @doc_read(ptr, i64, i64, ptr)
declare i64   @doc_length(ptr)
declare void  @win_editor_clear_spans(ptr)
declare ptr   @win_editor_fmt(ptr)
declare i32   @fmt_add_span(ptr, i64, i64, i64)
declare void  @win_editor_draw(ptr, i32, i32, i32, i32)
declare ptr   @win_editor_path(ptr)
declare i64   @win_editor_cursor(ptr)
declare void  @win_editor_set_cursor(ptr, i64, i64)
declare ptr   @win_editor_new(ptr)
declare ptr   @win_editor_new_empty(ptr)
declare i32   @win_editor_dirty(ptr)
declare ptr   @console_text(ptr)
declare i32   @console_prefix(ptr)
declare void  @console_reset(ptr, i32)
declare i32   @state_mode(ptr)
declare void  @canvas_layout(i32, i32, ptr, ptr, ptr)
declare void  @canvas_layout_panels(i32, i32, i32, i32, ptr, ptr, ptr, ptr)
declare ptr   @canvas_active(ptr)
declare i32   @window_rect(ptr, ptr)
declare void  @canvas_set_size(ptr, i32, i32)

declare ptr   @memory_new()
declare void  @memory_destroy(ptr)
declare i32   @memory_add(ptr, i32, ptr, i64, i64, i64)
declare i32   @memory_get(ptr, i32, ptr, ptr, ptr, ptr)
declare void  @memory_set_last_dir(ptr, ptr, i64)
declare ptr   @memory_last_dir(ptr, ptr)
declare i32   @memory_save(ptr, ptr)
declare i32   @memory_load(ptr, ptr)
declare i32   @fsio_ensure_dir(ptr)

declare ptr   @fileman_cwd(ptr)
declare void  @fileman_load(ptr)
declare i32   @fileman_chdir(ptr, ptr)
declare void  @fileman_set_cwd(ptr, ptr)
declare ptr   @fileman_name(ptr, i64)
declare i64   @fileman_count(ptr)
declare i64   @fileman_sel(ptr)
declare void  @fileman_draw(ptr, i32, i32, i32, i32)

; --- constantes ---
@MAX_TABS  = private constant i64 16
@MAX_LOG   = private constant i64 24
@MAX_NAMES = private constant i64 16
@FMT_PATH  = private constant [512 x i8] zeroinitializer
@SESSION_DIR = private constant [9 x i8] c"/tmp/swi\00"
@SESSION_PATH = private constant [17 x i8] c"/tmp/swi/session\00"
@FMT_FMTFILE = private constant [23 x i8] c"/tmp/swi_fmt_input.txt\00"
@FMT_WB = private constant [3 x i8] c"wb\00"
@FMT_D = private constant [3 x i8] c"%d\00"
@FMT_LD = private constant [6 x i8] c"%d,%d\00"
@FMT_LD3 = private constant [9 x i8] c"%d,%d,%d\00"
@FMT_TABS = private constant [11 x i8] c"[%d/%d] %s\00"
@FMT_TAB1 = private constant [10 x i8] c"[%d]%s%s \00"
@FMT_FILES = private constant [11 x i8] c"[files] %s\00"
@FMT_LOGCMD = private constant [5 x i8] c"%c%s\00"
@FMT_STATUS = private constant [29 x i8] c"-- %s --%s  %dx%d%s  fexl:%s\00"
@HINT = private constant [29 x i8] c"  i=insert  :w=save  :q=quit\00"
@HINT_INS = private constant [13 x i8] c"  ESC=normal\00"
@UNTITLED_FMT = private constant [28 x i8] c"/tmp/swi_untitled_%d_%d.txt\00"
@DOT = private constant [2 x i8] c".\00"
@SLASH = private constant [2 x i8] c"/\00"
@ACTIVE0 = private constant [2 x i8] c"0\00"
@DIRTY = private constant [2 x i8] c"+\00"
@EMPTY = private constant [1 x i8] c"\00"
@KIND_EDITOR = private constant i32 69
@KIND_ACTIVE = private constant i32 65
@KIND_LAYOUT = private constant i32 76

; -------------------------------------------------------------- log / foco

define void @shell_log_add(ptr %s) {
entry:
  %nul = icmp eq ptr %s, null
  br i1 %nul, label %done, label %first
first:
  %c = load i8, ptr %s
  %empty = icmp eq i8 %c, 0
  br i1 %empty, label %done, label %full_chk
full_chk:
  %np = getelementptr i32, ptr @g_clog_n, i32 0
  %n = load i32, ptr %np
  %is24 = icmp eq i32 %n, 24
  br i1 %is24, label %shift, label %store
shift:
  %i = alloca i32
  store i32 1, ptr %i
  br label %shift_loop
shift_loop:
  %iv = load i32, ptr %i
  %cont = icmp slt i32 %iv, 24
  br i1 %cont, label %shift_body, label %shift_done
shift_body:
  %src = getelementptr [24 x [200 x i8]], ptr @g_clog, i32 0, i32 %iv
  %dst = getelementptr [24 x [200 x i8]], ptr @g_clog, i32 0, i32 %iv, i32 0
  %pre = sub i32 %iv, 1
  %dest = getelementptr [24 x [200 x i8]], ptr @g_clog, i32 0, i32 %pre, i32 0
  call ptr @memcpy(ptr %dest, ptr %src, i64 200)
  %i1 = add i32 %iv, 1
  store i32 %i1, ptr %i
  br label %shift_loop
shift_done:
  store i32 23, ptr %np
  br label %store
store:
  %n2 = load i32, ptr %np
  %slot = getelementptr [24 x [200 x i8]], ptr @g_clog, i32 0, i32 %n2, i32 0
  call ptr @strncpy(ptr %slot, ptr %s, i64 199)
  %term = getelementptr i8, ptr %slot, i64 199
  store i8 0, ptr %term
  %n3 = add i32 %n2, 1
  store i32 %n3, ptr %np
  br label %done
done:
  ret void
}

define void @shell_set_focus(i32 %f) {
entry:
  store i32 %f, ptr @g_focus
  ret void
}

define i32 @shell_has_bind(ptr %act) {
entry:
  %fp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 9
  %nb = load i32, ptr %fp
  %pos = icmp sgt i32 %nb, 0
  br i1 %pos, label %loop_init, label %no
loop_init:
  %i = alloca i32
  store i32 0, ptr %i
  br label %loop
loop:
  %iv = load i32, ptr %i
  %nb2 = load i32, ptr %fp
  %cont = icmp slt i32 %iv, %nb2
  br i1 %cont, label %body, label %no
body:
  %bidx = sext i32 %iv to i64
  %bp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 8, i64 %bidx
  %ap = getelementptr inbounds %FuiBind, ptr %bp, i32 0, i32 1, i32 0
  %r = call i32 @strcmp(ptr %ap, ptr %act)
  %hit = icmp eq i32 %r, 0
  br i1 %hit, label %yes, label %next
yes:
  ret i32 1
next:
  %i1 = add i32 %iv, 1
  store i32 %i1, ptr %i
  br label %loop
no:
  ret i32 0
}

define void @shell_ui_sync(i32 %ev, i32 %a, i32 %b, i32 %c) {
entry:
  %chp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 0
  %tcp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 1
  %fwp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 2
  %ch = load i32, ptr %chp
  %tc = load i32, ptr %tcp
  %fw = load i32, ptr %fwp
  call void @fexl_ui_event(i32 %ev, i32 %a, i32 %b, i32 %c, ptr @g_ui)
  %alive = call i32 @fexl_ui_alive()
  %az = icmp eq i32 %alive, 0
  br i1 %az, label %apply, label %log
log:
  %lgp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 4, i32 0
  call void @shell_log_add(ptr %lgp)
  br label %apply
apply:
  ; g_ui.fileman_w decide si el panel existe; el resto ya esta en g_ui.
  ret void
}

; -------------------------------------------------------------- tabs

define void @shell_tab_new(ptr %path) {
entry:
  %np = getelementptr i32, ptr @g_ntabs, i32 0
  %n = load i32, ptr %np
  %full = icmp sge i32 %n, 16
  br i1 %full, label %done, label %path_chk
path_chk:
  %pn = icmp eq ptr %path, null
  br i1 %pn, label %untitled, label %given
untitled:
  %buf = alloca [128 x i8]
  %bp = getelementptr [128 x i8], ptr %buf, i32 0, i32 0
  %pid = call i32 @getpid()
  %cnt = call i32 @shell_next_counter()
  %r = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 128,
                                               ptr @UNTITLED_FMT, i32 %pid, i32 %cnt)
  %ed = call ptr @win_editor_new_empty(ptr %bp)
  br label %install
given:
  %ed2 = call ptr @win_editor_new(ptr %path)
  br label %install2
install:
  br label %install2
install2:
  %editor = phi ptr [ %ed, %install ], [ %ed2, %given ]
  %en = icmp eq ptr %editor, null
  br i1 %en, label %done, label %store
store:
  %idx = sext i32 %n to i64
  %slot = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %idx
  store ptr %editor, ptr %slot
  %fslot = getelementptr [16 x i32], ptr @g_tab_focus, i32 0, i64 %idx
  store i32 0, ptr %fslot
  %n1 = add i32 %n, 1
  store i32 %n1, ptr %np
  store i32 %n, ptr @g_active
  store i32 0, ptr @g_focus
  call void @shell_ui_sync(i32 116, i32 0, i32 0, i32 0)
  br label %done
done:
  ret void
}

@SHELL_COUNTER = private global i32 0
define internal i32 @shell_next_counter() {
entry:
  %v = load i32, ptr @SHELL_COUNTER
  %v1 = add i32 %v, 1
  store i32 %v1, ptr @SHELL_COUNTER
  ret i32 %v
}

define void @shell_tab_close() {
entry:
  %np = getelementptr i32, ptr @g_ntabs, i32 0
  %n = load i32, ptr %np
  %one = icmp sle i32 %n, 1
  br i1 %one, label %done, label %destroy
destroy:
  %ap = getelementptr i32, ptr @g_active, i32 0
  %act = load i32, ptr %ap
  %aidx = sext i32 %act to i64
  %slot = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %aidx
  %ed = load ptr, ptr %slot
  call void @win_editor_destroy(ptr %ed)
  %shift = alloca i32
  store i32 %act, ptr %shift
  br label %shift_loop
shift_loop:
  %iv = load i32, ptr %shift
  %n2 = load i32, ptr %np
  %last = sub i32 %n2, 1
  %cont = icmp slt i32 %iv, %last
  br i1 %cont, label %shift_body, label %finish
shift_body:
  %i1 = add i32 %iv, 1
  %s1 = sext i32 %iv to i64
  %s2 = sext i32 %i1 to i64
  %dst = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %s1
  %src = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %s2
  %v = load ptr, ptr %src
  store ptr %v, ptr %dst
  %fd = getelementptr [16 x i32], ptr @g_tab_focus, i32 0, i64 %s1
  %fs = getelementptr [16 x i32], ptr @g_tab_focus, i32 0, i64 %s2
  %fv = load i32, ptr %fs
  store i32 %fv, ptr %fd
  store i32 %i1, ptr %shift
  br label %shift_loop
finish:
  %n3 = load i32, ptr %np
  %n4 = sub i32 %n3, 1
  store i32 %n4, ptr %np
  %act2 = load i32, ptr %ap
  %big = icmp sge i32 %act2, %n4
  br i1 %big, label %clamp, label %focus
clamp:
  store i32 %n4, ptr %ap
  br label %focus
focus:
  %act3 = load i32, ptr %ap
  %aidx3 = sext i32 %act3 to i64
  %fs3 = getelementptr [16 x i32], ptr @g_tab_focus, i32 0, i64 %aidx3
  %fv3 = load i32, ptr %fs3
  call void @shell_set_focus(i32 %fv3)
  call void @shell_ui_sync(i32 116, i32 0, i32 0, i32 0)
  br label %done
done:
  ret void
}

declare void @win_editor_destroy(ptr)

; -------------------------------------------------------------- session

define void @shell_session_save() {
entry:
  %m = call ptr @memory_new()
  %mn = icmp eq ptr %m, null
  br i1 %mn, label %done, label %ensure_dir
ensure_dir:
  call i32 @fsio_ensure_dir(ptr @SESSION_DIR)
  %np = getelementptr i32, ptr @g_ntabs, i32 0
  %n = load i32, ptr %np
  %ip = alloca i32
  store i32 0, ptr %ip
  br label %tab_loop
tab_loop:
  %iv = load i32, ptr %ip
  %cont = icmp slt i32 %iv, %n
  br i1 %cont, label %tab_body, label %active
tab_body:
  %idx = sext i32 %iv to i64
  %slot = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %idx
  %ed = load ptr, ptr %slot
  %path = call ptr @win_editor_path(ptr %ed)
  %plen = call i64 @strlen(ptr %path)
  %cur = call i64 @win_editor_cursor(ptr %ed)
  %fslot = getelementptr [16 x i32], ptr @g_tab_focus, i32 0, i64 %idx
  %fv = load i32, ptr %fslot
  %fv64 = sext i32 %fv to i64
  call i32 @memory_add(ptr %m, i32 69, ptr %path, i64 %plen, i64 %cur, i64 %fv64)
  %i1 = add i32 %iv, 1
  store i32 %i1, ptr %ip
  br label %tab_loop
active:
  %buf = alloca [128 x i8]
  %bp = getelementptr [128 x i8], ptr %buf, i32 0, i32 0
  %act = load i32, ptr @g_active
  %r1 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 128, ptr @FMT_D, i32 %act)
  call i32 @memory_add(ptr %m, i32 65, ptr %bp, i64 1, i64 0, i64 0)
  %chp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 0
  %tcp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 1
  %fwp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 2
  %ch = load i32, ptr %chp
  %tc = load i32, ptr %tcp
  %fw = load i32, ptr %fwp
  %r2 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 128,
                  ptr @FMT_LD3, i32 %ch, i32 %tc, i32 %fw)
  %l2 = call i64 @strlen(ptr %bp)
  call i32 @memory_add(ptr %m, i32 76, ptr %bp, i64 %l2, i64 0, i64 0)
  %fm = load ptr, ptr @g_fileman
  %cwd = call ptr @fileman_cwd(ptr %fm)
  %cl = call i64 @strlen(ptr %cwd)
  call void @memory_set_last_dir(ptr %m, ptr %cwd, i64 %cl)
  call i32 @memory_save(ptr %m, ptr @SESSION_PATH)
  call void @memory_destroy(ptr %m)
  br label %done
done:
  ret void
}

declare i32 @atoi(ptr)
declare i32 @sscanf(ptr, ptr, ...)

define void @shell_session_load() {
entry:
  %m = call ptr @memory_new()
  %mn = icmp eq ptr %m, null
  br i1 %mn, label %done, label %load
load:
  call i32 @memory_load(ptr %m, ptr @SESSION_PATH)
  %ip = alloca i32
  store i32 0, ptr %ip
  br label %loop
loop:
  %iv = load i32, ptr %ip
  %lim = icmp slt i32 %iv, 256
  br i1 %lim, label %get, label %cwd
get:
  %p = alloca ptr
  %cur = alloca i64
  %top = alloca i64
  %kind = alloca i32
  store ptr null, ptr %p
  %r = call i32 @memory_get(ptr %m, i32 %iv, ptr %p, ptr %cur, ptr %top, ptr %kind)
  %ok = icmp eq i32 %r, 1
  br i1 %ok, label %have, label %cwd
have:
  %pv = load ptr, ptr %p
  %pn = icmp eq ptr %pv, null
  br i1 %pn, label %next, label %kind_chk
kind_chk:
  %k = load i32, ptr %kind
  %ised = icmp eq i32 %k, 69
  br i1 %ised, label %do_tab, label %other
do_tab:
  %c0 = load i8, ptr %pv
  %empty = icmp eq i8 %c0, 0
  %argp = select i1 %empty, ptr null, ptr %pv
  call void @shell_tab_new(ptr %argp)
  %np2 = getelementptr i32, ptr @g_ntabs, i32 0
  %n2 = load i32, ptr %np2
  %last = sub i32 %n2, 1
  %idx = sext i32 %last to i64
  %slot = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %idx
  %ed = load ptr, ptr %slot
  %cv = load i64, ptr %cur
  call void @win_editor_set_cursor(ptr %ed, i64 %cv, i64 0)
  %tv = load i64, ptr %top
  %tv32 = trunc i64 %tv to i32
  %fslot = getelementptr [16 x i32], ptr @g_tab_focus, i32 0, i64 %idx
  store i32 %tv32, ptr %fslot
  br label %next
other:
  %isact = icmp eq i32 %k, 65
  br i1 %isact, label %do_active, label %layout
do_active:
  %a = call i32 @atoi(ptr %pv)
  %np3 = getelementptr i32, ptr @g_ntabs, i32 0
  %n3 = load i32, ptr %np3
  %in = icmp sge i32 %a, 0
  %lt = icmp slt i32 %a, %n3
  %both = and i1 %in, %lt
  br i1 %both, label %set_active, label %next
set_active:
  store i32 %a, ptr @g_active
  br label %next
layout:
  %islay = icmp eq i32 %k, 76
  br i1 %islay, label %do_layout, label %next
do_layout:
  %chp = alloca i32
  %tcp = alloca i32
  %fwp = alloca i32
  %lr = call i32 (ptr, ptr, ...) @sscanf(ptr %pv, ptr @FMT_LD3,
                                         ptr %chp, ptr %tcp, ptr %fwp)
  %lok = icmp eq i32 %lr, 3
  br i1 %lok, label %apply_layout, label %next
apply_layout:
  %chv = load i32, ptr %chp
  %tcv = load i32, ptr %tcp
  %fwv = load i32, ptr %fwp
  %gch = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 0
  %gtc = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 1
  %gfw = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 2
  store i32 %chv, ptr %gch
  store i32 %tcv, ptr %gtc
  store i32 %fwv, ptr %gfw
  br label %next
next:
  %i1 = add i32 %iv, 1
  store i32 %i1, ptr %ip
  br label %loop
cwd:
  %dlen = alloca i64
  store i64 0, ptr %dlen
  %dir = call ptr @memory_last_dir(ptr %m, ptr %dlen)
  %dl = load i64, ptr %dlen
  %hasdir = icmp ne ptr %dir, null
  %haslen = icmp sgt i64 %dl, 0
  %has = and i1 %hasdir, %haslen
  br i1 %has, label %do_wd, label %reset_focus
do_wd:
  %wdrc = call i32 @shell_wd_apply(ptr %dir, i32 1)
  %failed = icmp ne i32 %wdrc, 1
  br i1 %failed, label %wd_fail, label %reset_focus
wd_fail:
  %fm = load ptr, ptr @g_fileman
  call void @fileman_set_cwd(ptr %fm, ptr @DOT)
  call void @fileman_load(ptr %fm)
  br label %reset_focus
reset_focus:
  store i32 0, ptr @g_focus
  %fi = alloca i32
  store i32 0, ptr %fi
  br label %focus_loop
focus_loop:
  %fv2 = load i32, ptr %fi
  %c = icmp slt i32 %fv2, 16
  br i1 %c, label %focus_body, label %focus_done
focus_body:
  %fs = getelementptr [16 x i32], ptr @g_tab_focus, i32 0, i32 %fv2
  store i32 0, ptr %fs
  %f1 = add i32 %fv2, 1
  store i32 %f1, ptr %fi
  br label %focus_loop
focus_done:
  %fm2 = load ptr, ptr @g_fileman
  call void @fileman_load(ptr %fm2)
  call void @memory_destroy(ptr %m)
  br label %done
done:
  ret void
}

@FMT_WD = private constant [7 x i8] c"wd: %s\00"
@FMT_FAIL = private constant [21 x i8] c"no puedo entrar a %s\00"

define i32 @shell_wd_apply(ptr %path, i32 %quiet) {
entry:
  %fm = load ptr, ptr @g_fileman
  %pn = icmp eq ptr %path, null
  %cwd = call ptr @fileman_cwd(ptr %fm)
  %target = select i1 %pn, ptr %cwd, ptr %path
  %c = load i8, ptr %target
  %empty = icmp eq i8 %c, 0
  br i1 %empty, label %fail, label %do_chdir
do_chdir:
  %rc = call i32 @fileman_chdir(ptr %fm, ptr %target)
  %ok = icmp eq i32 %rc, 1
  br i1 %ok, label %success, label %fail
success:
  %q1 = icmp eq i32 %quiet, 1
  br i1 %q1, label %yes, label %log_ok
log_ok:
  %buf = alloca [640 x i8]
  %bp = getelementptr [640 x i8], ptr %buf, i32 0, i32 0
  %nc = call ptr @fileman_cwd(ptr %fm)
  %rr = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 640,
                                                ptr @FMT_WD, ptr %nc)
  call void @shell_log_add(ptr %bp)
  br label %yes
fail:
  %q2 = icmp eq i32 %quiet, 1
  br i1 %q2, label %no, label %log_fail
log_fail:
  %buf2 = alloca [640 x i8]
  %bp2 = getelementptr [640 x i8], ptr %buf2, i32 0, i32 0
  %rr2 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp2, i64 640,
                                                 ptr @FMT_FAIL, ptr %target)
  call void @shell_log_add(ptr %bp2)
  br label %no
yes:
  ret i32 1
no:
  ret i32 0
}

; -------------------------------------------------------------- formato

declare ptr @win_editor_doc(ptr)

define void @shell_fmt_send(ptr %ed) {
entry:
  %alive = call i32 @fexl_ui_alive()
  %az = icmp eq i32 %alive, 0
  br i1 %az, label %done, label %open
open:
  %fp = call ptr @fopen(ptr @FMT_FMTFILE, ptr @FMT_WB)
  %fn = icmp eq ptr %fp, null
  br i1 %fn, label %done, label %read_init
read_init:
  %doc = call ptr @win_editor_doc(ptr %ed)
  %len = call i64 @doc_length(ptr %doc)
  %buf = alloca [4096 x i8]
  %bp = getelementptr [4096 x i8], ptr %buf, i32 0, i32 0
  %off = alloca i64
  store i64 0, ptr %off
  br label %read_loop
read_loop:
  %o = load i64, ptr %off
  %more = icmp slt i64 %o, %len
  br i1 %more, label %read_body, label %read_done
read_body:
  %got = call i64 @doc_read(ptr %doc, i64 %o, i64 4096, ptr %bp)
  %nonpos = icmp sle i64 %got, 0
  br i1 %nonpos, label %read_done, label %write_body
write_body:
  %n = call i64 @fwrite(ptr %bp, i64 1, i64 %got, ptr %fp)
  %o1 = add i64 %o, %got
  store i64 %o1, ptr %off
  br label %read_loop
read_done:
  %fc = call i32 @fclose(ptr %fp)
  %frame = alloca [4116 x i8]
  %fr = getelementptr [4116 x i8], ptr %frame, i32 0, i32 0
  call ptr @memset(ptr %fr, i32 0, i64 4116)
  %chp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 0
  %tcp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 1
  %fwp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 2
  %ch = load i32, ptr %chp
  %tc = load i32, ptr %tcp
  %fw = load i32, ptr %fwp
  %ff = bitcast [4116 x i8]* %frame to %UiFrame*
  call void @fexl_ui_event(i32 70, i32 %ch, i32 %tc, i32 %fw, ptr %ff)
  call void @win_editor_clear_spans(ptr %ed)
  %fmt = call ptr @win_editor_fmt(ptr %ed)
  %ns = getelementptr inbounds %UiFrame, ptr %ff, i32 0, i32 7
  %nspan = load i32, ptr %ns
  %i = alloca i32
  store i32 0, ptr %i
  br label %span_loop
span_loop:
  %iv = load i32, ptr %i
  %cont = icmp slt i32 %iv, %nspan
  br i1 %cont, label %span_body, label %done
span_body:
  %idx = sext i32 %iv to i64
  %sp = getelementptr inbounds %UiFrame, ptr %ff, i32 0, i32 6, i64 %idx
  %st = getelementptr inbounds %FmtSpan, ptr %sp, i32 0, i32 0
  %ln = getelementptr inbounds %FmtSpan, ptr %sp, i32 0, i32 1
  %sy = getelementptr inbounds %FmtSpan, ptr %sp, i32 0, i32 2
  %sv = load i32, ptr %st
  %lv = load i32, ptr %ln
  %yv = load i32, ptr %sy
  %sv64 = sext i32 %sv to i64
  %lv64 = sext i32 %lv to i64
  %yv64 = sext i32 %yv to i64
  call i32 @fmt_add_span(ptr %fmt, i64 %sv64, i64 %lv64, i64 %yv64)
  %i1 = add i32 %iv, 1
  store i32 %i1, ptr %i
  br label %span_loop
done:
  ret void
}

; -------------------------------------------------------------- toggles

define void @shell_toggle_console() {
entry:
  %chp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 0
  %ch = load i32, ptr %chp
  %on = icmp sgt i32 %ch, 0
  br i1 %on, label %to0, label %sync
to0:
  call void @shell_set_focus(i32 0)
  br label %sync
sync:
  %tcp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 1
  %fwp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 2
  %tc = load i32, ptr %tcp
  %fw = load i32, ptr %fwp
  call void @shell_ui_sync(i32 50, i32 %ch, i32 %tc, i32 %fw)
  %newch = load i32, ptr %chp
  %on2 = icmp sgt i32 %newch, 0
  br i1 %on2, label %focus1, label %done
focus1:
  call void @shell_set_focus(i32 1)
  br label %done
done:
  ret void
}

define void @shell_toggle_fileman() {
entry:
  %fwp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 2
  %fw = load i32, ptr %fwp
  %on = icmp sgt i32 %fw, 0
  br i1 %on, label %to0, label %sync
to0:
  call void @shell_set_focus(i32 0)
  br label %sync
sync:
  %chp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 0
  %tcp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 1
  %ch = load i32, ptr %chp
  %tc = load i32, ptr %tcp
  call void @shell_ui_sync(i32 51, i32 %ch, i32 %tc, i32 %fw)
  %newfw = load i32, ptr %fwp
  %on2 = icmp sgt i32 %newfw, 0
  br i1 %on2, label %loadfm, label %done
loadfm:
  %fm = load ptr, ptr @g_fileman
  call void @fileman_load(ptr %fm)
  call void @shell_set_focus(i32 2)
  br label %done
done:
  ret void
}

define void @shell_toggle_tabs() {
entry:
  %chp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 0
  %tcp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 1
  %fwp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 2
  %ch = load i32, ptr %chp
  %tc = load i32, ptr %tcp
  %fw = load i32, ptr %fwp
  call void @shell_ui_sync(i32 52, i32 %ch, i32 %tc, i32 %fw)
  ret void
}
