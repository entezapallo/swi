; tui/fileman.ll — file manager con scroll (migrado de main.c).
;
; Dueño de: cwd, listado, seleccion y offset de scroll. main.c solo crea el
; objeto, dibuja sus rects y traduce las teclas del loop.
;
; %FileMan = { ptr cwd, ptr names, i64 n, i64 sel, i64 top }
;   cwd   = char* malloc'd (MAX_CWD = 512)
;   names = char[MAX_NAMES][160] contiguo (MAX_NAMES = 160)
;   top   = primera entrada visible

%FileMan = type { ptr, ptr, i64, i64, i64 }

declare ptr   @malloc(i64)
declare void  @free(ptr)
declare ptr   @memcpy(ptr, ptr, i64)
declare i64   @strlen(ptr)
declare i32   @strcmp(ptr, ptr)
declare ptr   @strrchr(ptr, i32)
declare i32   @snprintf(ptr, i64, ptr, ...)
declare ptr   @getcwd(ptr, i64)

declare i32   @fsio_chdir(ptr)
declare i32   @fsio_list_dir(ptr, ptr, ptr)
declare void  @fsio_free_dir_list(ptr, i64)
declare ptr   @fsio_path_join(ptr, ptr)

declare i32   @out_fill(i32, i32, i32, i32, i32, i32, i32, i32)
declare i32   @out_text(i32, i32, ptr, i32, i32, i32)

@FM_DOT  = private constant [2 x i8] c".\00"
@FM_DOTS = private constant [3 x i8] c"..\00"
@FM_HEAD = private constant [11 x i8] c"[files] %s\00"
@FM_SEL  = private constant [10 x i8] c"  %ld/%ld\00"
@FM_SLASH = private constant [2 x i8] c"/\00"

; musl x86-64 struct stat: st_mode está en offset 24; S_IFMT=0170000, S_IFDIR=0040000
@FM_IFMT  = private constant i64 61440
@FM_IFDIR = private constant i64 16384

; ---------------------------------------------------------------- lifecycle

define ptr @fileman_new() {
entry:
  %fm = call ptr @malloc(i64 40)
  %nul = icmp eq ptr %fm, null
  br i1 %nul, label %fail, label %alloc_cwd
alloc_cwd:
  %cwd = call ptr @malloc(i64 512)
  %cnul = icmp eq ptr %cwd, null
  br i1 %cnul, label %fail_fm, label %alloc_names
alloc_names:
  %names = call ptr @malloc(i64 25600)      ; 160 * 160
  %nnul = icmp eq ptr %names, null
  br i1 %nnul, label %fail_cwd, label %init
init:
  call ptr @memcpy(ptr %cwd, ptr @FM_DOT, i64 2)
  %c = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 0
  store ptr %cwd, ptr %c
  %nm = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 1
  store ptr %names, ptr %nm
  %np = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  store i64 0, ptr %np
  %sp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 3
  store i64 0, ptr %sp
  %tp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 4
  store i64 0, ptr %tp
  ret ptr %fm
fail_cwd:
  call void @free(ptr %cwd)
  br label %fail_fm
fail_fm:
  call void @free(ptr %fm)
  br label %fail
fail:
  ret ptr null
}

define void @fileman_destroy(ptr %fm) {
entry:
  %cp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 0
  %cwd = load ptr, ptr %cp
  call void @free(ptr %cwd)
  %np = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 1
  %names = load ptr, ptr %np
  call void @free(ptr %names)
  call void @free(ptr %fm)
  ret void
}

; ---------------------------------------------------------------- getters

define ptr @fileman_cwd(ptr %fm) {
entry:
  %p = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 0
  %v = load ptr, ptr %p
  ret ptr %v
}

