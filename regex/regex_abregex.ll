; core/regex_abregex.ll — Fase 2 completa: def_simple + def_param,
; ref_simple + ref_param. Sin restricción de anidamiento. Un solo frame
; de scope activo, nunca apilado. Ver comentarios inline por función.
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare i32  @memcmp(ptr, ptr, i64)
declare ptr  @memcpy(ptr, ptr, i64)
declare ptr @regex_parse(ptr, i64)
declare ptr @rx_node_new(i64, ptr, ptr, i64, i64)
declare ptr @rx_name_new(ptr, i64)
declare i1  @is_name_char(i8)
declare ptr @ps_create(ptr, i64)
declare void @ps_destroy(ptr)
declare i8  @ps_peek(ptr)
declare void @ps_advance(ptr)
declare i1  @ps_eof(ptr)
declare i1  @ps_has_error(ptr)
declare ptr @parse_alt(ptr)
declare ptr  @rx_compile(ptr)
declare void @rx_program_destroy(ptr)
declare void @rx_ast_destroy(ptr)
%RxNode = type { i64, ptr, ptr, i64, i64 }
%RxName = type { ptr, i64 }
%RxProgram = type { ptr, i64, i64 }
%PState = type { ptr, i64, i64, i64, i64 }
%MacroDef = type { ptr, i64, i64, i64, ptr, i64, ptr }
%Symtab   = type { ptr, i64, i64 }
%ScopeEntry = type { ptr, i64, ptr }
%ParamScope = type { ptr, i64 }

define i1 @is_ws_char(i8 %c) {
entry:
  %is_sp = icmp eq i8 %c, 32
  %is_tab = icmp eq i8 %c, 9
  %is_cr = icmp eq i8 %c, 13
  %is_lf = icmp eq i8 %c, 10
  %r1 = or i1 %is_sp, %is_tab
  %r2 = or i1 %r1, %is_cr
  %r3 = or i1 %r2, %is_lf
  ret i1 %r3
}

define i1 @match_coloncolon(ptr %src, i64 %src_len, i64 %pos) {
entry:
  %pos1 = add i64 %pos, 1
  %in_range = icmp ult i64 %pos1, %src_len
  br i1 %in_range, label %check_chars, label %ret_false
check_chars:
  %c0_ptr = getelementptr i8, ptr %src, i64 %pos
  %c0 = load i8, ptr %c0_ptr
  %c1_ptr = getelementptr i8, ptr %src, i64 %pos1
  %c1 = load i8, ptr %c1_ptr
  %c0_ok = icmp eq i8 %c0, 58
  %c1_ok = icmp eq i8 %c1, 58
  %both_ok = and i1 %c0_ok, %c1_ok
  ret i1 %both_ok
ret_false:
  ret i1 false
}

define ptr @rx_name_clone(ptr %rn) {
entry:
  %p_ptr = getelementptr %RxName, ptr %rn, i32 0, i32 0
  %p = load ptr, ptr %p_ptr
  %l_ptr = getelementptr %RxName, ptr %rn, i32 0, i32 1
  %l = load i64, ptr %l_ptr
  %new_rn = call ptr @rx_name_new(ptr %p, i64 %l)
  ret ptr %new_rn
}

define ptr @rx_ast_clone(ptr %node) {
entry:
  %is_null = icmp eq ptr %node, null
  br i1 %is_null, label %ret_null, label %do_clone
ret_null:
  ret ptr null
do_clone:
  %kind_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 0
  %kind = load i64, ptr %kind_ptr
  %c1_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1 = load ptr, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2 = load ptr, ptr %c2_ptr
  %lit_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 3
  %lit = load i64, ptr %lit_ptr
  %gid_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 4
  %gid = load i64, ptr %gid_ptr
  %is_ref = icmp eq i64 %kind, 8
  br i1 %is_ref, label %clone_macroref, label %check_charclass
clone_macroref:
  %c1_clone_r = call ptr @rx_ast_clone(ptr %c1)
  %new_name = call ptr @rx_name_clone(ptr %c2)
  %ref_clone = call ptr @rx_node_new(i64 8, ptr %c1_clone_r, ptr %new_name, i64 0, i64 -1)
  ret ptr %ref_clone
check_charclass:
  %is_charclass = icmp eq i64 %kind, 9
  br i1 %is_charclass, label %clone_charclass, label %clone_normal
clone_charclass:
  %new_bs = call ptr @malloc(i64 32)
  call ptr @memcpy(ptr %new_bs, ptr %c2, i64 32)
  %cc_node = call ptr @rx_node_new(i64 9, ptr null, ptr %new_bs, i64 0, i64 -1)
  ret ptr %cc_node
clone_normal:
  %c1_clone = call ptr @rx_ast_clone(ptr %c1)
  %c2_clone = call ptr @rx_ast_clone(ptr %c2)
  %new_node = call ptr @rx_node_new(i64 %kind, ptr %c1_clone, ptr %c2_clone, i64 %lit, i64 %gid)
  ret ptr %new_node
}

