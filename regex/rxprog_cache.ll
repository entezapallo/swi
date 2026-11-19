; core/rxprog_cache.ll — hash FNV-1a y serialización de RxProgram a .rxc
;
; %RxProgram/%RxInst DUPLICADOS de core/regex_compiler.ll (líneas 51-52).
; DEBEN COINCIDIR — si el struct real cambia allá, actualizar acá también.

; formato .rxc:
;   [magic:i64][self_hash:i64][dep_hash:i64][count:i64][num_groups:i64]
;   + count * 24 bytes de RxInst
;   + N * 32 bytes de bitsets CHAR_CLASS
; header = 40 bytes
;
; CHAR_CLASS (opcode 5): en memoria arg1 es un ptr a un bitset de 32 bytes.
; Un puntero NO se puede persistir. En disco arg1=0 y arg2=índice del bitset
; en el bloque final; serialize copia ahí los 32 bytes y deserialize los
; reconstruye con malloc fresco. Así rx_program_destroy puede liberarlos sin
; doble-free (antes copiaba el puntero crudo -> doble free / use-after-free).

declare ptr @malloc(i64)
declare void @free(ptr)
declare i32  @fsio_read_file(ptr, ptr, ptr)
declare i32  @fsio_write_file(ptr, ptr, i64)
declare void @fsio_free_buffer(ptr)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly,
                                    ptr noalias nocapture readonly, i64, i1)

; FNV-1a de 64 bits sobre %len bytes en %data.
define i64 @fnv1a_hash(ptr %data, i64 %len) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i_next, %body ]
  %h = phi i64 [ -3750763034362895579, %entry ], [ %h_next, %body ]
  %done = icmp uge i64 %i, %len
  br i1 %done, label %ret, label %body
body:
  %p = getelementptr i8, ptr %data, i64 %i
  %b = load i8, ptr %p
  %b64 = zext i8 %b to i64
  %hx = xor i64 %h, %b64
  %h_next = mul i64 %hx, 1099511628211
  %i_next = add i64 %i, 1
  br label %loop
ret:
  ret i64 %h
}

