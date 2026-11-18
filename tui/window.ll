; window.ll — abstraccion de ventana de swi.
;
; Una ventana es un datastruct opaco: river, flags, rectangulo y un puntero
; a los datos de la clase concreta (window_new lo recibe, window_data lo
; devuelve). No sabe nada del contenido: eso lo decide canvas/ los modulos
; de cada clase.
;
; kind:  0 EDITOR  1 FILES  2 REGISTER
; flags: bit 1 OPEN, bit 2 MINIMIZED, bit 4 MAXIMIZED
;
; No usa `switch` -> no necesita -relocation-model=pic.
;
; %Window = { i32 kind, i32 flags, i32 x, i32 y, i32 w, i32 h, ptr data }
; tamano 32 bytes (6*i32 = 24 + ptr alineado a 8).

%Window = type { i32, i32, i32, i32, i32, i32, ptr }
%Rect   = type { i32, i32, i32, i32 }

declare ptr @malloc(i64)
declare void @free(ptr)

define ptr @window_new(i32 %kind, i32 %x, i32 %y, i32 %w, i32 %h, ptr %data) {
entry:
  %p = call ptr @malloc(i64 32)
  %isnull = icmp eq ptr %p, null
  br i1 %isnull, label %fail, label %init
fail:
  ret ptr null
init:
  %kp = getelementptr inbounds %Window, ptr %p, i32 0, i32 0
  store i32 %kind, ptr %kp
  %fp = getelementptr inbounds %Window, ptr %p, i32 0, i32 1
  store i32 1, ptr %fp                      ; OPEN
  %xp = getelementptr inbounds %Window, ptr %p, i32 0, i32 2
  store i32 %x, ptr %xp
  %yp = getelementptr inbounds %Window, ptr %p, i32 0, i32 3
  store i32 %y, ptr %yp
  %wp = getelementptr inbounds %Window, ptr %p, i32 0, i32 4
  store i32 %w, ptr %wp
  %hp = getelementptr inbounds %Window, ptr %p, i32 0, i32 5
  store i32 %h, ptr %hp
  %dp = getelementptr inbounds %Window, ptr %p, i32 0, i32 6
  store ptr %data, ptr %dp
  ret ptr %p
}

define void @window_destroy(ptr %win) {
entry:
  call void @free(ptr %win)
  ret void
}

define i32 @window_kind(ptr %win) {
entry:
  %p = getelementptr inbounds %Window, ptr %win, i32 0, i32 0
  %v = load i32, ptr %p
  ret i32 %v
}

define i32 @window_flags(ptr %win) {
entry:
  %p = getelementptr inbounds %Window, ptr %win, i32 0, i32 1
  %v = load i32, ptr %p
  ret i32 %v
}

define ptr @window_data(ptr %win) {
entry:
  %p = getelementptr inbounds %Window, ptr %win, i32 0, i32 6
  %v = load ptr, ptr %p
  ret ptr %v
}

define void @window_rect(ptr %win, ptr %out) {
entry:
  %xp = getelementptr inbounds %Window, ptr %win, i32 0, i32 2
  %yp = getelementptr inbounds %Window, ptr %win, i32 0, i32 3
  %wp = getelementptr inbounds %Window, ptr %win, i32 0, i32 4
  %hp = getelementptr inbounds %Window, ptr %win, i32 0, i32 5
  %x = load i32, ptr %xp
  %y = load i32, ptr %yp
  %w = load i32, ptr %wp
  %h = load i32, ptr %hp
  store i32 %x, ptr %out
  %o1 = getelementptr inbounds %Rect, ptr %out, i32 0, i32 1
  store i32 %y, ptr %o1
  %o2 = getelementptr inbounds %Rect, ptr %out, i32 0, i32 2
  store i32 %w, ptr %o2
  %o3 = getelementptr inbounds %Rect, ptr %out, i32 0, i32 3
  store i32 %h, ptr %o3
  ret void
}

define void @window_set_rect(ptr %win, i32 %x, i32 %y, i32 %w, i32 %h) {
entry:
  %xp = getelementptr inbounds %Window, ptr %win, i32 0, i32 2
  store i32 %x, ptr %xp
  %yp = getelementptr inbounds %Window, ptr %win, i32 0, i32 3
  store i32 %y, ptr %yp
  %wp = getelementptr inbounds %Window, ptr %win, i32 0, i32 4
  store i32 %w, ptr %wp
  %hp = getelementptr inbounds %Window, ptr %win, i32 0, i32 5
  store i32 %h, ptr %hp
  ret void
}

; Prende (on != 0) o apaga (on == 0) un bit de flags.
define void @window_set_flag(ptr %win, i32 %flag, i32 %on) {
entry:
  %fp = getelementptr inbounds %Window, ptr %win, i32 0, i32 1
  %f = load i32, ptr %fp
  %isset = icmp ne i32 %on, 0
  br i1 %isset, label %set, label %clear
set:
  %newset = or i32 %f, %flag
  store i32 %newset, ptr %fp
  ret void
clear:
  %notflag = xor i32 %flag, -1
  %newclr = and i32 %f, %notflag
  store i32 %newclr, ptr %fp
  ret void
}

define i32 @window_is_open(ptr %win) {
entry:
  %f = call i32 @window_flags(ptr %win)
  %v = and i32 %f, 1
  ret i32 %v
}

define i32 @window_is_minimized(ptr %win) {
entry:
  %f = call i32 @window_flags(ptr %win)
  %v = and i32 %f, 2
  ret i32 %v
}

define i32 @window_is_maximized(ptr %win) {
entry:
  %f = call i32 @window_flags(ptr %win)
  %v = and i32 %f, 4
  ret i32 %v
}