define ptr @symtab_create() {
entry:
  %st = call ptr @malloc(i64 24)
  %entries_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 0
  store ptr null, ptr %entries_ptr
  %count_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 1
  store i64 0, ptr %count_ptr
  %cap_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 2
  store i64 0, ptr %cap_ptr
  ret ptr %st
}

; --- FIX: symtab_destroy con null checks para evitar crash si el parser falló ---
define void @symtab_destroy(ptr %st) {
entry:
  %is_null = icmp eq ptr %st, null
  br i1 %is_null, label %ret_void, label %do_destroy

ret_void:
  ret void

do_destroy:
  %entries_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %count_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  br label %loop

loop:
  %i = phi i64 [ 0, %do_destroy ], [ %i_next, %skip_pn ]
  %cond = icmp slt i64 %i, %count
  br i1 %cond, label %body, label %done

body:
  %e_ptr = getelementptr %MacroDef, ptr %entries, i64 %i
  %ast_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 4
  %ast = load ptr, ptr %ast_ptr
  %ast_is_null = icmp eq ptr %ast, null
  br i1 %ast_is_null, label %skip_ast, label %free_ast

free_ast:
  call void @rx_ast_destroy(ptr %ast)
  br label %skip_ast

skip_ast:
  %pn_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 6
  %pn = load ptr, ptr %pn_ptr
  %pn_is_null = icmp eq ptr %pn, null
  br i1 %pn_is_null, label %skip_pn, label %free_pn

free_pn:
  call void @free(ptr %pn)
  br label %skip_pn

skip_pn:
  %i_next = add i64 %i, 1
  br label %loop

done:
  %entries_is_null = icmp eq ptr %entries, null
  br i1 %entries_is_null, label %skip_entries, label %free_entries

free_entries:
  call void @free(ptr %entries)
  br label %skip_entries

skip_entries:
  call void @free(ptr %st)
  ret void
}

; --- FIX: rx_ast_destroy corregido para no tratar buffers de charclass como nodos ---
define i64 @symtab_find(ptr %st, ptr %name, i64 %name_len) {
entry:
  %entries_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %count_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %next ]
  %cond = icmp slt i64 %i, %count
  br i1 %cond, label %body, label %not_found
body:
  %e_ptr = getelementptr %MacroDef, ptr %entries, i64 %i
  %en_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 0
  %en = load ptr, ptr %en_ptr
  %el_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 1
  %el = load i64, ptr %el_ptr
  %len_eq = icmp eq i64 %el, %name_len
  br i1 %len_eq, label %cmp_bytes, label %next
cmp_bytes:
  %cmp = call i32 @memcmp(ptr %en, ptr %name, i64 %name_len)
  %is_eq = icmp eq i32 %cmp, 0
  br i1 %is_eq, label %found, label %next
found:
  ret i64 %i
next:
  %i_next = add i64 %i, 1
  br label %loop
not_found:
  ret i64 -1
}

define void @symtab_add(ptr %st, ptr %name, i64 %name_len, ptr %body_ast, i64 %param_count, ptr %param_names) {
entry:
  %count_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  %cap_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 2
  %cap = load i64, ptr %cap_ptr
  %needs_grow = icmp uge i64 %count, %cap
  br i1 %needs_grow, label %grow, label %write
grow:
  %is_zero = icmp eq i64 %cap, 0
  %doubled = mul i64 %cap, 2
  %final_cap = select i1 %is_zero, i64 16, i64 %doubled
  %needed_bytes = mul i64 %final_cap, 56
  %entries_ptr = getelementptr %Symtab, ptr %st, i32 0, i32 0
  %old_entries = load ptr, ptr %entries_ptr
  %new_entries = call ptr @realloc(ptr %old_entries, i64 %needed_bytes)
  store ptr %new_entries, ptr %entries_ptr
  store i64 %final_cap, ptr %cap_ptr
  br label %write
write:
  %entries_ptr2 = getelementptr %Symtab, ptr %st, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr2
  %e_ptr = getelementptr %MacroDef, ptr %entries, i64 %count
  %en_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 0
  store ptr %name, ptr %en_ptr
  %el_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 1
  store i64 %name_len, ptr %el_ptr
  %resolved_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 2
  store i64 0, ptr %resolved_ptr
  %resolving_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 3
  store i64 0, ptr %resolving_ptr
  %ast_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 4
  store ptr %body_ast, ptr %ast_ptr
  %pc_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 5
  store i64 %param_count, ptr %pc_ptr
  %pn_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 6
  store ptr %param_names, ptr %pn_ptr
  %new_count = add i64 %count, 1
  store i64 %new_count, ptr %count_ptr
  ret void
}