; escribe %prog a %path con header de hashes. Devuelve 1 ok, 0 fail.
define i32 @rxprog_serialize(ptr %prog, i64 %self_hash, i64 %dep_hash, ptr %path) {
entry:
  %instrs_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 0
  %instrs = load ptr, ptr %instrs_ptr
  %count_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 1
  %count = load i64, ptr %count_ptr
  %ng_ptr = getelementptr %RxProgram, ptr %prog, i32 0, i32 2
  %num_groups = load i64, ptr %ng_ptr

  ; --- primera pasada: contar CHAR_CLASS (opcode 5) ---
  %ci = alloca i64
  store i64 0, ptr %ci
  %ncc = alloca i64
  store i64 0, ptr %ncc
  br label %count_loop

count_loop:
  %iv = load i64, ptr %ci
  %cont = icmp ult i64 %iv, %count
  br i1 %cont, label %count_body, label %count_done
count_body:
  %ip = getelementptr %RxInst, ptr %instrs, i64 %iv
  %opp = getelementptr %RxInst, ptr %ip, i32 0, i32 0
  %op = load i64, ptr %opp
  %iscc = icmp eq i64 %op, 5
  br i1 %iscc, label %count_hit, label %count_next
count_hit:
  %n1 = load i64, ptr %ncc
  %n2 = add i64 %n1, 1
  store i64 %n2, ptr %ncc
  br label %count_next
count_next:
  %iv2 = load i64, ptr %ci
  %iv3 = add i64 %iv2, 1
  store i64 %iv3, ptr %ci
  br label %count_loop
count_done:
  %nccv = load i64, ptr %ncc

  ; --- allocar buffer ---
  %body_bytes = mul i64 %count, 24
  %cc_bytes = mul i64 %nccv, 32
  %tmp = add i64 40, %body_bytes
  %buf_total = add i64 %tmp, %cc_bytes
  %buf = call ptr @malloc(i64 %buf_total)

  %h0 = getelementptr i8, ptr %buf, i64 0
  store i64 6076820373606883633, ptr %h0
  %h1 = getelementptr i8, ptr %buf, i64 8
  store i64 %self_hash, ptr %h1
  %h2 = getelementptr i8, ptr %buf, i64 16
  store i64 %dep_hash, ptr %h2
  %h3 = getelementptr i8, ptr %buf, i64 24
  store i64 %count, ptr %h3
  %h4 = getelementptr i8, ptr %buf, i64 32
  store i64 %num_groups, ptr %h4
  %body_dst = getelementptr i8, ptr %buf, i64 40
  %cc_dst = getelementptr i8, ptr %body_dst, i64 %body_bytes

  ; --- segunda pasada: escribir instrucciones + bitsets ---
  store i64 0, ptr %ci
  %ioff = alloca i64
  store i64 0, ptr %ioff
  %coff = alloca i64
  store i64 0, ptr %coff
  br label %copy_loop

copy_loop:
  %iv4 = load i64, ptr %ci
  %cont2 = icmp ult i64 %iv4, %count
  br i1 %cont2, label %copy_body, label %copy_done
copy_body:
  %ip2 = getelementptr %RxInst, ptr %instrs, i64 %iv4
  %op2p = getelementptr %RxInst, ptr %ip2, i32 0, i32 0
  %op2 = load i64, ptr %op2p
  %a1p = getelementptr %RxInst, ptr %ip2, i32 0, i32 1
  %a2p = getelementptr %RxInst, ptr %ip2, i32 0, i32 2
  %a1 = load i64, ptr %a1p
  %a2 = load i64, ptr %a2p
  %iscc2 = icmp eq i64 %op2, 5
  br i1 %iscc2, label %cc_emit, label %plain_emit

cc_emit:
  ; copiar 32 bytes del bitset (a1) al bloque final en cc_dst+coff
  %bsrc = inttoptr i64 %a1 to ptr
  %coffv = load i64, ptr %coff
  %slot = getelementptr i8, ptr %cc_dst, i64 %coffv
  call void @llvm.memcpy.p0.p0.i64(ptr %slot, ptr %bsrc, i64 32, i1 false)
  %coff1 = add i64 %coffv, 32
  store i64 %coff1, ptr %coff
  ; en disco: arg1=0, arg2=indice del bitset (= coffv/32)
  %idx = sdiv i64 %coffv, 32
  br label %write_inst
plain_emit:
  %idx_unused = add i64 %a2, 0
  br label %write_inst

write_inst:
  %out1 = phi i64 [ 0, %cc_emit ], [ %a1, %plain_emit ]
  %out2 = phi i64 [ %idx, %cc_emit ], [ %a2, %plain_emit ]
  %offv = load i64, ptr %ioff
  %dest = getelementptr i8, ptr %body_dst, i64 %offv
  %d0 = getelementptr i8, ptr %dest, i64 0
  store i64 %op2, ptr %d0
  %d1 = getelementptr i8, ptr %dest, i64 8
  store i64 %out1, ptr %d1
  %d2 = getelementptr i8, ptr %dest, i64 16
  store i64 %out2, ptr %d2
  %off1 = add i64 %offv, 24
  store i64 %off1, ptr %ioff
  %iv5 = load i64, ptr %ci
  %iv6 = add i64 %iv5, 1
  store i64 %iv6, ptr %ci
  br label %copy_loop

copy_done:
  %ok = call i32 @fsio_write_file(ptr %path, ptr %buf, i64 %buf_total)
  call void @free(ptr %buf)
  ret i32 %ok
}

