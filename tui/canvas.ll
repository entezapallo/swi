; canvas.ll — layout + motor de ventanas de swi.
;
; Parte 1 (layout): canvas_layout calcula barra de ventanas, canvas y barra
;   de comandos. Puro, sin estado.
; Parte 2 (motor): Canvas es un struct opaco pasado explicitamente (sin
;   globals: convencion del proyecto). Tiene una lista de ventanas, la
;   activa y el ultimo tamano de pantalla. Permite abrir, cerrar, minimizar
;   y maximizar. Solo la activa se dibuja (por ahora ocupa todo el body).
;
; El tamano de la lista es fijo (MAX_WINDOWS = 16) para mantener el IR chico.
;
; No usa `switch` -> no necesita -relocation-model=pic.
;
; %Rect   = { i32 x, i32 y, i32 w, i32 h }
; %Canvas = { ptr windows, i32 count, i32 cap, ptr active, i32 w, i32 h }

%Rect   = type { i32, i32, i32, i32 }
%Canvas = type { ptr, i32, i32, ptr, i32, i32 }

declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @window_new(i32, i32, i32, i32, i32, ptr)
declare void @window_destroy(ptr)
declare i32 @window_is_open(ptr)
declare i32 @window_is_minimized(ptr)
declare void @window_set_rect(ptr, i32, i32, i32, i32)
declare void @window_set_flag(ptr, i32, i32)
declare void @window_rect(ptr, ptr)

; ======================= parte 1: layout =======================

define internal void @rect_set(ptr %r, i32 %x, i32 %y, i32 %w, i32 %h) {
entry:
  store i32 %x, ptr %r
  %p1 = getelementptr inbounds %Rect, ptr %r, i32 0, i32 1
  store i32 %y, ptr %p1
  %p2 = getelementptr inbounds %Rect, ptr %r, i32 0, i32 2
  store i32 %w, ptr %p2
  %p3 = getelementptr inbounds %Rect, ptr %r, i32 0, i32 3
  store i32 %h, ptr %p3
  ret void
}

define internal void @rect_zero(ptr %r) {
entry:
  call void @rect_set(ptr %r, i32 0, i32 0, i32 0, i32 0)
  ret void
}

define void @canvas_layout(i32 %w, i32 %h,
                            ptr %out_top, ptr %out_body, ptr %out_bottom) {
entry:
  %w_ok = icmp sgt i32 %w, 0
  %h_ok = icmp sgt i32 %h, 0
  %valid = and i1 %w_ok, %h_ok
  br i1 %valid, label %layout, label %zero

zero:
  call void @rect_zero(ptr %out_top)
  call void @rect_zero(ptr %out_body)
  call void @rect_zero(ptr %out_bottom)
  ret void

layout:
  call void @rect_set(ptr %out_top, i32 0, i32 0, i32 %w, i32 1)
  %h_ge3 = icmp sge i32 %h, 3
  br i1 %h_ge3, label %body_yes, label %body_no

body_yes:
  %body_h = sub i32 %h, 2
  call void @rect_set(ptr %out_body, i32 0, i32 1, i32 %w, i32 %body_h)
  br label %bottom_sel

body_no:
  call void @rect_zero(ptr %out_body)
  br label %bottom_sel

bottom_sel:
  %h_ge2 = icmp sge i32 %h, 2
  br i1 %h_ge2, label %bottom_yes, label %bottom_no

bottom_yes:
  %by = sub i32 %h, 1
  call void @rect_set(ptr %out_bottom, i32 0, i32 %by, i32 %w, i32 1)
  ret void

bottom_no:
  call void @rect_zero(ptr %out_bottom)
  ret void
}