define i64 @parse_param_list(ptr %src, i64 %src_len, i64 %start_pos, ptr %out_names, ptr %out_count) {
entry:
  %names0 = call ptr @malloc(i64 64)
  br label %pl_loop
pl_loop:
  %pos = phi i64 [ %start_pos, %entry ], [ %pos_next, %pl_append ]
  %names = phi ptr [ %names0, %entry ], [ %names_m, %pl_append ]
  %cap = phi i64 [ 4, %entry ], [ %cap_m, %pl_append ]
  %count = phi i64 [ 0, %entry ], [ %count_next, %pl_append ]
  %pl_at_end = icmp uge i64 %pos, %src_len
  br i1 %pl_at_end, label %ret_fail, label %pl_name_loop
pl_name_loop:
  %npos = phi i64 [ %pos, %pl_loop ], [ %npos_next, %pl_name_body ]
  %n_at_end = icmp uge i64 %npos, %src_len
  br i1 %n_at_end, label %ret_fail, label %pl_name_check
pl_name_check:
  %nc_ptr = getelementptr i8, ptr %src, i64 %npos
  %nc = load i8, ptr %nc_ptr
  %nc_is_name = call i1 @is_name_char(i8 %nc)
  br i1 %nc_is_name, label %pl_name_body, label %pl_name_done
pl_name_body:
  %npos_next = add i64 %npos, 1
  br label %pl_name_loop
pl_name_done:
  %pname_len = sub i64 %npos, %pos
  %pname_empty = icmp eq i64 %pname_len, 0
  br i1 %pname_empty, label %ret_fail, label %pl_grow_check
pl_grow_check:
  %needs_grow = icmp uge i64 %count, %cap
  br i1 %needs_grow, label %pl_grow, label %pl_merge
pl_grow:
  %cap_g = mul i64 %cap, 2
  %needed_bytes = mul i64 %cap_g, 16
  %names_g = call ptr @realloc(ptr %names, i64 %needed_bytes)
  br label %pl_merge
pl_merge:
  %names_m = phi ptr [ %names, %pl_grow_check ], [ %names_g, %pl_grow ]
  %cap_m = phi i64 [ %cap, %pl_grow_check ], [ %cap_g, %pl_grow ]
  %pname_ptr = getelementptr i8, ptr %src, i64 %pos
  %slot_ptr = getelementptr %RxName, ptr %names_m, i64 %count
  %slot_p_ptr = getelementptr %RxName, ptr %slot_ptr, i32 0, i32 0
  store ptr %pname_ptr, ptr %slot_p_ptr
  %slot_l_ptr = getelementptr %RxName, ptr %slot_ptr, i32 0, i32 1
  store i64 %pname_len, ptr %slot_l_ptr
  %count_next = add i64 %count, 1
  br label %pl_check_sep
pl_check_sep:
  %sep_ptr = getelementptr i8, ptr %src, i64 %npos
  %sep_c = load i8, ptr %sep_ptr
  %sep_is_semi = icmp eq i8 %sep_c, 59
  br i1 %sep_is_semi, label %pl_do_append, label %pl_check_close
pl_do_append:
  %pos_next = add i64 %npos, 1
  br label %pl_append
pl_append:
  br label %pl_loop
pl_check_close:
  %sep_is_gt = icmp eq i8 %sep_c, 62
  br i1 %sep_is_gt, label %pl_finish, label %ret_fail
pl_finish:
  %final_pos = add i64 %npos, 1
  store ptr %names_m, ptr %out_names
  store i64 %count_next, ptr %out_count
  ret i64 %final_pos
ret_fail:
  ret i64 -1
}

define ptr @parse_body_list(ptr %src, i64 %src_len, i64 %start_pos, ptr %out_pos) {
entry:
  %ps = call ptr @ps_create(ptr %src, i64 %src_len)
  %pos_field_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  store i64 %start_pos, ptr %pos_field_ptr
  %first_frag = call ptr @parse_alt(ptr %ps)
  %err0 = call i1 @ps_has_error(ptr %ps)
  br i1 %err0, label %ret_fail, label %bl_loop
bl_loop:
  %acc = phi ptr [ %first_frag, %entry ], [ %acc_next, %bl_append ]
  %c = call i8 @ps_peek(ptr %ps)
  %is_semi = icmp eq i8 %c, 59
  br i1 %is_semi, label %bl_next_frag, label %bl_check_close
bl_next_frag:
  call void @ps_advance(ptr %ps)
  %next_frag = call ptr @parse_alt(ptr %ps)
  %err1 = call i1 @ps_has_error(ptr %ps)
  br i1 %err1, label %ret_fail, label %bl_append
bl_append:
  %acc_next = call ptr @rx_node_new(i64 1, ptr %acc, ptr %next_frag, i64 0, i64 -1)
  br label %bl_loop
bl_check_close:
  %is_gt = icmp eq i8 %c, 62
  br i1 %is_gt, label %bl_finish, label %ret_fail
bl_finish:
  call void @ps_advance(ptr %ps)
  %fpos_ptr = getelementptr %PState, ptr %ps, i32 0, i32 2
  %fpos = load i64, ptr %fpos_ptr
  call void @ps_destroy(ptr %ps)
  store i64 %fpos, ptr %out_pos
  ret ptr %acc
ret_fail:
  call void @ps_destroy(ptr %ps)
  ret ptr null
}

