; tui/draw.ll — dibujo de paneles y fileman_open (migrado de main.c).
; Comparte los globals de main.c como external global, igual que shell.ll.

%UiFrame = type { i32, i32, i32, [64 x i8], [256 x i8], [128 x i8],
                  [256 x %FmtSpan], i32, [12 x %FuiBind], i32 }
%FmtSpan = type { i32, i32, i32 }
%FuiBind = type { [16 x i8], [32 x i8] }
%SwiRect = type { i32, i32, i32, i32 }
%SwiAction = type { i32, i64, i64, i64 }

@g_ui      = external global %UiFrame
@g_tabs    = external global [16 x ptr]
@g_tab_focus = external global [16 x i32]
@g_ntabs   = external global i32
@g_active  = external global i32
@g_focus   = external global i32
@g_clog    = external global [24 x [200 x i8]]
@g_clog_n  = external global i32
@g_cmd     = external global [256 x i8]
@g_fm_rows = external global i32
@g_fileman = external global ptr
@g_last_pattern = external global [256 x i8]
@g_eval_msg = external global [512 x i8]

declare ptr   @memset(ptr, i32, i64)
declare ptr   @strncpy(ptr, ptr, i64)
declare i64   @strlen(ptr)
declare i32   @strcmp(ptr, ptr)
declare ptr   @strrchr(ptr, i32)
declare i32   @snprintf(ptr, i64, ptr, ...)

declare i32   @out_cell(i32, i32, i32, i32, i32, i32)
declare i32   @out_fill(i32, i32, i32, i32, i32, i32, i32, i32)
declare i32   @out_text(i32, i32, ptr, i32, i32, i32)
declare i32   @out_clear()
declare i32   @out_present()
declare i32   @out_cursor(i32, i32)
declare i32   @out_width()
declare i32   @out_height()

declare ptr   @fsio_path_join(ptr, ptr)
declare ptr   @fileman_cwd(ptr)
declare ptr   @fileman_name(ptr, i64)
declare i64   @fileman_count(ptr)
declare i64   @fileman_sel(ptr)
declare void  @fileman_parent(ptr)
declare i32   @fileman_is_dir(ptr, ptr)
declare void  @fileman_set_cwd(ptr, ptr)
declare void  @fileman_load(ptr)
declare void  @fileman_draw(ptr, i32, i32, i32, i32)

declare ptr   @win_editor_path(ptr)
declare i32   @win_editor_dirty(ptr)
declare i32   @win_editor_open(ptr, ptr)
declare void  @win_editor_set_highlight(ptr, ptr, i64)
declare i32   @win_editor_step(ptr, ptr)
declare void  @win_editor_draw(ptr, i32, i32, i32, i32)
declare ptr   @console_text(ptr)
declare i32   @console_prefix(ptr)
declare void  @console_reset(ptr, i32)
declare void  @console_push(ptr, i64)
declare i32   @console_execute(ptr, ptr)
declare i32   @console_repeat(ptr, ptr, i32)
declare i32   @state_mode(ptr)
declare void  @state_set_mode(ptr, i32)
declare ptr   @swi_eval_output()
declare void  @canvas_set_size(ptr, i32, i32)
declare void  @canvas_layout(i32, i32, ptr, ptr, ptr)
declare void  @canvas_layout_panels(i32, i32, i32, i32, ptr, ptr, ptr, ptr)
declare ptr   @canvas_active(ptr)
declare i32   @window_rect(ptr, ptr)

declare void  @shell_log_add(ptr)
declare void  @shell_tab_new(ptr)
declare void  @shell_set_focus(i32)
declare void  @shell_ui_sync(i32, i32, i32, i32)
declare void  @shell_fmt_send(ptr)

