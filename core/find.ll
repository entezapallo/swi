; core/find.ll — búsqueda literal bidireccional con wraparound.
; Sin ninguna relación con regex_posix.ll — substring search plano,
; conviven como capacidades hermanas, no una encima de la otra.
;
; Case-fold ASCII-only (A-Z <-> a-z). UTF-8 multibyte no se pliega
; correctamente — limitación conocida, misma clase de la que ya tiene
; el resto de core/ al tratar todo como bytes crudos.


; ---- helpers internos, no cruzan la frontera ABI, i1 está bien acá ----

define i8 @ascii_fold(i8 %c) {
entry:
  %ge_A = icmp uge i8 %c, 65   ; 'A'
  %le_Z = icmp ule i8 %c, 90   ; 'Z'
  %is_upper = and i1 %ge_A, %le_Z
  %folded = add i8 %c, 32
  %result = select i1 %is_upper, i8 %folded, i8 %c
  ret i8 %result
}

define i1 @find_bytes_match(ptr %hay_start, ptr %needle, i64 %len, i32 %match_case) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %next ]
  %done = icmp uge i64 %i, %len
  br i1 %done, label %ret_true, label %check

check:
  %hptr = getelementptr i8, ptr %hay_start, i64 %i
  %hb = load i8, ptr %hptr
  %nptr = getelementptr i8, ptr %needle, i64 %i
  %nb = load i8, ptr %nptr
  %is_ci = icmp eq i32 %match_case, 0
  br i1 %is_ci, label %fold_both, label %cmp_raw

fold_both:
  %hb_f = call i8 @ascii_fold(i8 %hb)
  %nb_f = call i8 @ascii_fold(i8 %nb)
  %eq_f = icmp eq i8 %hb_f, %nb_f
  br i1 %eq_f, label %next, label %ret_false

cmp_raw:
  %eq_raw = icmp eq i8 %hb, %nb
  br i1 %eq_raw, label %next, label %ret_false

next:
  %i_next = add i64 %i, 1
  br label %loop

ret_true:
  ret i1 true

ret_false:
  ret i1 false
}

; find_next: busca %needle en %tb empezando desde %from_pos.
; %forward: i32, !=0 = hacia adelante, ==0 = hacia atrás.
; %match_case: i32, !=0 = case-sensitive, ==0 = case-insensitive (ASCII fold).
; Wraparound: si no encuentra desde %from_pos hasta el borde, sigue
; buscando desde el otro extremo hasta %from_pos.
; Devuelve la posición del match (i64 >= 0), o -1 (todos los bits en 1)
; si no hay match en todo el buffer.
define i64 @find_next(ptr %hay, i64 %hay_len, ptr %needle, i64 %needle_len, i64 %from_pos, i32 %forward, i32 %match_case) {
entry:

  %needle_empty = icmp eq i64 %needle_len, 0
  br i1 %needle_empty, label %ret_neg1, label %check_fit

check_fit:
  %too_long = icmp ugt i64 %needle_len, %hay_len
  br i1 %too_long, label %ret_neg1, label %check_dir

check_dir:
  %is_forward = icmp ne i32 %forward, 0
  br i1 %is_forward, label %fwd_setup, label %bwd_setup

; ================= forward =================
; posiciones válidas de inicio: [0, hay_len - needle_len]

fwd_setup:
  %fwd_max_start = sub i64 %hay_len, %needle_len
  %from_gt_max = icmp ugt i64 %from_pos, %fwd_max_start
  %fwd_start0 = select i1 %from_gt_max, i64 0, i64 %from_pos
  br label %fwd_phase1

; fase 1: desde fwd_start0 hasta fwd_max_start (inclusive)
fwd_phase1:
  %fp1 = phi i64 [ %fwd_start0, %fwd_setup ], [ %fp1_next, %fwd_phase1_next ]
  %fp1_done = icmp ugt i64 %fp1, %fwd_max_start
  br i1 %fp1_done, label %ret_neg1, label %fwd_phase1_check

fwd_phase1_check:
  %fp1_hay_ptr = getelementptr i8, ptr %hay, i64 %fp1
  %fp1_match = call i1 @find_bytes_match(ptr %fp1_hay_ptr, ptr %needle, i64 %needle_len, i32 %match_case)
  br i1 %fp1_match, label %ret_fp1, label %fwd_phase1_next

fwd_phase1_next:
  %fp1_next = add i64 %fp1, 1
  br label %fwd_phase1

ret_fp1:
  ret i64 %fp1


; ================= backward =================

bwd_setup:
  %bwd_max_start = sub i64 %hay_len, %needle_len
  %bfrom_gt_max = icmp ugt i64 %from_pos, %bwd_max_start
  %bwd_start0 = select i1 %bfrom_gt_max, i64 %bwd_max_start, i64 %from_pos
  br label %bwd_phase1

; fase 1: desde bwd_start0 hacia abajo hasta 0
bwd_phase1:
  %bp1 = phi i64 [ %bwd_start0, %bwd_setup ], [ %bp1_next, %bwd_phase1_next ]
  %bp1_hay_ptr = getelementptr i8, ptr %hay, i64 %bp1
  %bp1_match = call i1 @find_bytes_match(ptr %bp1_hay_ptr, ptr %needle, i64 %needle_len, i32 %match_case)
  br i1 %bp1_match, label %ret_bp1, label %bwd_phase1_check_zero

bwd_phase1_check_zero:
  %bp1_is_zero = icmp eq i64 %bp1, 0
  br i1 %bp1_is_zero, label %ret_neg1, label %bwd_phase1_next

bwd_phase1_next:
  %bp1_next = sub i64 %bp1, 1
  br label %bwd_phase1

ret_bp1:
  ret i64 %bp1


ret_neg1:
  ret i64 -1
}
