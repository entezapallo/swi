; state.ll — motor de modos de swi: tecla + modo -> ACCION.
;
; Es el unico lugar que decide que significa una tecla. El evento entra como
; %InEvent (espejo de in.h) y sale un %Action por parametro (no por valor,
; para no depender de sret en la frontera C<->IR).
;
; Compilar con -relocation-model=pic (usa `switch`).
;
; Modos:        0 NORMAL   1 INSERT   2 VISUAL   3 COMMAND
; Action.kind:  0 NONE  1 MODE  2 INSERT_CHAR  3 MOTION  4 OPERATOR  5 EDIT
;               6 CMDLINE  7 EXECUTE  8 CANCEL  9 QUIT  10 REJECTED
;               11 SEARCH_NEXT (a=1 forward, a=0 backward)
;               12 HSCROLL (a=-1 izq / +1 der, b=columnas)
;               14 VISUAL_OP (a=op kind 1=d 2=y 3=c, sobre [anchor,cursor))
; Action.a:     MODE->mode | INSERT_CHAR->codepoint | MOTION->motion kind
;               OPERATOR->op | EDIT->edit kind | CMDLINE->codepoint
; Action.b:     MODE->prefix | MOTION->count | OPERATOR->motion | EDIT->count
; Action.c:     OPERATOR->count
; Motion kind:  1 left  2 right  3 up  4 down  5 line_start  6 line_end
;               7 doc_start  8 doc_end  9 word_fwd  10 word_back  11 word_end
; Op kind:      1 d  2 y  3 c
; Edit kind:    1 x  2 dd  3 yy  4 cc  5 p  6 u  7 redo  8 backspace
;
; InEvent (in.h): type KEY=1 CHAR=2 ; key ENTER=1 BACKSPACE=3 ESC=6
;   UP=10 DOWN=11 LEFT=12 RIGHT=13 HOME=14 END=15 F10=29
; mods ALT=1 CTRL=2 ; usar solo caracteres "plain" (sin ALT/CTRL) como
; comandos, salvo Ctrl+R (redo).
;
; Convencion: '0' con count==0 es motion line_start; con count>0 es digito.
; 'gg' necesita un estado extra (pending_g). Un operador pendiente se consume
; con un motion; la misma letra (dd/yy/cc) significa linea completa.

%Action  = type { i32, i64, i64, i64 }
%State   = type { i32, i32, i64, i32, i32 }  ; mode, prefix, count, pending_op, pending_g
%InEvent = type { i32, i32, i32, i32, i32, i32 }

declare ptr @malloc(i64)
declare void @free(ptr)

; --- helpers internos ---

define internal void @act(ptr %out, i32 %kind, i64 %a, i64 %b, i64 %c) {
entry:
  store i32 %kind, ptr %out
  %p1 = getelementptr inbounds %Action, ptr %out, i32 0, i32 1
  store i64 %a, ptr %p1
  %p2 = getelementptr inbounds %Action, ptr %out, i32 0, i32 2
  store i64 %b, ptr %p2
  %p3 = getelementptr inbounds %Action, ptr %out, i32 0, i32 3
  store i64 %c, ptr %p3
  ret void
}

define internal void @clear_pending(ptr %st) {
entry:
  %cp = getelementptr inbounds %State, ptr %st, i32 0, i32 2
  store i64 0, ptr %cp
  %op = getelementptr inbounds %State, ptr %st, i32 0, i32 3
  store i32 0, ptr %op
  %g = getelementptr inbounds %State, ptr %st, i32 0, i32 4
  store i32 0, ptr %g
  ret void
}

define internal void @set_mode(ptr %st, i32 %m) {
entry:
  %mp = getelementptr inbounds %State, ptr %st, i32 0, i32 0
  store i32 %m, ptr %mp
  ret void
}

define internal void @set_prefix(ptr %st, i32 %p) {
entry:
  %pp = getelementptr inbounds %State, ptr %st, i32 0, i32 1
  store i32 %p, ptr %pp
  ret void
}

define internal void @emit_none(ptr %out) {
entry:
  call void @act(ptr %out, i32 0, i64 0, i64 0, i64 0)
  ret void
}

define internal void @emit_motion(ptr %st, ptr %out, i32 %m) {
entry:
  %cp = getelementptr inbounds %State, ptr %st, i32 0, i32 2
  %raw = load i64, ptr %cp
  %pos = icmp sgt i64 %raw, 0
  %cnt = select i1 %pos, i64 %raw, i64 1
  %mv = zext i32 %m to i64
  call void @act(ptr %out, i32 3, i64 %mv, i64 %cnt, i64 0)
  call void @clear_pending(ptr %st)
  ret void
}