define i32 @abregex_parse_defs(ptr %src, i64 %src_len, ptr %symtab) {
entry:
  br label %skip_ws
skip_ws:
  %pos = phi i64 [ 0, %entry ], [ %pos_next_ws, %skip_ws_body ], [ %ppos_final, %add_entry ], [ %pos_after_semi_p, %add_entry_param ]
  %at_end = icmp uge i64 %pos, %src_len
  br i1 %at_end, label %ret_ok, label %check_ws
check_ws:
  %c_ptr = getelementptr i8, ptr %src, i64 %pos
  %c = load i8, ptr %c_ptr
  %is_ws = call i1 @is_ws_char(i8 %c)
  br i1 %is_ws, label %skip_ws_body, label %check_at
skip_ws_body:
  %pos_next_ws = add i64 %pos, 1
  br label %skip_ws
check_at:
  %is_at2 = icmp eq i8 %c, 64
  br i1 %is_at2, label %parse_def, label %ret_fail
parse_def:
  %name_start = add i64 %pos, 1
  br label %name_loop
name_loop:
  %npos = phi i64 [ %name_start, %parse_def ], [ %npos_next, %name_loop_body ]
  %n_at_end = icmp uge i64 %npos, %src_len
  br i1 %n_at_end, label %ret_fail, label %name_check
name_check:
  %nc_ptr = getelementptr i8, ptr %src, i64 %npos
  %nc = load i8, ptr %nc_ptr
  %nc_is_name = call i1 @is_name_char(i8 %nc)
  br i1 %nc_is_name, label %name_loop_body, label %name_done
name_loop_body:
  %npos_next = add i64 %npos, 1
  br label %name_loop
name_done:
  %name_len = sub i64 %npos, %name_start
  %name_empty = icmp eq i64 %name_len, 0
  br i1 %name_empty, label %ret_fail, label %check_paramchar
check_paramchar:
  %pc_ptr = getelementptr i8, ptr %src, i64 %npos
  %pc = load i8, ptr %pc_ptr
  %pc_is_lt = icmp eq i8 %pc, 60
  br i1 %pc_is_lt, label %parse_def_param, label %expect_coloncolon
expect_coloncolon:
  %cc_ok = call i1 @match_coloncolon(ptr %src, i64 %src_len, i64 %npos)
  br i1 %cc_ok, label %do_pattern, label %ret_fail
do_pattern:
  %pat_start = add i64 %npos, 2
  %ps_s = call ptr @ps_create(ptr %src, i64 %src_len)
  %pos_field_ptr_s = getelementptr %PState, ptr %ps_s, i32 0, i32 2
  store i64 %pat_start, ptr %pos_field_ptr_s
  %body_ast_s = call ptr @parse_alt(ptr %ps_s)
  %err_s = call i1 @ps_has_error(ptr %ps_s)
  br i1 %err_s, label %pattern_parse_fail, label %pattern_check_semi
pattern_parse_fail:
  call void @ps_destroy(ptr %ps_s)
  br label %ret_fail
pattern_check_semi:
  %sc_s = call i8 @ps_peek(ptr %ps_s)
  %is_semi_s = icmp eq i8 %sc_s, 59
  br i1 %is_semi_s, label %pattern_done, label %pattern_parse_fail
pattern_done:
  call void @ps_advance(ptr %ps_s)
  %fpos_ptr_s = getelementptr %PState, ptr %ps_s, i32 0, i32 2
  %ppos_final = load i64, ptr %fpos_ptr_s
  call void @ps_destroy(ptr %ps_s)
  %name_ptr_val2 = getelementptr i8, ptr %src, i64 %name_start
  %existing = call i64 @symtab_find(ptr %symtab, ptr %name_ptr_val2, i64 %name_len)
  %dup = icmp ne i64 %existing, -1
  br i1 %dup, label %ret_fail, label %do_body_parse
do_body_parse:
  %body_null = icmp eq ptr %body_ast_s, null
  br i1 %body_null, label %ret_fail, label %add_entry
add_entry:
  call void @symtab_add(ptr %symtab, ptr %name_ptr_val2, i64 %name_len, ptr %body_ast_s, i64 0, ptr null)
  br label %skip_ws
parse_def_param:
  %pl_start = add i64 %npos, 1
  %pnames_out = alloca ptr
  %pcount_out = alloca i64
  %after_params = call i64 @parse_param_list(ptr %src, i64 %src_len, i64 %pl_start, ptr %pnames_out, ptr %pcount_out)
  %params_ok = icmp sge i64 %after_params, 0
  br i1 %params_ok, label %expect_cc_param, label %ret_fail
expect_cc_param:
  %cc_ok_p = call i1 @match_coloncolon(ptr %src, i64 %src_len, i64 %after_params)
  br i1 %cc_ok_p, label %expect_body_open, label %ret_fail
expect_body_open:
  %bo_pos = add i64 %after_params, 2
  %bo_ptr = getelementptr i8, ptr %src, i64 %bo_pos
  %bo_c = load i8, ptr %bo_ptr
  %bo_is_lt = icmp eq i8 %bo_c, 60
  br i1 %bo_is_lt, label %do_body_list, label %ret_fail
do_body_list:
  %body_start = add i64 %bo_pos, 1
  %bpos_out = alloca i64
  %body_ast_p = call ptr @parse_body_list(ptr %src, i64 %src_len, i64 %body_start, ptr %bpos_out)
  %body_p_null = icmp eq ptr %body_ast_p, null
  br i1 %body_p_null, label %ret_fail, label %expect_semi_param
expect_semi_param:
  %after_body = load i64, ptr %bpos_out
  %at_end_semi = icmp uge i64 %after_body, %src_len
  br i1 %at_end_semi, label %ret_fail, label %check_semi_p
check_semi_p:
  %sc_ptr = getelementptr i8, ptr %src, i64 %after_body
  %sc = load i8, ptr %sc_ptr
  %sc_is_semi = icmp eq i8 %sc, 59
  br i1 %sc_is_semi, label %check_dup_param, label %ret_fail
check_dup_param:
  %name_ptr_val3 = getelementptr i8, ptr %src, i64 %name_start
  %existing_p = call i64 @symtab_find(ptr %symtab, ptr %name_ptr_val3, i64 %name_len)
  %dup_p = icmp ne i64 %existing_p, -1
  br i1 %dup_p, label %ret_fail, label %add_entry_param
add_entry_param:
  %pnames = load ptr, ptr %pnames_out
  %pcount = load i64, ptr %pcount_out
  call void @symtab_add(ptr %symtab, ptr %name_ptr_val3, i64 %name_len, ptr %body_ast_p, i64 %pcount, ptr %pnames)
  %pos_after_semi_p = add i64 %after_body, 1
  br label %skip_ws
ret_ok:
  ret i32 1
ret_fail:
  ret i32 0
}