define i64 @fileman_count(ptr %fm) {
entry:
  %p = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @fileman_sel(ptr %fm) {
entry:
  %p = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 3
  %v = load i64, ptr %p
  ret i64 %v
}

define i64 @fileman_top(ptr %fm) {
entry:
  %p = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 4
  %v = load i64, ptr %p
  ret i64 %v
}

define ptr @fileman_name(ptr %fm, i64 %i) {
entry:
  %np = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 1
  %names = load ptr, ptr %np
  %off = mul i64 %i, 160
  %p = getelementptr i8, ptr %names, i64 %off
  ret ptr %p
}

define void @fileman_set_sel(ptr %fm, i64 %sel) {
entry:
  %np = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  %n = load i64, ptr %np
  %last = sub i64 %n, 1
  %neg = icmp slt i64 %sel, 0
  %s0 = select i1 %neg, i64 0, i64 %sel
  %over = icmp sgt i64 %s0, %last
  %s1 = select i1 %over, i64 %last, i64 %s0
  %s2 = select i1 %neg, i64 0, i64 %s1
  %sp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 3
  store i64 %s2, ptr %sp
  ret void
}

define void @fileman_set_cwd(ptr %fm, ptr %path) {
entry:
  %cp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 0
  %cwd = load ptr, ptr %cp
  %len = call i64 @strlen(ptr %path)
  %lim = icmp sgt i64 %len, 511
  %use = select i1 %lim, i64 511, i64 %len
  call ptr @memcpy(ptr %cwd, ptr %path, i64 %use)
  %term = getelementptr i8, ptr %cwd, i64 %use
  store i8 0, ptr %term
  %sp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 3
  store i64 0, ptr %sp
  %tp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 4
  store i64 0, ptr %tp
  ret void
}

; ---------------------------------------------------------------- scroll

; Ajusta %top para que la seleccion quede visible en %rows filas.
define void @fileman_scroll(ptr %fm, i64 %rows) {
entry:
  %tp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 4
  %np = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  %sp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 3
  %n = load i64, ptr %np
  %sel = load i64, ptr %sp
  %top0 = load i64, ptr %tp
  %bad = icmp sle i64 %rows, 0
  br i1 %bad, label %zero, label %up
zero:
  store i64 0, ptr %tp
  ret void
up:
  %lt = icmp slt i64 %sel, %top0
  br i1 %lt, label %set_sel_top, label %down
set_sel_top:
  store i64 %sel, ptr %tp
  br label %clamp_lo
down:
  %win_end = add i64 %top0, %rows
  %ge = icmp sge i64 %sel, %win_end
  br i1 %ge, label %advance, label %clamp_lo
advance:
  %newtop = sub i64 %sel, %rows
  %newtop1 = add i64 %newtop, 1
  store i64 %newtop1, ptr %tp
  br label %clamp_lo
clamp_lo:
  %top1 = load i64, ptr %tp
  %neg = icmp slt i64 %top1, 0
  br i1 %neg, label %set_zero, label %clamp_hi
set_zero:
  store i64 0, ptr %tp
  br label %done
clamp_hi:
  %span = sub i64 %n, %rows
  %maxpos = icmp sgt i64 %span, 0
  %maxtop = select i1 %maxpos, i64 %span, i64 0
  %top2 = load i64, ptr %tp
  %over = icmp sgt i64 %top2, %maxtop
  br i1 %over, label %set_max, label %done
set_max:
  store i64 %maxtop, ptr %tp
  br label %done
done:
  ret void
}

; ---------------------------------------------------------------- listado

define void @fileman_load(ptr %fm) {
entry:
  %np0 = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 1
  %names = load ptr, ptr %np0
  call ptr @memcpy(ptr %names, ptr @FM_DOTS, i64 3)
  %out_names = alloca ptr
  %out_count = alloca i64
  store ptr null, ptr %out_names
  store i64 0, ptr %out_count
  %cp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 0
  %cwd = load ptr, ptr %cp
  %rc = call i32 @fsio_list_dir(ptr %cwd, ptr %out_names, ptr %out_count)
  %ok = icmp eq i32 %rc, 1
  br i1 %ok, label %have_list, label %finish
have_list:
  %lst = load ptr, ptr %out_names
  %ln = load i64, ptr %out_count
  %lstnull = icmp eq ptr %lst, null
  br i1 %lstnull, label %finish, label %loop_init
loop_init:
  %count = alloca i64
  store i64 1, ptr %count
  %idx = alloca i64
  store i64 0, ptr %idx
  br label %loop
loop:
  %i = load i64, ptr %idx
  %more = icmp slt i64 %i, %ln
  %cnt = load i64, ptr %count
  %cap = icmp slt i64 %cnt, 160
  %go = and i1 %more, %cap
  br i1 %go, label %body, label %loop_done
body:
  %srcp = getelementptr ptr, ptr %lst, i64 %i
  %src = load ptr, ptr %srcp
  %slen = call i64 @strlen(ptr %src)
  %lim = icmp sgt i64 %slen, 159
  %slen1 = select i1 %lim, i64 159, i64 %slen
  %off = mul i64 %cnt, 160
  %dst = getelementptr i8, ptr %names, i64 %off
  call ptr @memcpy(ptr %dst, ptr %src, i64 %slen1)
  %term = getelementptr i8, ptr %dst, i64 %slen1
  store i8 0, ptr %term
  %cnt1 = add i64 %cnt, 1
  store i64 %cnt1, ptr %count
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %idx
  br label %loop
loop_done:
  call void @fsio_free_dir_list(ptr %lst, i64 %ln)
  %final = load i64, ptr %count
  %nfield1 = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  store i64 %final, ptr %nfield1
  br label %clamp_sel
finish:
  %nfield2 = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  store i64 1, ptr %nfield2
  br label %clamp_sel
clamp_sel:
  call void @fileman_set_sel(ptr %fm, i64 0)
  %tp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 4
  store i64 0, ptr %tp
  ret void
}

; ---------------------------------------------------------------- navegacion

define i32 @fileman_chdir(ptr %fm, ptr %path) {
entry:
  %pnull = icmp eq ptr %path, null
  br i1 %pnull, label %fail, label %do_chdir
do_chdir:
  ; chdir(2) ya falla si la ruta no es un directorio: no hace falta stat.
  %cok = call i32 @fsio_chdir(ptr %path)
  %cokb = icmp eq i32 %cok, 1
  br i1 %cokb, label %getcwd, label %fail
getcwd:
  %abs = alloca [512 x i8]
  %absp = getelementptr [512 x i8], ptr %abs, i32 0, i32 0
  %got = call ptr @getcwd(ptr %absp, i64 512)
  %gnull = icmp eq ptr %got, null
  br i1 %gnull, label %use_path, label %use_abs
use_abs:
  call void @fileman_set_cwd(ptr %fm, ptr %absp)
  br label %reload
use_path:
  call void @fileman_set_cwd(ptr %fm, ptr %path)
  br label %reload
reload:
  call void @fileman_load(ptr %fm)
  ret i32 1
fail:
  ret i32 0
}

; 1 si la entrada %name es un directorio: fsio_list_dir solo tiene exito
; en directorios (y libera su lista internamente).
define i32 @fileman_is_dir(ptr %fm, ptr %name) {
entry:
  %cp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 0
  %cwd = load ptr, ptr %cp
  %full = call ptr @fsio_path_join(ptr %cwd, ptr %name)
  %nul = icmp eq ptr %full, null
  br i1 %nul, label %no, label %do_list
do_list:
  %out_names = alloca ptr
  %out_count = alloca i64
  store ptr null, ptr %out_names
  store i64 0, ptr %out_count
  %rc = call i32 @fsio_list_dir(ptr %full, ptr %out_names, ptr %out_count)
  %lst = load ptr, ptr %out_names
  %lstnul = icmp ne ptr %lst, null
  br i1 %lstnul, label %free_it, label %check
free_it:
  %cnt = load i64, ptr %out_count
  call void @fsio_free_dir_list(ptr %lst, i64 %cnt)
  br label %check
check:
  %ok = icmp eq i32 %rc, 1
  br i1 %ok, label %yes, label %no
yes:
  ret i32 1
no:
  ret i32 0
}

@FM_JOIN = private constant [6 x i8] c"%s/%s\00"
@FM_NAME = private constant [4 x i8] c" %s\00"

define void @fileman_parent(ptr %fm) {
entry:
  %cp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 0
  %cwd = load ptr, ptr %cp
  %first = load i8, ptr %cwd
  %isabs = icmp eq i8 %first, 47
  br i1 %isabs, label %cut_init, label %resolve

resolve:
  %buf = alloca [512 x i8]
  %bp = getelementptr [512 x i8], ptr %buf, i32 0, i32 0
  %got = call ptr @getcwd(ptr %bp, i64 512)
  %gnull = icmp eq ptr %got, null
  br i1 %gnull, label %cut_init, label %is_dot

is_dot:
  %d0 = load i8, ptr %cwd
  %dot = icmp eq i8 %d0, 46
  %clen = call i64 @strlen(ptr %cwd)
  %one = icmp eq i64 %clen, 1
  %dotonly = and i1 %dot, %one
  br i1 %dotonly, label %use_absbuf, label %join

use_absbuf:
  call void @fileman_set_cwd(ptr %fm, ptr %bp)
  br label %cut_init

join:
  %tmp = alloca [1024 x i8]
  %tp = getelementptr [1024 x i8], ptr %tmp, i32 0, i32 0
  %jn = call i32 @snprintf(ptr %tp, i64 1024, ptr @FM_JOIN, ptr %bp, ptr %cwd)
  call void @fileman_set_cwd(ptr %fm, ptr %tp)
  br label %cut_init

cut_init:
  %cwd2 = load ptr, ptr %cp
  %p = call ptr @strrchr(ptr %cwd2, i32 47)
  %pnull = icmp eq ptr %p, null
  %atroot = icmp eq ptr %p, %cwd2
  %root = or i1 %pnull, %atroot
  br i1 %root, label %set_root, label %trim

set_root:
  call void @fileman_set_cwd(ptr %fm, ptr @FM_SLASH)
  call void @fileman_load(ptr %fm)
  ret void

trim:
  store i8 0, ptr %p
  call void @fileman_load(ptr %fm)
  ret void
}

; ---------------------------------------------------------------- dibujo

define void @fileman_draw(ptr %fm, i32 %x, i32 %y, i32 %w, i32 %h) {
entry:
  %hp = icmp sgt i32 %h, 0
  %wp = icmp sgt i32 %w, 0
  %go = and i1 %hp, %wp
  br i1 %go, label %draw, label %done

draw:
  call i32 @out_fill(i32 %x, i32 %y, i32 %w, i32 %h, i32 32,
                     i32 8, i32 1, i32 0)
  %rows = sub i32 %h, 1
  %rows64 = sext i32 %rows to i64
  call void @fileman_scroll(ptr %fm, i64 %rows64)
  %lim = sub i32 %w, 1

  ; ---- cabecera ----
  %buf = alloca [200 x i8]
  %bp = getelementptr [200 x i8], ptr %buf, i32 0, i32 0
  %cp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 0
  %cwd = load ptr, ptr %cp
  %hn = call i32 @snprintf(ptr %bp, i64 200, ptr @FM_HEAD, ptr %cwd)
  %hlen = call i64 @strlen(ptr %bp)
  %hlen32 = trunc i64 %hlen to i32
  %hclip = icmp sgt i32 %hlen32, %lim
  %hlen2 = select i1 %hclip, i32 %lim, i32 %hlen32

  %np = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  %n = load i64, ptr %np
  %needind = icmp sgt i64 %n, %rows64
  br i1 %needind, label %indicator, label %head_out

indicator:
  %sp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 3
  %sel = load i64, ptr %sp
  %sel1 = add i64 %sel, 1
  %tail = getelementptr i8, ptr %bp, i64 %hlen
  %room = sub i64 200, %hlen
  %h2 = call i32 @snprintf(ptr %tail, i64 %room, ptr @FM_SEL,
                           i64 %sel1, i64 %n)
  %hlen3 = call i64 @strlen(ptr %bp)
  %hlen4 = trunc i64 %hlen3 to i32
  %hclip2 = icmp sgt i32 %hlen4, %lim
  %hlen5 = select i1 %hclip2, i32 %lim, i32 %hlen4
  br label %head_out

head_out:
  %hlen6 = phi i32 [ %hlen2, %draw ], [ %hlen5, %indicator ]
  call i32 @out_text(i32 %x, i32 %y, ptr %bp, i32 15, i32 1, i32 1)

  ; ---- entradas, desde %top ----
  %tp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 4
  %top = load i64, ptr %tp
  %endv = add i64 %top, %rows64
  %idx = alloca i64
  store i64 %top, ptr %idx
  br label %loop

loop:
  %iv = load i64, ptr %idx
  %c1 = icmp slt i64 %iv, %n
  %c2 = icmp slt i64 %iv, %endv
  %c = and i1 %c1, %c2
  br i1 %c, label %body, label %done

body:
  %lbuf = alloca [200 x i8]
  %lbp = getelementptr [200 x i8], ptr %lbuf, i32 0, i32 0
  %nm = call ptr @fileman_name(ptr %fm, i64 %iv)
  %ln = call i32 @snprintf(ptr %lbp, i64 200, ptr @FM_NAME, ptr %nm)
  %llen = call i64 @strlen(ptr %lbp)
  %llen32 = trunc i64 %llen to i32
  %lclip = icmp sgt i32 %llen32, %lim
  %llen2 = select i1 %lclip, i32 %lim, i32 %llen32
  %rel = sub i64 %iv, %top
  %rel32 = trunc i64 %rel to i32
  %y2 = add i32 %y, %rel32
  %y3 = add i32 %y2, 1
  %selp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 3
  %selv = load i64, ptr %selp
  %issel = icmp eq i64 %iv, %selv
  br i1 %issel, label %selected, label %normal

selected:
  call i32 @out_text(i32 %x, i32 %y3, ptr %lbp, i32 12, i32 13, i32 1)
  br label %next

normal:
  call i32 @out_text(i32 %x, i32 %y3, ptr %lbp, i32 8, i32 1, i32 0)
  br label %next

next:
  %inext = add i64 %iv, 1
  store i64 %inext, ptr %idx
  br label %loop

done:
  ret void
}

; ---------------------------------------------------------------------------
; fileman_sort: reordena el buffer de nombres segun %order.
; %order es un array de i64 con los indices deseados (order[i] = indice
; original de la entrada que debe quedar en la posicion i). La funcion no
; decide criterios: solo permuta. Los casos (nombre/fecha/tamano) se calculan
; en el llamador. MAX_NAMES = 160, cada entrada ocupa 160 bytes.
; ---------------------------------------------------------------------------
define void @fileman_sort(ptr %fm, ptr %order) {
entry:
  %np = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 1
  %names = load ptr, ptr %np
  %cp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  %n = load i64, ptr %cp
  %tmp = call ptr @malloc(i64 25600)
  %isnull = icmp eq ptr %tmp, null
  br i1 %isnull, label %done, label %copy
copy:
  call ptr @memcpy(ptr %tmp, ptr %names, i64 25600)
  br label %loop_init
loop_init:
  %ip = alloca i64
  store i64 0, ptr %ip
  br label %loop
loop:
  %i = load i64, ptr %ip
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %cleanup
body:
  %ordp = getelementptr i64, ptr %order, i64 %i
  %src = load i64, ptr %ordp
  %lo = icmp sge i64 %src, 0
  %hi = icmp slt i64 %src, %n
  %valid = and i1 %lo, %hi
  br i1 %valid, label %do_copy, label %next
do_copy:
  %soff = mul i64 %src, 160
  %doff = mul i64 %i, 160
  %sp = getelementptr i8, ptr %tmp, i64 %soff
  %dp = getelementptr i8, ptr %names, i64 %doff
  call ptr @memcpy(ptr %dp, ptr %sp, i64 160)
  br label %next
next:
  %inext = add i64 %i, 1
  store i64 %inext, ptr %ip
  br label %loop
cleanup:
  call void @free(ptr %tmp)
  br label %done
done:
  ret void
}

; fileman_reverse_order: ejemplo minimo de orden calculado por el llamador.
; Llena %order con n-1, n-2, ..., 0 (invierte la lista). No es un criterio
; de orden "real": los casos fecha/nombre/tamano se documentan en extend.md.
define void @fileman_reverse_order(ptr %fm, ptr %order) {
entry:
  %cp = getelementptr inbounds %FileMan, ptr %fm, i32 0, i32 2
  %n = load i64, ptr %cp
  %last = sub i64 %n, 1
  %ip = alloca i64
  store i64 0, ptr %ip
  br label %loop
loop:
  %i = load i64, ptr %ip
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %src = sub i64 %last, %i
  %slot = getelementptr i64, ptr %order, i64 %i
  store i64 %src, ptr %slot
  %inext = add i64 %i, 1
  store i64 %inext, ptr %ip
  br label %loop
done:
  ret void
}