@DOT = private constant [3 x i8] c"..\00"
@SLASH = private constant [2 x i8] c"/\00"
@UNTITLED = private constant [9 x i8] c"untitled\00"
@OPEN = private constant [8 x i8] c"open %s\00"
@CANT_OPEN = private constant [18 x i8] c"no puedo abrir %s\00"
@FMT_TABS_COL = private constant [11 x i8] c"[%d/%d] %s\00"
@FMT_TAB = private constant [10 x i8] c"[%d]%s%s \00"
@DASH = private constant [2 x i8] c"+\00"
@FMT_CONS_HDR = private constant [13 x i8] c"[consola] %s\00"
@CONS_HINT0 = private constant [21 x i8] c"F2/F3/F4  Ctrl+T tab\00"
@CONS_HINT1 = private constant [25 x i8] c"F2 extiende  F3 archivos\00"
@CONS_EMPTY = private constant [48 x i8] c"(sin salida)  escribe una expresion Fexl con F2\00"
@FMT_PROMPT = private constant [5 x i8] c"> %s\00"
@SWI = private constant [4 x i8] c"swi\00"
@MODE_Q = private constant [2 x i8] c"?\00"
@EMPTY = private constant [1 x i8] c"\00"
@HINT0 = private constant [29 x i8] c"  i=insert  :w=save  :q=quit\00"
@HINT1 = private constant [13 x i8] c"  ESC=normal\00"
@FMT_BOTTOM = private constant [5 x i8] c"%c%s\00"
@FMT_STATUS = private constant [29 x i8] c"-- %s --%s  %dx%d%s  fexl:%s\00"
@DIRTY_TAG = private constant [5 x i8] c" [+]\00"

; -------------------------------------------------------------- fileman_open

define void @shell_fileman_open(i32 %new_tab) {
entry:
  %fm = load ptr, ptr @g_fileman
  %cnt = call i64 @fileman_count(ptr %fm)
  %zero = icmp sle i64 %cnt, 0
  br i1 %zero, label %done, label %get_name
get_name:
  %sel = call i64 @fileman_sel(ptr %fm)
  %name = call ptr @fileman_name(ptr %fm, i64 %sel)
  %isup = call i32 @strcmp(ptr %name, ptr @DOT)
  %up = icmp eq i32 %isup, 0
  br i1 %up, label %parent, label %join
parent:
  call void @fileman_parent(ptr %fm)
  br label %done
join:
  %cwd = call ptr @fileman_cwd(ptr %fm)
  %full = call ptr @fsio_path_join(ptr %cwd, ptr %name)
  %nul = icmp eq ptr %full, null
  br i1 %nul, label %done, label %isdir
isdir:
  %d = call i32 @fileman_is_dir(ptr %fm, ptr %name)
  %yes = icmp eq i32 %d, 1
  br i1 %yes, label %enter, label %open_file
enter:
  call void @fileman_set_cwd(ptr %fm, ptr %full)
  call void @fileman_load(ptr %fm)
  br label %cleanup
open_file:
  %buf = alloca [512 x i8]
  %bp = getelementptr [512 x i8], ptr %buf, i32 0, i32 0
  %r1 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 512,
                                                ptr @OPEN, ptr %full)
  call void @shell_log_add(ptr %bp)
  %nt = icmp ne i32 %new_tab, 0
  br i1 %nt, label %newtab, label %same_tab
newtab:
  call void @shell_tab_new(ptr %full)
  br label %focus0
same_tab:
  %ap = getelementptr i32, ptr @g_active, i32 0
  %act = load i32, ptr %ap
  %aidx = sext i32 %act to i64
  %slot = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %aidx
  %ed = load ptr, ptr %slot
  %rc = call i32 @win_editor_open(ptr %ed, ptr %full)
  %bad = icmp eq i32 %rc, 0
  br i1 %bad, label %log_fail, label %focus0
log_fail:
  %r2 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 512,
                                                ptr @CANT_OPEN, ptr %full)
  call void @shell_log_add(ptr %bp)
  br label %focus0
focus0:
  call void @shell_set_focus(i32 0)
  br label %cleanup
cleanup:
  call void @free(ptr %full)
  br label %done
done:
  ret void
}
declare void @free(ptr)

; -------------------------------------------------------------- draw_tabs