define internal void @emit_edit(ptr %st, ptr %out, i32 %k) {
entry:
  %cp = getelementptr inbounds %State, ptr %st, i32 0, i32 2
  %raw = load i64, ptr %cp
  %pos = icmp sgt i64 %raw, 0
  %cnt = select i1 %pos, i64 %raw, i64 1
  %kv = zext i32 %k to i64
  call void @act(ptr %out, i32 5, i64 %kv, i64 %cnt, i64 0)
  call void @clear_pending(ptr %st)
  ret void
}

define internal void @emit_mode(ptr %st, ptr %out, i32 %m, i32 %prefix) {
entry:
  %mv = zext i32 %m to i64
  %pv = zext i32 %prefix to i64
  call void @set_prefix(ptr %st, i32 %prefix)
  call void @set_mode(ptr %st, i32 %m)
  call void @act(ptr %out, i32 1, i64 %mv, i64 %pv, i64 0)
  call void @clear_pending(ptr %st)
  ret void
}

define internal void @emit_cancel(ptr %st, ptr %out) {
entry:
  call void @set_mode(ptr %st, i32 0)
  call void @set_prefix(ptr %st, i32 0)
  call void @clear_pending(ptr %st)
  call void @act(ptr %out, i32 8, i64 0, i64 0, i64 0)
  ret void
}

; Tecla/movimiento -> motion kind, o 0 si no es movimiento.
define internal i32 @motion_of(i32 %ch, i32 %key, i32 %type) {
entry:
  %is_key = icmp eq i32 %type, 1
  br i1 %is_key, label %keys, label %chars

keys:
  %ir = icmp eq i32 %key, 13
  br i1 %ir, label %kr, label %k2
kr:
  ret i32 2
k2:
  %id = icmp eq i32 %key, 11
  br i1 %id, label %kd, label %k3
kd:
  ret i32 4
k3:
  %iu = icmp eq i32 %key, 10
  br i1 %iu, label %ku, label %k4
ku:
  ret i32 3
k4:
  %il = icmp eq i32 %key, 12
  br i1 %il, label %kl, label %k5
kl:
  ret i32 1
k5:
  %ih = icmp eq i32 %key, 14
  br i1 %ih, label %kh, label %k6
kh:
  ret i32 5
k6:
  %ie = icmp eq i32 %key, 15
  br i1 %ie, label %ke, label %k0
ke:
  ret i32 6
k0:
  ret i32 0

chars:
  %ihc = icmp eq i32 %ch, 104
  br i1 %ihc, label %mh_left, label %c2
mh_left:
  ret i32 1
c2:
  %ijc = icmp eq i32 %ch, 106
  br i1 %ijc, label %cj, label %c3
cj:
  ret i32 4
c3:
  %ikc = icmp eq i32 %ch, 107
  br i1 %ikc, label %ck, label %c4
ck:
  ret i32 3
c4:
  %ilc = icmp eq i32 %ch, 108
  br i1 %ilc, label %cl, label %c5
cl:
  ret i32 2
c5:
  %i0c = icmp eq i32 %ch, 48
  br i1 %i0c, label %c0, label %c6
c0:
  ret i32 5
c6:
  %idc = icmp eq i32 %ch, 36
  br i1 %idc, label %cd, label %cz0
cd:
  ret i32 6
cz0:
  %iwc = icmp eq i32 %ch, 119
  br i1 %iwc, label %cw, label %cb_chk
cw:
  ret i32 9
cb_chk:
  %ibc = icmp eq i32 %ch, 98
  br i1 %ibc, label %cb, label %ce_chk
cb:
  ret i32 10
ce_chk:
  %iec = icmp eq i32 %ch, 101
  br i1 %iec, label %ce, label %cz
ce:
  ret i32 11
cz:
  ret i32 0
}

; --- API publica ---

define ptr @state_new() {
entry:
  %p = call ptr @malloc(i64 24)
  %isnull = icmp eq ptr %p, null
  br i1 %isnull, label %fail, label %init
fail:
  ret ptr null
init:
  %m = getelementptr inbounds %State, ptr %p, i32 0, i32 0
  %pr = getelementptr inbounds %State, ptr %p, i32 0, i32 1
  %c = getelementptr inbounds %State, ptr %p, i32 0, i32 2
  %o = getelementptr inbounds %State, ptr %p, i32 0, i32 3
  %g = getelementptr inbounds %State, ptr %p, i32 0, i32 4
  store i32 0, ptr %m
  store i32 0, ptr %pr
  store i64 0, ptr %c
  store i32 0, ptr %o
  store i32 0, ptr %g
  ret ptr %p
}