define ptr @scope_lookup(ptr %scope, ptr %name, i64 %name_len) {
entry:
  %entries_ptr = getelementptr %ParamScope, ptr %scope, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %count_ptr = getelementptr %ParamScope, ptr %scope, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %next ]
  %cond = icmp slt i64 %i, %count
  br i1 %cond, label %body, label %not_found
body:
  %e_ptr = getelementptr %ScopeEntry, ptr %entries, i64 %i
  %en_ptr = getelementptr %ScopeEntry, ptr %e_ptr, i32 0, i32 0
  %en = load ptr, ptr %en_ptr
  %el_ptr = getelementptr %ScopeEntry, ptr %e_ptr, i32 0, i32 1
  %el = load i64, ptr %el_ptr
  %len_eq = icmp eq i64 %el, %name_len
  br i1 %len_eq, label %cmp_bytes, label %next
cmp_bytes:
  %cmp = call i32 @memcmp(ptr %en, ptr %name, i64 %name_len)
  %is_eq = icmp eq i32 %cmp, 0
  br i1 %is_eq, label %found, label %next
found:
  %ast_ptr = getelementptr %ScopeEntry, ptr %e_ptr, i32 0, i32 2
  %ast = load ptr, ptr %ast_ptr
  ret ptr %ast
next:
  %i_next = add i64 %i, 1
  br label %loop
not_found:
  ret ptr null
}

define i64 @arglist_count(ptr %head) {
entry:
  br label %loop
loop:
  %n = phi ptr [ %head, %entry ], [ %next, %body ]
  %count = phi i64 [ 0, %entry ], [ %count_next, %body ]
  %is_null = icmp eq ptr %n, null
  br i1 %is_null, label %done, label %body
body:
  %c2_ptr = getelementptr %RxNode, ptr %n, i32 0, i32 2
  %next = load ptr, ptr %c2_ptr
  %count_next = add i64 %count, 1
  br label %loop
done:
  ret i64 %count
}