define void @shell_draw_tabs(ptr %r) {
entry:
  %hp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 3
  %h = load i32, ptr %hp
  %vis = icmp sgt i32 %h, 0
  br i1 %vis, label %fill, label %done
fill:
  %xp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 0
  %yp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 1
  %wp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 2
  %x0 = load i32, ptr %xp
  %y0 = load i32, ptr %yp
  %w0 = load i32, ptr %wp
  call i32 @out_fill(i32 %x0, i32 %y0, i32 %w0, i32 %h, i32 32,
                     i32 8, i32 5, i32 0)
  %tcp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 1
  %collapsed = load i32, ptr %tcp
  %cl = icmp ne i32 %collapsed, 0
  br i1 %cl, label %collapsed_draw, label %normal_draw
collapsed_draw:
  %actp = getelementptr i32, ptr @g_active, i32 0
  %act = load i32, ptr %actp
  %aidx = sext i32 %act to i64
  %slot = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %aidx
  %ed = load ptr, ptr %slot
  %p = call ptr @win_editor_path(ptr %ed)
  %pn = icmp eq ptr %p, null
  %path = select i1 %pn, ptr @UNTITLED, ptr %p
  %buf = alloca [160 x i8]
  %bp = getelementptr [160 x i8], ptr %buf, i32 0, i32 0
  %a1 = add i32 %act, 1
  %n = load i32, ptr @g_ntabs
  %r2 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 160,
                   ptr @FMT_TABS_COL, i32 %a1, i32 %n, ptr %path)
  %x1 = add i32 %x0, 1
  call i32 @out_text(i32 %x1, i32 %y0, ptr %bp, i32 16, i32 5, i32 1)
  br label %done
normal_draw:
  %x = alloca i32
  %xinit = add i32 %x0, 1
  store i32 %xinit, ptr %x
  %i = alloca i32
  store i32 0, ptr %i
  br label %loop
loop:
  %iv = load i32, ptr %i
  %n2 = load i32, ptr @g_ntabs
  %more = icmp slt i32 %iv, %n2
  %xv = load i32, ptr %x
  %edge = sub i32 %x0, 4
  %edge2 = add i32 %w0, %edge
  %fit = icmp slt i32 %xv, %edge2
  %go = and i1 %more, %fit
  br i1 %go, label %body, label %done
body:
  %idx = sext i32 %iv to i64
  %slot2 = getelementptr [16 x ptr], ptr @g_tabs, i32 0, i64 %idx
  %ed2 = load ptr, ptr %slot2
  %p2 = call ptr @win_editor_path(ptr %ed2)
  %pn2 = icmp eq ptr %p2, null
  %sname = select i1 %pn2, ptr @UNTITLED, ptr %p2
  %slash = call ptr @strrchr(ptr %sname, i32 47)
  %sn = icmp ne ptr %slash, null
  %namep = getelementptr i8, ptr %slash, i64 1
  %name = select i1 %sn, ptr %namep, ptr %sname
  %dirty = call i32 @win_editor_dirty(ptr %ed2)
  %dz = icmp ne i32 %dirty, 0
  %tag = select i1 %dz, ptr @DASH, ptr @EMPTY
  %b2 = alloca [160 x i8]
  %b2p = getelementptr [160 x i8], ptr %b2, i32 0, i32 0
  %i1 = add i32 %iv, 1
  %r3 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %b2p, i64 160,
                  ptr @FMT_TAB, i32 %i1, ptr %name, ptr %tag)
  %len = call i64 @strlen(ptr %b2p)
  %len32 = trunc i64 %len to i32
  %lim = sub i32 %w0, %xv
  %over = icmp sgt i32 %len32, %lim
  br i1 %over, label %done, label %emit
emit:
  %actp2 = getelementptr i32, ptr @g_active, i32 0
  %act2 = load i32, ptr %actp2
  %sel = icmp eq i32 %iv, %act2
  %fg = select i1 %sel, i32 12, i32 8
  %bg = select i1 %sel, i32 5, i32 5
  %at = select i1 %sel, i32 1, i32 0
  call i32 @out_text(i32 %xv, i32 %y0, ptr %b2p, i32 %fg, i32 %bg, i32 %at)
  %xnew = add i32 %xv, %len32
  store i32 %xnew, ptr %x
  %inext = add i32 %iv, 1
  store i32 %inext, ptr %i
  br label %loop
done:
  ret void
}

; -------------------------------------------------------------- draw_console