define void @state_free(ptr %st) {
entry:
  call void @free(ptr %st)
  ret void
}

define i32 @state_mode(ptr %st) {
entry:
  %p = getelementptr inbounds %State, ptr %st, i32 0, i32 0
  %v = load i32, ptr %p
  ret i32 %v
}

define i32 @state_prefix(ptr %st) {
entry:
  %p = getelementptr inbounds %State, ptr %st, i32 0, i32 1
  %v = load i32, ptr %p
  ret i32 %v
}

define i64 @state_count(ptr %st) {
entry:
  %p = getelementptr inbounds %State, ptr %st, i32 0, i32 2
  %v = load i64, ptr %p
  ret i64 %v
}

define i32 @state_pending_op(ptr %st) {
entry:
  %p = getelementptr inbounds %State, ptr %st, i32 0, i32 3
  %v = load i32, ptr %p
  ret i32 %v
}

; Lo usa el TUI cuando una edicion (c) debe dejar INSERT activo.
define void @state_set_mode(ptr %st, i32 %m) {
entry:
  call void @set_mode(ptr %st, i32 %m)
  ret void
}

; Evento -> accion.
define void @state_step(ptr %st, ptr %ev, i32 %editable, ptr %out) {
entry:
  %mp = getelementptr inbounds %State, ptr %st, i32 0, i32 0
  %mode = load i32, ptr %mp
  %op_ptr = getelementptr inbounds %State, ptr %st, i32 0, i32 3
  %pending = load i32, ptr %op_ptr
  %g_ptr = getelementptr inbounds %State, ptr %st, i32 0, i32 4
  %pend_g = load i32, ptr %g_ptr
  %cp = getelementptr inbounds %State, ptr %st, i32 0, i32 2
  %cnt = load i64, ptr %cp
  %prefix_ptr = getelementptr inbounds %State, ptr %st, i32 0, i32 1
  %prefix = load i32, ptr %prefix_ptr

  %tp = getelementptr inbounds %InEvent, ptr %ev, i32 0, i32 0
  %kp = getelementptr inbounds %InEvent, ptr %ev, i32 0, i32 1
  %mdp = getelementptr inbounds %InEvent, ptr %ev, i32 0, i32 2
  %chp = getelementptr inbounds %InEvent, ptr %ev, i32 0, i32 3
  %type = load i32, ptr %tp
  %key = load i32, ptr %kp
  %mods = load i32, ptr %mdp
  %ch = load i32, ptr %chp

  ; caracter "plain": sin CTRL ni ALT
  %is_char = icmp eq i32 %type, 2
  %mm = and i32 %mods, 3
  %is_plain = icmp eq i32 %mm, 0
  %plain_ok = and i1 %is_char, %is_plain
  %pch = select i1 %plain_ok, i32 %ch, i32 -1

  ; teclas especiales
  %is_key = icmp eq i32 %type, 1
  %k_esc0 = icmp eq i32 %key, 6
  %is_esc = and i1 %is_key, %k_esc0
  %k_ent0 = icmp eq i32 %key, 1
  %is_enter = and i1 %is_key, %k_ent0
  %k_bs0 = icmp eq i32 %key, 3
  %is_bs = and i1 %is_key, %k_bs0
  %k_f10_0 = icmp eq i32 %key, 29
  %is_f10 = and i1 %is_key, %k_f10_0

  ; Ctrl+R (redo): char 'r' con bit CTRL
  %mods_ctrl = and i32 %mods, 2
  %is_ctrl_bit = icmp ne i32 %mods_ctrl, 0
  %is_r = icmp eq i32 %ch, 114
  %ctrl_r_raw = and i1 %is_char, %is_ctrl_bit
  %is_ctrl_r = and i1 %ctrl_r_raw, %is_r
  %ctrl_q_raw = and i1 %is_char, %is_ctrl_bit
  %is_q = icmp eq i32 %ch, 113
  %is_ctrl_q = and i1 %ctrl_q_raw, %is_q

  ; digito 1..9
  %dge = icmp sge i32 %pch, 49
  %dle = icmp sle i32 %pch, 57
  %is_digit = and i1 %dge, %dle
  %is_zero = icmp eq i32 %pch, 48
  %is_g = icmp eq i32 %pch, 103
  %is_G = icmp eq i32 %pch, 71

  %motion = call i32 @motion_of(i32 %pch, i32 %key, i32 %type)
  %has_motion = icmp ne i32 %motion, 0
  %has_pending = icmp ne i32 %pending, 0
  %has_pend_g = icmp ne i32 %pend_g, 0

  switch i32 %mode, label %none [
    i32 0, label %m_normal
    i32 1, label %m_insert
    i32 2, label %m_visual
    i32 3, label %m_command
  ]

; ================= NORMAL =================
m_normal:
  br i1 %has_pend_g, label %pend_g_check, label %pend_op_check

pend_g_check:
  %gg = icmp eq i32 %pch, 103
  br i1 %gg, label %do_motion_ds, label %gG
gG:
  %gG2 = icmp eq i32 %pch, 71
  br i1 %gG2, label %do_motion_de, label %none_clear

pend_op_check:
  br i1 %has_pending, label %pend_op_body, label %plain_normal

pend_op_body:
  ; misma letra que el operador -> operador de linea (dd/yy/cc)
  %op_d = icmp eq i32 %pending, 1
  %op_y = icmp eq i32 %pending, 2
  %op_c = icmp eq i32 %pending, 3
  %ch_d = select i1 %op_d, i32 100, i32 0
  %ch_y = select i1 %op_y, i32 121, i32 0
  %ch_c = select i1 %op_c, i32 99, i32 0
  %opch_or1 = or i32 %ch_d, %ch_y
  %opch = or i32 %opch_or1, %ch_c
  %is_same = icmp eq i32 %pch, %opch
  %opch_ok = icmp ne i32 %opch, 0
  %same_ok = and i1 %is_same, %opch_ok
  br i1 %same_ok, label %do_line_op, label %pend_motion_chk

pend_motion_chk:
  br i1 %has_motion, label %do_operator, label %pend_esc_chk
pend_esc_chk:
  br i1 %is_esc, label %cancel, label %none

do_line_op:
  ; d->dd(2), y->yy(3), c->cc(4)
  %cnt_pos_lo = icmp sgt i64 %cnt, 0
  %cnt_lo = select i1 %cnt_pos_lo, i64 %cnt, i64 1
  %e_d = select i1 %op_d, i64 2, i64 0
  %e_y = select i1 %op_y, i64 3, i64 0
  %e_c = select i1 %op_c, i64 4, i64 0
  %e_or1 = or i64 %e_d, %e_y
  %ekind = or i64 %e_or1, %e_c
  call void @act(ptr %out, i32 5, i64 %ekind, i64 %cnt_lo, i64 0)
  call void @clear_pending(ptr %st)
  ret void

do_operator:
  %cnt_pos_op = icmp sgt i64 %cnt, 0
  %cnt_op = select i1 %cnt_pos_op, i64 %cnt, i64 1
  %opv = zext i32 %pending to i64
  %motv = zext i32 %motion to i64
  call void @act(ptr %out, i32 4, i64 %opv, i64 %motv, i64 %cnt_op)
  call void @clear_pending(ptr %st)
  ret void

plain_normal:
  br i1 %is_digit, label %accum, label %zero_chk
zero_chk:
  br i1 %is_zero, label %zero_dispatch, label %g_chk
zero_dispatch:
  %cnt_pos = icmp sgt i64 %cnt, 0
  br i1 %cnt_pos, label %accum, label %do_motion_ls
g_chk:
  br i1 %is_g, label %set_g, label %G_chk
G_chk:
  br i1 %is_G, label %do_motion_de, label %nmotion_chk
nmotion_chk:
  br i1 %has_motion, label %do_motion_generic, label %x_chk
x_chk:
  %is_x = icmp eq i32 %pch, 120
  br i1 %is_x, label %do_edit_x, label %d_chk
d_chk:
  %ch_d2 = icmp eq i32 %pch, 100
  br i1 %ch_d2, label %set_op_d, label %y_chk
y_chk:
  %ch_y2 = icmp eq i32 %pch, 121
  br i1 %ch_y2, label %set_op_y, label %c_chk
c_chk:
  %ch_c2 = icmp eq i32 %pch, 99
  br i1 %ch_c2, label %set_op_c, label %p_chk
p_chk:
  %is_p = icmp eq i32 %pch, 112
  br i1 %is_p, label %do_edit_p, label %u_chk
u_chk:
  %is_u = icmp eq i32 %pch, 117
  br i1 %is_u, label %do_edit_u, label %redo_chk
redo_chk:
  br i1 %is_ctrl_r, label %do_edit_redo, label %lt_chk
lt_chk:
  %is_lt = icmp eq i32 %pch, 60
  br i1 %is_lt, label %do_hs_left, label %gt_chk
gt_chk:
  %is_gt = icmp eq i32 %pch, 62
  br i1 %is_gt, label %do_hs_right, label %n_chk
do_hs_left:
  %hpos_l = icmp sgt i64 %cnt, 0
  %hcnt_l = select i1 %hpos_l, i64 %cnt, i64 8
  call void @act(ptr %out, i32 12, i64 -1, i64 %hcnt_l, i64 0)
  ret void
do_hs_right:
  %hpos_r = icmp sgt i64 %cnt, 0
  %hcnt_r = select i1 %hpos_r, i64 %cnt, i64 8
  call void @act(ptr %out, i32 12, i64 1, i64 %hcnt_r, i64 0)
  ret void
n_chk:
  %is_n = icmp eq i32 %pch, 110
  br i1 %is_n, label %do_search_n, label %N_chk
N_chk:
  %is_N = icmp eq i32 %pch, 78
  br i1 %is_N, label %do_search_N, label %i_chk
do_search_n:
  call void @act(ptr %out, i32 11, i64 1, i64 0, i64 0)
  ret void
do_search_N:
  call void @act(ptr %out, i32 11, i64 0, i64 0, i64 0)
  ret void
i_chk:
  %is_i = icmp eq i32 %pch, 105
  br i1 %is_i, label %try_insert, label %v_chk
v_chk:
  %is_v = icmp eq i32 %pch, 118
  br i1 %is_v, label %do_visual, label %colon_chk
colon_chk:
  %is_colon = icmp eq i32 %pch, 58
  br i1 %is_colon, label %do_command_colon, label %slash_chk
slash_chk:
  %is_slash = icmp eq i32 %pch, 47
  br i1 %is_slash, label %do_command_slash, label %quit_chk
quit_chk:
  %is_quit = or i1 %is_ctrl_q, %is_f10
  br i1 %is_quit, label %do_quit, label %esc_chk
esc_chk:
  br i1 %is_esc, label %cancel, label %none

accum:
  %digit_val = sub i32 %pch, 48
  %dv = sext i32 %digit_val to i64
  %cnt10 = mul i64 %cnt, 10
  %newcnt = add i64 %cnt10, %dv
  store i64 %newcnt, ptr %cp
  br label %none

set_g:
  store i32 1, ptr %g_ptr
  br label %none
set_op_d:
  store i32 1, ptr %op_ptr
  br label %none
set_op_y:
  store i32 2, ptr %op_ptr
  br label %none
set_op_c:
  store i32 3, ptr %op_ptr
  br label %none

do_motion_ls:
  call void @emit_motion(ptr %st, ptr %out, i32 5)
  ret void
do_motion_de:
  call void @emit_motion(ptr %st, ptr %out, i32 8)
  ret void
do_motion_ds:
  call void @emit_motion(ptr %st, ptr %out, i32 7)
  ret void
do_motion_generic:
  call void @emit_motion(ptr %st, ptr %out, i32 %motion)
  ret void
do_edit_x:
  call void @emit_edit(ptr %st, ptr %out, i32 1)
  ret void
do_edit_p:
  call void @emit_edit(ptr %st, ptr %out, i32 5)
  ret void
do_edit_u:
  call void @emit_edit(ptr %st, ptr %out, i32 6)
  ret void
do_edit_redo:
  call void @emit_edit(ptr %st, ptr %out, i32 7)
  ret void
try_insert:
  %ed_ok = icmp ne i32 %editable, 0
  br i1 %ed_ok, label %do_insert_mode, label %rejected
do_insert_mode:
  call void @emit_mode(ptr %st, ptr %out, i32 1, i32 0)
  ret void
do_visual:
  call void @emit_mode(ptr %st, ptr %out, i32 2, i32 0)
  ret void
do_command_colon:
  call void @emit_mode(ptr %st, ptr %out, i32 3, i32 58)
  ret void
do_command_slash:
  call void @emit_mode(ptr %st, ptr %out, i32 3, i32 47)
  ret void

; operador sobre la seleccion VISUAL: vuelve a NORMAL y emite VISUAL_OP
; con a = op kind (1=d, 2=y, 3=c).
do_visual_op:
  call void @set_mode(ptr %st, i32 0)
  call void @clear_pending(ptr %st)
  %op = select i1 %vd, i64 1, i64 0
  %op2 = select i1 %vy, i64 2, i64 %op
  %op3 = select i1 %vc2, i64 3, i64 %op2
  call void @act(ptr %out, i32 14, i64 %op3, i64 0, i64 0)
  ret void
do_quit:
  call void @act(ptr %out, i32 9, i64 0, i64 0, i64 0)
  ret void

; ================= INSERT =================
m_insert:
  br i1 %is_esc, label %to_normal, label %ins_check
ins_check:
  %k_tab0 = icmp eq i32 %key, 2
  %is_tab = and i1 %is_key, %k_tab0
  br i1 %is_tab, label %ins_tab, label %ins_bs
ins_bs:
  br i1 %is_bs, label %ins_backspace, label %ins_motion
ins_motion:
  ; en INSERT solo las teclas especiales (flechas/Home/End) son motion.
  ; Si se usa %has_motion solo, las letras h/j/k/l se comen como comandos
  ; vi en vez de insertarse como texto.
  %ins_motion_ok = and i1 %is_key, %has_motion
  br i1 %ins_motion_ok, label %do_motion_generic, label %ins_char
ins_char:
  %any_char = icmp eq i32 %type, 2
  br i1 %any_char, label %do_insert_char, label %ins_enter
ins_enter:
  br i1 %is_enter, label %do_insert_newline, label %none
ins_tab:
  call void @act(ptr %out, i32 2, i64 9, i64 0, i64 0)
  ret void
ins_backspace:
  call void @act(ptr %out, i32 5, i64 8, i64 1, i64 0)
  ret void
do_insert_char:
  %ichv = zext i32 %ch to i64
  call void @act(ptr %out, i32 2, i64 %ichv, i64 0, i64 0)
  ret void
do_insert_newline:
  call void @act(ptr %out, i32 2, i64 10, i64 0, i64 0)
  ret void

; ================= VISUAL =================
m_visual:
  br i1 %is_esc, label %to_normal_visual, label %vis_op_check
vis_op_check:
  ; en VISUAL, d/y/c operan sobre el rango [anchor,cursor)
  %vd = icmp eq i32 %pch, 100
  %vy = icmp eq i32 %pch, 121
  %vc2 = icmp eq i32 %pch, 99
  %is_vop = or i1 %vd, %vy
  %is_vop2 = or i1 %is_vop, %vc2
  br i1 %is_vop2, label %do_visual_op, label %vis_motion
vis_motion:
  br i1 %has_motion, label %do_motion_generic, label %vis_colon
vis_colon:
  %is_colon_v = icmp eq i32 %pch, 58
  br i1 %is_colon_v, label %do_command_colon, label %none

; ================= COMMAND =================
m_command:
  br i1 %is_esc, label %cancel, label %cmd_enter
cmd_enter:
  br i1 %is_enter, label %do_execute, label %cmd_bs
cmd_bs:
  br i1 %is_bs, label %do_cmdline_bs, label %cmd_char
cmd_char:
  %any_char_c = icmp eq i32 %type, 2
  br i1 %any_char_c, label %do_cmdline_char, label %none
do_cmdline_char:
  %cchv = zext i32 %ch to i64
  %cprv = zext i32 %prefix to i64
  call void @act(ptr %out, i32 6, i64 %cchv, i64 %cprv, i64 0)
  ret void
do_cmdline_bs:
  %bprv = zext i32 %prefix to i64
  call void @act(ptr %out, i32 6, i64 8, i64 %bprv, i64 0)
  ret void
do_execute:
  call void @set_mode(ptr %st, i32 0)
  call void @clear_pending(ptr %st)
  call void @act(ptr %out, i32 7, i64 0, i64 0, i64 0)
  ret void

; --- cola comun ---
to_normal:
  call void @emit_mode(ptr %st, ptr %out, i32 0, i32 0)
  ret void
to_normal_visual:
  call void @emit_mode(ptr %st, ptr %out, i32 0, i32 0)
  ret void
cancel:
  call void @emit_cancel(ptr %st, ptr %out)
  ret void
none_clear:
  call void @clear_pending(ptr %st)
  br label %none
none:
  call void @emit_none(ptr %out)
  ret void
rejected:
  call void @act(ptr %out, i32 10, i64 0, i64 0, i64 0)
  ret void
}