define ptr @arglist_nth(ptr %head, i64 %idx) {
entry:
  br label %loop
loop:
  %n = phi ptr [ %head, %entry ], [ %next, %body ]
  %i = phi i64 [ 0, %entry ], [ %i_next, %body ]
  %found = icmp eq i64 %i, %idx
  br i1 %found, label %ret_it, label %body
ret_it:
  %c1_ptr = getelementptr %RxNode, ptr %n, i32 0, i32 1
  %arg = load ptr, ptr %c1_ptr
  ret ptr %arg
body:
  %c2_ptr = getelementptr %RxNode, ptr %n, i32 0, i32 2
  %next = load ptr, ptr %c2_ptr
  %i_next = add i64 %i, 1
  br label %loop
}

define i32 @rx_resolve_in_place(ptr %node, ptr %symtab, ptr %scope) {
entry:
  %is_null = icmp eq ptr %node, null
  br i1 %is_null, label %ret_ok, label %check_kind
check_kind:
  %kind_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 0
  %kind = load i64, ptr %kind_ptr
  %is_ref = icmp eq i64 %kind, 8
  br i1 %is_ref, label %do_splice, label %recurse_children
do_splice:
  %c1_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %old_args = load ptr, ptr %c1_ptr
  %c2_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %rxname = load ptr, ptr %c2_ptr
  %np_ptr = getelementptr %RxName, ptr %rxname, i32 0, i32 0
  %np = load ptr, ptr %np_ptr
  %nl_ptr = getelementptr %RxName, ptr %rxname, i32 0, i32 1
  %nl = load i64, ptr %nl_ptr
  %scope_is_null = icmp eq ptr %scope, null
  br i1 %scope_is_null, label %check_args, label %try_scope
try_scope:
  %scope_hit = call ptr @scope_lookup(ptr %scope, ptr %np, i64 %nl)
  %scope_hit_null = icmp eq ptr %scope_hit, null
  br i1 %scope_hit_null, label %check_args, label %from_scope
from_scope:
  call void @rx_ast_destroy(ptr %old_args)
  store ptr null, ptr %c1_ptr
  store ptr null, ptr %c1_ptr
  %r1 = call ptr @rx_ast_clone(ptr %scope_hit)
  br label %converge
check_args:
  %args_is_null = icmp eq ptr %old_args, null
  br i1 %args_is_null, label %from_simple, label %from_param
from_simple:
  %r2 = call ptr @abregex_resolve(ptr %symtab, ptr %np, i64 %nl)
  br label %converge
from_param:
  %r3 = call ptr @abregex_resolve_param(ptr %symtab, ptr %np, i64 %nl, ptr %old_args, ptr %scope)
  call void @rx_ast_destroy(ptr %old_args)
  store ptr null, ptr %c1_ptr
  store ptr null, ptr %c1_ptr
  store ptr null, ptr %c1_ptr
  br label %converge
converge:
  %resolved = phi ptr [ %r1, %from_scope ], [ %r2, %from_simple ], [ %r3, %from_param ]
  %resolved_null = icmp eq ptr %resolved, null
  br i1 %resolved_null, label %ret_fail, label %splice_write
splice_write:
  call void @free(ptr %rxname)
  %rk_ptr = getelementptr %RxNode, ptr %resolved, i32 0, i32 0
  %rk = load i64, ptr %rk_ptr
  %rc1_ptr = getelementptr %RxNode, ptr %resolved, i32 0, i32 1
  %rc1 = load ptr, ptr %rc1_ptr
  %rc2_ptr = getelementptr %RxNode, ptr %resolved, i32 0, i32 2
  %rc2 = load ptr, ptr %rc2_ptr
  %rlit_ptr = getelementptr %RxNode, ptr %resolved, i32 0, i32 3
  %rlit = load i64, ptr %rlit_ptr
  %rgid_ptr = getelementptr %RxNode, ptr %resolved, i32 0, i32 4
  %rgid = load i64, ptr %rgid_ptr
  store i64 %rk, ptr %kind_ptr
  store ptr %rc1, ptr %c1_ptr
  store ptr %rc2, ptr %c2_ptr
  %lit_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 3
  store i64 %rlit, ptr %lit_ptr
  %gid_ptr = getelementptr %RxNode, ptr %node, i32 0, i32 4
  store i64 %rgid, ptr %gid_ptr
  call void @free(ptr %resolved)
  ret i32 1
recurse_children:
  %c1_ptr2 = getelementptr %RxNode, ptr %node, i32 0, i32 1
  %c1 = load ptr, ptr %c1_ptr2
  %ok1 = call i32 @rx_resolve_in_place(ptr %c1, ptr %symtab, ptr %scope)
  %ok1_b = icmp eq i32 %ok1, 1
  br i1 %ok1_b, label %check_cc, label %ret_fail
check_cc:
  ; FIX: kind 9 = CHARCLASS, su child2 es un bitset de 32 bytes (4 x i64),
  ; NO un %RxNode. Recursar sobre el lo interpretaba como nodo y crasheaba
  ; (bug CHAR_CLASS+loop del handoff). rx_ast_destroy ya hace esta exemption;
  ; el resolver tambien debe hacerla.
  %is_cc = icmp eq i64 %kind, 9
  br i1 %is_cc, label %ret_ok, label %recurse_c2
recurse_c2:
  %c2_ptr2 = getelementptr %RxNode, ptr %node, i32 0, i32 2
  %c2 = load ptr, ptr %c2_ptr2
  %ok2 = call i32 @rx_resolve_in_place(ptr %c2, ptr %symtab, ptr %scope)
  ret i32 %ok2
ret_ok:
  ret i32 1
ret_fail:
  ret i32 0
}