define void @shell_draw_console(ptr %r) {
entry:
  %hp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 3
  %h = load i32, ptr %hp
  %vis = icmp sgt i32 %h, 0
  br i1 %vis, label %fill, label %done
fill:
  %xp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 0
  %yp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 1
  %wp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 2
  %x0 = load i32, ptr %xp
  %y0 = load i32, ptr %yp
  %w0 = load i32, ptr %wp
  call i32 @out_fill(i32 %x0, i32 %y0, i32 %w0, i32 %h, i32 32,
                     i32 8, i32 1, i32 0)
  %fp = getelementptr i32, ptr @g_focus, i32 0
  %focus = load i32, ptr %fp
  %incons = icmp eq i32 %focus, 1
  %hint = select i1 %incons, ptr @CONS_HINT0, ptr @CONS_HINT1
  %hdr = alloca [200 x i8]
  %hdrp = getelementptr [200 x i8], ptr %hdr, i32 0, i32 0
  %r1 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %hdrp, i64 200,
                                                ptr @FMT_CONS_HDR, ptr %hint)
  %max = sub i32 %w0, 1
  %max2 = select i1 %incons, i32 %max, i32 0
  %max3 = icmp sgt i32 %w0, 1
  %termi = select i1 %max3, i32 %max, i32 0
  %termi64 = sext i32 %termi to i64
  %termp = getelementptr i8, ptr %hdrp, i64 %termi64
  store i8 0, ptr %termp
  %x1 = add i32 %x0, 1
  call i32 @out_text(i32 %x1, i32 %y0, ptr %hdrp, i32 13, i32 1, i32 1)
  %np = getelementptr i32, ptr @g_clog_n, i32 0
  %n = load i32, ptr %np
  %has = icmp sgt i32 %n, 0
  br i1 %has, label %log_init, label %empty_chk
log_init:
  %rows = sub i32 %h, 1
  %first0 = sub i32 %n, %rows
  %neg = icmp slt i32 %first0, 0
  %first = select i1 %neg, i32 0, i32 %first0
  %ip = alloca i32
  store i32 %first, ptr %ip
  %yp2 = add i32 %y0, 1
  %ycur = alloca i32
  store i32 %yp2, ptr %ycur
  br label %log_loop
log_loop:
  %iv = load i32, ptr %ip
  %n2 = load i32, ptr %np
  %c1 = icmp slt i32 %iv, %n2
  %yv = load i32, ptr %ycur
  %bottom = add i32 %y0, %h
  %c2 = icmp slt i32 %yv, %bottom
  %go = and i1 %c1, %c2
  br i1 %go, label %log_body, label %border_init
log_body:
  %idx = sext i32 %iv to i64
  %slot = getelementptr [24 x [200 x i8]], ptr @g_clog, i32 0, i64 %idx, i32 0
  call i32 @out_text(i32 %x1, i32 %yv, ptr %slot, i32 15, i32 1, i32 0)
  %inext = add i32 %iv, 1
  store i32 %inext, ptr %ip
  %ynext = add i32 %yv, 1
  store i32 %ynext, ptr %ycur
  br label %log_loop
empty_chk:
  %more = icmp sgt i32 %h, 1
  br i1 %more, label %empty_msg, label %border_init
empty_msg:
  %yempty = add i32 %y0, 1
  call i32 @out_text(i32 %x1, i32 %yempty, ptr @CONS_EMPTY, i32 8, i32 1, i32 0)
  br label %border_init
border_init:
  %bx = alloca i32
  store i32 %x0, ptr %bx
  br label %border_loop
border_loop:
  %bv = load i32, ptr %bx
  %bmax = sub i32 %x0, 1
  %bend = add i32 %w0, %x0
  %bend2 = sub i32 %bend, 1
  %cont = icmp slt i32 %bv, %bend2
  br i1 %cont, label %border_body, label %prompt_chk
border_body:
  %by = add i32 %y0, %h
  %by2 = sub i32 %by, 1
  call i32 @out_cell(i32 %bv, i32 %by2, i32 45, i32 5, i32 1, i32 0)
  %bn = add i32 %bv, 1
  store i32 %bn, ptr %bx
  br label %border_loop
prompt_chk:
  %focus2 = load i32, ptr %fp
  %show = icmp eq i32 %focus2, 1
  br i1 %show, label %prompt, label %done
prompt:
  %pr = alloca [300 x i8]
  %prp = getelementptr [300 x i8], ptr %pr, i32 0, i32 0
  %cmd = getelementptr [256 x i8], ptr @g_cmd, i32 0, i32 0
  %r2 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %prp, i64 300,
                                                ptr @FMT_PROMPT, ptr %cmd)
  %py = add i32 %y0, %h
  %py2 = sub i32 %py, 1
  call i32 @out_text(i32 %x1, i32 %py2, ptr %prp, i32 16, i32 1, i32 1)
  br label %done
done:
  ret void
}