; Composicion de paneles: un solo lugar donde se calculan los rects de
; tabs, buffer, consola y file manager. Fexl decide los pesos (con_h/fm_w),
; este modulo decide la geometria. Antes esto estaba a mano en main.c.
define void @canvas_layout_panels(i32 %w, i32 %h, i32 %con_h, i32 %fm_w,
                                  ptr %out_tabs, ptr %out_buf,
                                  ptr %out_con, ptr %out_fm) {
entry:
  %w_ok = icmp sgt i32 %w, 0
  %h_ok = icmp sge i32 %h, 4
  %valid = and i1 %w_ok, %h_ok
  br i1 %valid, label %layout, label %zero

zero:
  call void @rect_zero(ptr %out_tabs)
  call void @rect_zero(ptr %out_buf)
  call void @rect_zero(ptr %out_con)
  call void @rect_zero(ptr %out_fm)
  ret void

layout:
  ; barra de tabs: fila 1 (la fila 0 es la cabecera)
  call void @rect_set(ptr %out_tabs, i32 0, i32 1, i32 %w, i32 1)

  %area_h = sub i32 %h, 3          ; cabecera + tabs + barra de estado

  ; consola: clamp [0, area_h], pegada abajo
  %chneg = icmp slt i32 %con_h, 0
  %ch0 = select i1 %chneg, i32 0, i32 %con_h
  %chgt = icmp sgt i32 %ch0, %area_h
  %ch = select i1 %chgt, i32 %area_h, i32 %ch0
  %chfree = sub i32 %area_h, %ch
  %con_y = add i32 2, %chfree
  call void @rect_set(ptr %out_con, i32 0, i32 %con_y, i32 %w, i32 %ch)

  %buf_h = sub i32 %area_h, %ch

  ; file manager: columna izquierda, con un minimo de 10 columnas para el buffer
  %maxfm = sub i32 %w, 10
  %fmneg = icmp slt i32 %fm_w, 0
  %fm0 = select i1 %fmneg, i32 0, i32 %fm_w
  %fmgt = icmp sgt i32 %fm0, %maxfm
  %fm = select i1 %fmgt, i32 %maxfm, i32 %fm0
  call void @rect_set(ptr %out_fm, i32 0, i32 2, i32 %fm, i32 %buf_h)

  %buf_w = sub i32 %w, %fm
  call void @rect_set(ptr %out_buf, i32 %fm, i32 2, i32 %buf_w, i32 %buf_h)
  ret void
}

define void @canvas_body_rect(ptr %c, ptr %out) {
entry:
  %wp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 4
  %hp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 5
  %w = load i32, ptr %wp
  %h = load i32, ptr %hp
  %top = alloca %Rect
  %bot = alloca %Rect
  call void @canvas_layout(i32 %w, i32 %h, ptr %top, ptr %out, ptr %bot)
  ret void
}

; ======================= parte 2: motor =======================

define ptr @canvas_new() {
entry:
  %c = call ptr @malloc(i64 32)
  %isnull = icmp eq ptr %c, null
  br i1 %isnull, label %fail, label %init
fail:
  ret ptr null
init:
  %arr = call ptr @malloc(i64 128)              ; 16 punteros
  %arrnull = icmp eq ptr %arr, null
  br i1 %arrnull, label %fail_arr, label %setup
fail_arr:
  call void @free(ptr %c)
  ret ptr null
setup:
  %ap = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 0
  store ptr %arr, ptr %ap
  %cp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 2
  store i32 16, ptr %cp
  %np = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 1
  store i32 0, ptr %np
  %actp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 3
  store ptr null, ptr %actp
  %wp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 4
  store i32 0, ptr %wp
  %hp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 5
  store i32 0, ptr %hp
  ret ptr %c
}

define void @canvas_destroy(ptr %c) {
entry:
  %np = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 1
  %n = load i32, ptr %np
  %ap = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 0
  %arr = load ptr, ptr %ap
  br label %loop
loop:
  %i = phi i32 [ 0, %entry ], [ %inext, %body ]
  %cont = icmp slt i32 %i, %n
  br i1 %cont, label %body, label %done
body:
  %slot = getelementptr ptr, ptr %arr, i32 %i
  %win = load ptr, ptr %slot
  call void @window_destroy(ptr %win)
  %inext = add i32 %i, 1
  br label %loop
done:
  call void @free(ptr %arr)
  call void @free(ptr %c)
  ret void
}

define void @canvas_set_size(ptr %c, i32 %w, i32 %h) {
entry:
  %wp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 4
  store i32 %w, ptr %wp
  %hp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 5
  store i32 %h, ptr %hp
  ret void
}

define i32 @canvas_count(ptr %c) {
entry:
  %np = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 1
  %n = load i32, ptr %np
  ret i32 %n
}

define ptr @canvas_active(ptr %c) {
entry:
  %ap = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 3
  %w = load ptr, ptr %ap
  ret ptr %w
}

define void @canvas_set_active(ptr %c, ptr %win) {
entry:
  %ap = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 3
  store ptr %win, ptr %ap
  ret void
}

define ptr @canvas_at(ptr %c, i32 %idx) {
entry:
  %np = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 1
  %n = load i32, ptr %np
  %in = icmp slt i32 %idx, %n
  %ge = icmp sge i32 %idx, 0
  %ok = and i1 %in, %ge
  br i1 %ok, label %get, label %nul
get:
  %arrp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 0
  %arr = load ptr, ptr %arrp
  %slot = getelementptr ptr, ptr %arr, i32 %idx
  %win = load ptr, ptr %slot
  ret ptr %win
nul:
  ret ptr null
}