define ptr @abregex_resolve(ptr %symtab, ptr %name, i64 %name_len) {
entry:
  %idx = call i64 @symtab_find(ptr %symtab, ptr %name, i64 %name_len)
  %not_found = icmp eq i64 %idx, -1
  br i1 %not_found, label %ret_null, label %check_arity
check_arity:
  %entries_ptr = getelementptr %Symtab, ptr %symtab, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %e_ptr = getelementptr %MacroDef, ptr %entries, i64 %idx
  %pc_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 5
  %pc = load i64, ptr %pc_ptr
  %needs_args = icmp sgt i64 %pc, 0
  br i1 %needs_args, label %ret_null, label %check_resolved
check_resolved:
  %resolved_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 2
  %resolved = load i64, ptr %resolved_ptr
  %is_resolved = icmp eq i64 %resolved, 1
  br i1 %is_resolved, label %clone_cached, label %check_cycle
clone_cached:
  %ast_ptr0 = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 4
  %ast0 = load ptr, ptr %ast_ptr0
  %clone0 = call ptr @rx_ast_clone(ptr %ast0)
  ret ptr %clone0
check_cycle:
  %resolving_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 3
  %resolving = load i64, ptr %resolving_ptr
  %is_cycle = icmp eq i64 %resolving, 1
  br i1 %is_cycle, label %ret_null, label %do_resolve
do_resolve:
  store i64 1, ptr %resolving_ptr
  %ast_ptr1 = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 4
  %ast1 = load ptr, ptr %ast_ptr1
  %ok = call i32 @rx_resolve_in_place(ptr %ast1, ptr %symtab, ptr null)
  store i64 0, ptr %resolving_ptr
  %ok_b = icmp eq i32 %ok, 1
  br i1 %ok_b, label %mark_resolved, label %ret_null
mark_resolved:
  store i64 1, ptr %resolved_ptr
  %clone1 = call ptr @rx_ast_clone(ptr %ast1)
  ret ptr %clone1
ret_null:
  ret ptr null
}