define void @shell_draw_fileman(ptr %r) {
entry:
  %hp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 3
  %h = load i32, ptr %hp
  %gt = icmp sgt i32 %h, 1
  %rows = sub i32 %h, 1
  %rows2 = select i1 %gt, i32 %rows, i32 0
  store i32 %rows2, ptr @g_fm_rows
  %xp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 0
  %yp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 1
  %wp = getelementptr inbounds %SwiRect, ptr %r, i32 0, i32 2
  %x0 = load i32, ptr %xp
  %y0 = load i32, ptr %yp
  %w0 = load i32, ptr %wp
  %fm = load ptr, ptr @g_fileman
  call void @fileman_draw(ptr %fm, i32 %x0, i32 %y0, i32 %w0, i32 %h)
  ret void
}

@MODE0 = private constant [7 x i8] c"NORMAL\00"
@MODE1 = private constant [7 x i8] c"INSERT\00"
@MODE2 = private constant [7 x i8] c"VISUAL\00"
@MODE3 = private constant [8 x i8] c"COMMAND\00"
@MODE_TABLE = private constant [4 x ptr] [ptr @MODE0, ptr @MODE1,
                                          ptr @MODE2, ptr @MODE3]

; -------------------------------------------------------------- draw()

define void @shell_draw(ptr %canvas, ptr %ed, ptr %console, ptr %st) {
entry:
  %w = call i32 @out_width()
  %h = call i32 @out_height()
  call void @canvas_set_size(ptr %canvas, i32 %w, i32 %h)
  %top = alloca %SwiRect
  %body = alloca %SwiRect
  %bottom = alloca %SwiRect
  call void @canvas_layout(i32 %w, i32 %h, ptr %top, ptr %body, ptr %bottom)
  call i32 @out_clear()
  %thp = getelementptr inbounds %SwiRect, ptr %top, i32 0, i32 3
  %th = load i32, ptr %thp
  %tshow = icmp sgt i32 %th, 0
  br i1 %tshow, label %top_draw, label %panels
top_draw:
  %txp = getelementptr inbounds %SwiRect, ptr %top, i32 0, i32 0
  %typ = getelementptr inbounds %SwiRect, ptr %top, i32 0, i32 1
  %twp = getelementptr inbounds %SwiRect, ptr %top, i32 0, i32 2
  %tx = load i32, ptr %txp
  %ty = load i32, ptr %typ
  %tw = load i32, ptr %twp
  call i32 @out_fill(i32 %tx, i32 %ty, i32 %tw, i32 %th, i32 32, i32 8, i32 5, i32 1)
  %tx1 = add i32 %tx, 1
  call i32 @out_text(i32 %tx1, i32 %ty, ptr @SWI, i32 16, i32 5, i32 1)
  br label %panels
panels:
  %chp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 0
  %fwp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 2
  %ch = load i32, ptr %chp
  %fw = load i32, ptr %fwp
  %tr = alloca %SwiRect
  %br = alloca %SwiRect
  %cr = alloca %SwiRect
  %fr = alloca %SwiRect
  call void @canvas_layout_panels(i32 %w, i32 %h, i32 %ch, i32 %fw,
                                   ptr %tr, ptr %br, ptr %cr, ptr %fr)
  call void @shell_draw_tabs(ptr %tr)
  %frwp = getelementptr inbounds %SwiRect, ptr %fr, i32 0, i32 2
  %frw = load i32, ptr %frwp
  %fmvis = icmp sgt i32 %frw, 0
  br i1 %fmvis, label %fm_draw, label %editor
fm_draw:
  call void @shell_draw_fileman(ptr %fr)
  br label %editor
editor:
  %win = call ptr @canvas_active(ptr %canvas)
  %wn = icmp eq ptr %win, null
  br i1 %wn, label %con, label %win_rect
win_rect:
  %wr = alloca %SwiRect
  %wrrc = call i32 @window_rect(ptr %win, ptr %wr)
  %bxp = getelementptr inbounds %SwiRect, ptr %br, i32 0, i32 0
  %byp = getelementptr inbounds %SwiRect, ptr %br, i32 0, i32 1
  %bwp = getelementptr inbounds %SwiRect, ptr %br, i32 0, i32 2
  %bhp = getelementptr inbounds %SwiRect, ptr %br, i32 0, i32 3
  %bx = load i32, ptr %bxp
  %by = load i32, ptr %byp
  %bw = load i32, ptr %bwp
  %bh = load i32, ptr %bhp
  call void @win_editor_draw(ptr %ed, i32 %bx, i32 %by, i32 %bw, i32 %bh)
  br label %con
con:
  call void @shell_draw_console(ptr %cr)
  %bhp2 = getelementptr inbounds %SwiRect, ptr %bottom, i32 0, i32 3
  %bh2 = load i32, ptr %bhp2
  %bshow = icmp sgt i32 %bh2, 0
  br i1 %bshow, label %bottom_draw, label %present
bottom_draw:
  %ct = call ptr @console_text(ptr %console)
  %prefix = call i32 @console_prefix(ptr %console)
  %nz = icmp ne i32 %prefix, 0
  %buf = alloca [160 x i8]
  %bp = getelementptr [160 x i8], ptr %buf, i32 0, i32 0
  br i1 %nz, label %cmdline, label %statusline
cmdline:
  %pc = trunc i32 %prefix to i8
  %n1 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 160,
                                                ptr @FMT_BOTTOM, i8 %pc, ptr %ct)
  br label %bottom_emit