; Abre una ventana maxima dentro del body y la deja activa.
define ptr @canvas_open(ptr %c, i32 %kind, ptr %data) {
entry:
  %np = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 1
  %n = load i32, ptr %np
  %capp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 2
  %cap = load i32, ptr %capp
  %full = icmp sge i32 %n, %cap
  br i1 %full, label %fail, label %make
fail:
  ret ptr null
make:
  %body = alloca %Rect
  call void @canvas_body_rect(ptr %c, ptr %body)
  %x = load i32, ptr %body
  %yp = getelementptr inbounds %Rect, ptr %body, i32 0, i32 1
  %y = load i32, ptr %yp
  %wp = getelementptr inbounds %Rect, ptr %body, i32 0, i32 2
  %w = load i32, ptr %wp
  %hp = getelementptr inbounds %Rect, ptr %body, i32 0, i32 3
  %h = load i32, ptr %hp
  %win = call ptr @window_new(i32 %kind, i32 %x, i32 %y, i32 %w, i32 %h, ptr %data)
  %isnull = icmp eq ptr %win, null
  br i1 %isnull, label %fail, label %add
add:
  call void @window_set_flag(ptr %win, i32 4, i32 1)   ; MAXIMIZED
  %arrp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 0
  %arr = load ptr, ptr %arrp
  %slot = getelementptr ptr, ptr %arr, i32 %n
  store ptr %win, ptr %slot
  %n1 = add i32 %n, 1
  store i32 %n1, ptr %np
  %actp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 3
  store ptr %win, ptr %actp
  ret ptr %win
}

; Cierra y destruye una ventana. Devuelve 1 si la encontro.
define i32 @canvas_close(ptr %c, ptr %win) {
entry:
  %np = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 1
  %n = load i32, ptr %np
  %arrp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 0
  %arr = load ptr, ptr %arrp
  br label %find
find:
  %i = phi i32 [ 0, %entry ], [ %inext, %no_match ]
  %cont = icmp slt i32 %i, %n
  br i1 %cont, label %check, label %not_found
check:
  %slot = getelementptr ptr, ptr %arr, i32 %i
  %cur = load ptr, ptr %slot
  %match = icmp eq ptr %cur, %win
  br i1 %match, label %found, label %no_match
no_match:
  %inext = add i32 %i, 1
  br label %find
found:
  ; correr los elementos posteriores una posicion a la izquierda
  br label %shift
shift:
  %j = phi i32 [ %i, %found ], [ %jnext, %do_shift ]
  %last = sub i32 %n, 1
  %more = icmp slt i32 %j, %last
  br i1 %more, label %do_shift, label %shift_done
do_shift:
  %dst = getelementptr ptr, ptr %arr, i32 %j
  %j1 = add i32 %j, 1
  %srcline = getelementptr ptr, ptr %arr, i32 %j1
  %v = load ptr, ptr %srcline
  store ptr %v, ptr %dst
  %jnext = add i32 %j, 1
  br label %shift
shift_done:
  %n1 = sub i32 %n, 1
  store i32 %n1, ptr %np
  %actp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 3
  %act = load ptr, ptr %actp
  %was_active = icmp eq ptr %act, %win
  br i1 %was_active, label %clear_active, label %destroy
clear_active:
  store ptr null, ptr %actp
  br label %destroy
destroy:
  call void @window_destroy(ptr %win)
  ret i32 1
not_found:
  ret i32 0
}

define void @canvas_minimize(ptr %c, ptr %win) {
entry:
  call void @window_set_flag(ptr %win, i32 2, i32 1)
  %actp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 3
  %act = load ptr, ptr %actp
  %is = icmp eq ptr %act, %win
  br i1 %is, label %clear, label %done
clear:
  store ptr null, ptr %actp
  br label %done
done:
  ret void
}

define void @canvas_maximize(ptr %c, ptr %win) {
entry:
  call void @window_set_flag(ptr %win, i32 2, i32 0)
  call void @window_set_flag(ptr %win, i32 4, i32 1)
  %body = alloca %Rect
  call void @canvas_body_rect(ptr %c, ptr %body)
  %x = load i32, ptr %body
  %yp = getelementptr inbounds %Rect, ptr %body, i32 0, i32 1
  %y = load i32, ptr %yp
  %wp = getelementptr inbounds %Rect, ptr %body, i32 0, i32 2
  %w = load i32, ptr %wp
  %hp = getelementptr inbounds %Rect, ptr %body, i32 0, i32 3
  %h = load i32, ptr %hp
  call void @window_set_rect(ptr %win, i32 %x, i32 %y, i32 %w, i32 %h)
  %actp = getelementptr inbounds %Canvas, ptr %c, i32 0, i32 3
  store ptr %win, ptr %actp
  ret void
}