; lee %path y valida hashes contra lo esperado. Devuelve RxProgram* si
; matchea, null si no existe / no matchea / archivo corrupto (< 40 bytes).
define ptr @rxprog_deserialize(ptr %path, i64 %expect_self_hash, i64 %expect_dep_hash) {
entry:
  %data_slot = alloca ptr
  %len_slot = alloca i64
  %ok = call i32 @fsio_read_file(ptr %path, ptr %data_slot, ptr %len_slot)
  %ok_b = icmp eq i32 %ok, 1
  br i1 %ok_b, label %check_len, label %fail

check_len:
  %data = load ptr, ptr %data_slot
  %len = load i64, ptr %len_slot
  %len_ok = icmp uge i64 %len, 40
  br i1 %len_ok, label %check_hash, label %fail_free

check_hash:
  %sh_ptr = getelementptr i8, ptr %data, i64 8
  %sh = load i64, ptr %sh_ptr
  %sh_ok = icmp eq i64 %sh, %expect_self_hash
  br i1 %sh_ok, label %check_dep, label %fail_free

check_dep:
  %dh_ptr = getelementptr i8, ptr %data, i64 16
  %dh = load i64, ptr %dh_ptr
  %dh_ok = icmp eq i64 %dh, %expect_dep_hash
  br i1 %dh_ok, label %build, label %fail_free

build:
  %count_ptr = getelementptr i8, ptr %data, i64 24
  %count = load i64, ptr %count_ptr
  %ng_ptr = getelementptr i8, ptr %data, i64 32
  %num_groups = load i64, ptr %ng_ptr
  %body_bytes = mul i64 %count, 24
  %instrs = call ptr @malloc(i64 %body_bytes)
  %body_src = getelementptr i8, ptr %data, i64 40
  %cc_src = getelementptr i8, ptr %body_src, i64 %body_bytes
  %offi = alloca i64
  store i64 0, ptr %offi
  br label %copyloop

copyloop:
  %ci = phi i64 [ 0, %build ], [ %ci_next, %writeinst ]
  %cdone = icmp uge i64 %ci, %count
  br i1 %cdone, label %copydone, label %copybyte

copybyte:
  %instp = getelementptr %RxInst, ptr %instrs, i64 %ci
  %offi_v = load i64, ptr %offi
  %srcp = getelementptr i8, ptr %body_src, i64 %offi_v
  ; copiar los 3 campos del RxInst desde el archivo
  %s0 = getelementptr i8, ptr %srcp, i64 0
  %op = load i64, ptr %s0
  %s1 = getelementptr i8, ptr %srcp, i64 8
  %a1 = load i64, ptr %s1
  %s2 = getelementptr i8, ptr %srcp, i64 16
  %a2 = load i64, ptr %s2
  %iscc = icmp eq i64 %op, 5
  br i1 %iscc, label %rebuild_cc, label %plain

rebuild_cc:
  ; reconstruir bitset fresco desde cc_src + a2*32
  %idx_bytes = mul i64 %a2, 32
  %ccb = getelementptr i8, ptr %cc_src, i64 %idx_bytes
  %newbs = call ptr @malloc(i64 32)
  call void @llvm.memcpy.p0.p0.i64(ptr %newbs, ptr %ccb, i64 32, i1 false)
  %newbs_int = ptrtoint ptr %newbs to i64
  br label %writeinst
plain:
  br label %writeinst

writeinst:
  %out1 = phi i64 [ %newbs_int, %rebuild_cc ], [ %a1, %plain ]
  %d0 = getelementptr %RxInst, ptr %instp, i32 0, i32 0
  store i64 %op, ptr %d0
  %d1 = getelementptr %RxInst, ptr %instp, i32 0, i32 1
  store i64 %out1, ptr %d1
  %d2 = getelementptr %RxInst, ptr %instp, i32 0, i32 2
  store i64 %a2, ptr %d2
  %offi_next = add i64 %offi_v, 24
  store i64 %offi_next, ptr %offi
  %ci_next = add i64 %ci, 1
  br label %copyloop

copydone:
  %prog = call ptr @malloc(i64 24)
  %p0 = getelementptr %RxProgram, ptr %prog, i32 0, i32 0
  store ptr %instrs, ptr %p0
  %p1 = getelementptr %RxProgram, ptr %prog, i32 0, i32 1
  store i64 %count, ptr %p1
  %p2 = getelementptr %RxProgram, ptr %prog, i32 0, i32 2
  store i64 %num_groups, ptr %p2
  call void @fsio_free_buffer(ptr %data)
  ret ptr %prog

fail_free:
  call void @fsio_free_buffer(ptr %data)
  ret ptr null

fail:
  ret ptr null
}