statusline:
  %m = call i32 @state_mode(ptr %st)
  %ge0 = icmp sge i32 %m, 0
  %lt4 = icmp slt i32 %m, 4
  %valid = and i1 %ge0, %lt4
  br i1 %valid, label %mode_ok, label %mode_bad
mode_bad:
  br label %mode_join
mode_ok:
  %midx = sext i32 %m to i64
  %mp = getelementptr [4 x ptr], ptr @MODE_TABLE, i64 0, i64 %midx
  %namev = load ptr, ptr %mp
  br label %mode_join
mode_join:
  %nameptr = phi ptr [ @MODE0, %mode_bad ], [ %namev, %mode_ok ]
  %is0 = icmp eq i32 %m, 0
  %is1 = icmp eq i32 %m, 1
  %hint0 = select i1 %is0, ptr @HINT0, ptr @EMPTY
  %hint1 = select i1 %is1, ptr @HINT1, ptr @EMPTY
  %hint2 = select i1 %is0, ptr @HINT0, ptr %hint1
  %dirty = call i32 @win_editor_dirty(ptr %ed)
  %dz = icmp ne i32 %dirty, 0
  %tag2 = select i1 %dz, ptr @DIRTY_TAG, ptr @EMPTY
  %wide = icmp sge i32 %w, 70
  %hint3 = select i1 %wide, ptr %hint2, ptr @EMPTY
  %stp = getelementptr inbounds %UiFrame, ptr @g_ui, i32 0, i32 3, i32 0
  %n2 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %bp, i64 160,
                  ptr @FMT_STATUS, ptr %nameptr, ptr %tag2, i32 %w, i32 %h,
                  ptr %hint3, ptr %stp)
  br label %bottom_emit
bottom_emit:
  %bxp3 = getelementptr inbounds %SwiRect, ptr %bottom, i32 0, i32 0
  %byp3 = getelementptr inbounds %SwiRect, ptr %bottom, i32 0, i32 1
  %bx3 = load i32, ptr %bxp3
  %by3 = load i32, ptr %byp3
  call i32 @out_text(i32 %bx3, i32 %by3, ptr %bp, i32 16, i32 1, i32 0)
  br label %present
present:
  %c1 = call i32 @out_cursor(i32 -1, i32 -1)
  %c2 = call i32 @out_present()
  ret void
}

; -------------------------------------------------------------- dispatch