define ptr @abregex_resolve_param(ptr %symtab, ptr %name, i64 %name_len, ptr %args_head, ptr %caller_scope) {
entry:
  %idx = call i64 @symtab_find(ptr %symtab, ptr %name, i64 %name_len)
  %not_found = icmp eq i64 %idx, -1
  br i1 %not_found, label %ret_null, label %check_arity
check_arity:
  %entries_ptr = getelementptr %Symtab, ptr %symtab, i32 0, i32 0
  %entries = load ptr, ptr %entries_ptr
  %e_ptr = getelementptr %MacroDef, ptr %entries, i64 %idx
  %pc_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 5
  %pc = load i64, ptr %pc_ptr
  %no_params = icmp eq i64 %pc, 0
  br i1 %no_params, label %ret_null, label %check_argcount
check_argcount:
  %arg_count = call i64 @arglist_count(ptr %args_head)
  %count_mismatch = icmp ne i64 %arg_count, %pc
  br i1 %count_mismatch, label %ret_null, label %check_cycle
check_cycle:
  %resolving_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 3
  %resolving = load i64, ptr %resolving_ptr
  %is_cycle = icmp eq i64 %resolving, 1
  br i1 %is_cycle, label %ret_null, label %do_resolve_param
do_resolve_param:
  store i64 1, ptr %resolving_ptr
  %pn_ptr = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 6
  %pnames = load ptr, ptr %pn_ptr
  %se_bytes = mul i64 %pc, 24
  %se_arr = call ptr @malloc(i64 %se_bytes)
  br label %build_scope
build_scope:
  %i = phi i64 [ 0, %do_resolve_param ], [ %i_next, %build_scope_next ]
  %build_done = icmp uge i64 %i, %pc
  br i1 %build_done, label %scope_ready, label %build_scope_body
build_scope_body:
  %arg_i = call ptr @arglist_nth(ptr %args_head, i64 %i)
  %arg_i_clone = call ptr @rx_ast_clone(ptr %arg_i)
  %arg_ok = call i32 @rx_resolve_in_place(ptr %arg_i_clone, ptr %symtab, ptr %caller_scope)
  %arg_ok_b = icmp eq i32 %arg_ok, 1
  br i1 %arg_ok_b, label %build_scope_write, label %fail_unresolving
fail_unresolving:
  call void @rx_ast_destroy(ptr %arg_i_clone)
  store i64 0, ptr %resolving_ptr
  ret ptr null
build_scope_write:
  %pname_slot = getelementptr %RxName, ptr %pnames, i64 %i
  %pn_p_ptr = getelementptr %RxName, ptr %pname_slot, i32 0, i32 0
  %pn_p = load ptr, ptr %pn_p_ptr
  %pn_l_ptr = getelementptr %RxName, ptr %pname_slot, i32 0, i32 1
  %pn_l = load i64, ptr %pn_l_ptr
  %se_slot = getelementptr %ScopeEntry, ptr %se_arr, i64 %i
  %se_n_ptr = getelementptr %ScopeEntry, ptr %se_slot, i32 0, i32 0
  store ptr %pn_p, ptr %se_n_ptr
  %se_l_ptr = getelementptr %ScopeEntry, ptr %se_slot, i32 0, i32 1
  store i64 %pn_l, ptr %se_l_ptr
  %se_a_ptr = getelementptr %ScopeEntry, ptr %se_slot, i32 0, i32 2
  store ptr %arg_i_clone, ptr %se_a_ptr
  br label %build_scope_next
build_scope_next:
  %i_next = add i64 %i, 1
  br label %build_scope
scope_ready:
  %new_scope = call ptr @malloc(i64 16)
  %ns_e_ptr = getelementptr %ParamScope, ptr %new_scope, i32 0, i32 0
  store ptr %se_arr, ptr %ns_e_ptr
  %ns_c_ptr = getelementptr %ParamScope, ptr %new_scope, i32 0, i32 1
  store i64 %pc, ptr %ns_c_ptr
  %ast_ptr1 = getelementptr %MacroDef, ptr %e_ptr, i32 0, i32 4
  %ast1 = load ptr, ptr %ast_ptr1
  %body_clone = call ptr @rx_ast_clone(ptr %ast1)
  %body_ok = call i32 @rx_resolve_in_place(ptr %body_clone, ptr %symtab, ptr %new_scope)
  br label %free_scope_entries

free_scope_entries:
  %fi = phi i64 [ 0, %scope_ready ], [ %fi_next, %free_scope_entries_body ]
  %fdone = icmp uge i64 %fi, %pc
  br i1 %fdone, label %free_scope_done, label %free_scope_entries_body

free_scope_entries_body:
  %fse_slot = getelementptr %ScopeEntry, ptr %se_arr, i64 %fi
  %fse_a_ptr = getelementptr %ScopeEntry, ptr %fse_slot, i32 0, i32 2
  %fse_a = load ptr, ptr %fse_a_ptr
  call void @rx_ast_destroy(ptr %fse_a)
  %fi_next = add i64 %fi, 1
  br label %free_scope_entries

free_scope_done:
  call void @free(ptr %se_arr)
  call void @free(ptr %new_scope)
  store i64 0, ptr %resolving_ptr
  %body_ok_b = icmp eq i32 %body_ok, 1
  br i1 %body_ok_b, label %ret_body, label %fail_after_body
fail_after_body:
  call void @rx_ast_destroy(ptr %body_clone)
  ret ptr null
ret_body:
  ret ptr %body_clone
ret_null:
  ret ptr null
}

define i64 @abregex_compile_named_instruction_count(ptr %src, i64 %src_len, ptr %name, i64 %name_len) {
entry:
  %symtab = call ptr @symtab_create()
  %parse_ok = call i32 @abregex_parse_defs(ptr %src, i64 %src_len, ptr %symtab)
  %parse_ok_b = icmp eq i32 %parse_ok, 1
  br i1 %parse_ok_b, label %do_resolve, label %fail_cleanup
do_resolve:
  %resolved = call ptr @abregex_resolve(ptr %symtab, ptr %name, i64 %name_len)
  %resolved_null = icmp eq ptr %resolved, null
  br i1 %resolved_null, label %fail_cleanup, label %do_compile
do_compile:
  %prog = call ptr @rx_compile(ptr %resolved)
  call void @rx_ast_destroy(ptr %resolved)
  %count_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  call void @rx_program_destroy(ptr %prog)
  call void @symtab_destroy(ptr %symtab)
  ret i64 %count
fail_cleanup:
  call void @symtab_destroy(ptr %symtab)
  ret i64 -1
}