define i32 @shell_dispatch(ptr %st, ptr %console, ptr %ed, ptr %a) {
entry:
  %kp = getelementptr inbounds %SwiAction, ptr %a, i32 0, i32 0
  %kind = load i32, ptr %kp
  switch i32 %kind, label %after [
    i32 1, label %do_mode
    i32 6, label %do_cmdline
    i32 7, label %do_exec
    i32 11, label %do_search
  ]
do_mode:
  %ap = getelementptr inbounds %SwiAction, ptr %a, i32 0, i32 1
  %av = load i64, ptr %ap
  %is3 = icmp eq i64 %av, 3
  br i1 %is3, label %reset_cmd, label %sync_mode
reset_cmd:
  %bp = getelementptr inbounds %SwiAction, ptr %a, i32 0, i32 2
  %bv = load i64, ptr %bp
  %b32 = trunc i64 %bv to i32
  call void @console_reset(ptr %console, i32 %b32)
  br label %sync_mode
sync_mode:
  %m = call i32 @state_mode(ptr %st)
  call void @shell_ui_sync(i32 109, i32 %m, i32 0, i32 0)
  br label %after
do_cmdline:
  %ap2 = getelementptr inbounds %SwiAction, ptr %a, i32 0, i32 1
  %av2 = load i64, ptr %ap2
  call void @console_push(ptr %console, i64 %av2)
  br label %after
do_exec:
  %prefix = call i32 @console_prefix(ptr %console)
  %txt = call ptr @console_text(ptr %console)
  %isslash = icmp eq i32 %prefix, 47
  br i1 %isslash, label %mark_pattern, label %exec_cmd
mark_pattern:
  %tl = call i64 @strlen(ptr %txt)
  call void @win_editor_set_highlight(ptr %ed, ptr %txt, i64 %tl)
  %lpp = getelementptr [256 x i8], ptr @g_last_pattern, i32 0, i32 0
  call ptr @strncpy(ptr %lpp, ptr %txt, i64 255)
  %term = getelementptr i8, ptr %lpp, i64 255
  store i8 0, ptr %term
  br label %exec_cmd
exec_cmd:
  %rc = call i32 @console_execute(ptr %console, ptr %ed)
  %notslash = icmp ne i32 %prefix, 47
  br i1 %notslash, label %copy_eval, label %sync_cmd
copy_eval:
  %o = call ptr @swi_eval_output()
  %on = icmp eq ptr %o, null
  %src = select i1 %on, ptr @EMPTY, ptr %o
  %ol = call i64 @strlen(ptr %src)
  %emp = getelementptr [512 x i8], ptr @g_eval_msg, i32 0, i32 0
  call ptr @strncpy(ptr %emp, ptr %src, i64 511)
  %eterm = getelementptr i8, ptr %emp, i64 511
  store i8 0, ptr %eterm
  %o0 = load i8, ptr %src
  %ononempty = icmp ne i8 %o0, 0
  br i1 %ononempty, label %log_eval, label %sync_cmd
log_eval:
  call void @shell_log_add(ptr %src)
  br label %sync_cmd
sync_cmd:
  call void @shell_ui_sync(i32 99, i32 0, i32 0, i32 0)
  call void @console_reset(ptr %console, i32 0)
  br label %after
do_search:
  %ap3 = getelementptr inbounds %SwiAction, ptr %a, i32 0, i32 1
  %av3 = load i64, ptr %ap3
  %nz = icmp ne i64 %av3, 0
  %fwd = select i1 %nz, i32 1, i32 0
  %sres = call i32 @console_repeat(ptr %console, ptr %ed, i32 %fwd)
  %txt2 = call ptr @console_text(ptr %console)
  %tl2 = call i64 @strlen(ptr %txt2)
  call void @win_editor_set_highlight(ptr %ed, ptr %txt2, i64 %tl2)
  br label %after
after:
  %flags = call i32 @win_editor_step(ptr %ed, ptr %a)
  %f4 = and i32 %flags, 4
  %setmode = icmp ne i32 %f4, 0
  br i1 %setmode, label %set_insert, label %check_edit
set_insert:
  call void @state_set_mode(ptr %st, i32 1)
  br label %check_edit
check_edit:
  %f1 = and i32 %flags, 1
  %edited = icmp ne i32 %f1, 0
  br i1 %edited, label %chk_pattern, label %maybe_fmt
chk_pattern:
  %lpp2 = getelementptr [256 x i8], ptr @g_last_pattern, i32 0, i32 0
  %lc = load i8, ptr %lpp2
  %haspat = icmp ne i8 %lc, 0
  br i1 %haspat, label %rehighlight, label %maybe_fmt
rehighlight:
  %ll = call i64 @strlen(ptr %lpp2)
  call void @win_editor_set_highlight(ptr %ed, ptr %lpp2, i64 %ll)
  br label %maybe_fmt
maybe_fmt:
  %f1b = and i32 %flags, 1
  %ed2 = icmp ne i32 %f1b, 0
  br i1 %ed2, label %do_fmt, label %ret
do_fmt:
  call void @shell_fmt_send(ptr %ed)
  br label %ret
ret:
  %f2 = and i32 %flags, 2
  %quit = icmp ne i32 %f2, 0
  %q32 = zext i1 %quit to i32
  ret i32 %q32
}
