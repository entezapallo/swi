; fsio/fsio_list_dir.ll — listado de directorio, syscalls crudas (getdents64),
; mismo estilo que fsio_posix.ll: mueve i8*/i64 crudo, dueño de lo malloc'd es
; quien llama. No usa opendir/readdir de libc (ABI de DIR* distinta, se evita).

declare i32 @open(ptr, i32, i32)
declare i32 @close(i32)
declare i64 @lseek(i32, i64, i32)
declare i64 @getdents64(i32, ptr, i64)
declare i64 @strlen(ptr)
declare ptr @malloc(i64)
declare void @free(ptr)

; O_RDONLY | O_DIRECTORY (Linux x86-64) = 0 | 0200000(oct) = 65536
; struct linux_dirent64: d_ino:8 d_off:8 d_reclen:u16@16 d_type:u8@18 d_name@19 (NUL-term)

; 1 si %p es "." o ".." , 0 si no.
define internal i32 @is_dot_entry(ptr %p) {
entry:
  %c0 = load i8, ptr %p
  %is_dot = icmp eq i8 %c0, 46
  br i1 %is_dot, label %check1, label %no

check1:
  %p1 = getelementptr i8, ptr %p, i64 1
  %c1 = load i8, ptr %p1
  %c1_nul = icmp eq i8 %c1, 0
  br i1 %c1_nul, label %yes, label %check2

check2:
  %c1_dot = icmp eq i8 %c1, 46
  br i1 %c1_dot, label %check2b, label %no

check2b:
  %p2 = getelementptr i8, ptr %p, i64 2
  %c2 = load i8, ptr %p2
  %c2_nul = icmp eq i8 %c2, 0
  br i1 %c2_nul, label %yes, label %no

yes:
  ret i32 1
no:
  ret i32 0
}

; devuelve i32 (1=ok, 0=fail). out_names recibe ptr malloc'd a array de ptr
; (cada string malloc'd, NUL-terminada, dueño: quien llama). out_count recibe
; la cantidad de entradas. Excluye "." y "..". Liberar con fsio_free_dir_list.
define i32 @fsio_list_dir(ptr %path, ptr %out_names, ptr %out_count) {
entry:
  %fd = call i32 @open(ptr %path, i32 65536, i32 0)
  %open_ok = icmp sge i32 %fd, 0
  br i1 %open_ok, label %pass1_init, label %fail_noclose

pass1_init:
  %cbuf = alloca [8192 x i8]
  %cbuf_ptr = getelementptr [8192 x i8], ptr %cbuf, i32 0, i32 0
  br label %pass1_read

pass1_read:
  %p1_count = phi i64 [ 0, %pass1_init ], [ %p1_acc, %pass1_scan_exit ]
  %n1 = call i64 @getdents64(i32 %fd, ptr %cbuf_ptr, i64 8192)
  %n1_done = icmp sle i64 %n1, 0
  br i1 %n1_done, label %pass1_done, label %p1_scan_entry

p1_scan_entry:
  br label %p1_scan

p1_scan:
  %p1_off = phi i64 [ 0, %p1_scan_entry ], [ %p1_off_next, %p1_scan_next ]
  %p1_acc = phi i64 [ %p1_count, %p1_scan_entry ], [ %p1_acc_next, %p1_scan_next ]
  %p1_scan_done = icmp sge i64 %p1_off, %n1
  br i1 %p1_scan_done, label %pass1_scan_exit, label %p1_entry

p1_entry:
  %p1_ep = getelementptr i8, ptr %cbuf_ptr, i64 %p1_off
  %p1_rl_ptr = getelementptr i8, ptr %p1_ep, i64 16
  %p1_rl16 = load i16, ptr %p1_rl_ptr
  %p1_rl = zext i16 %p1_rl16 to i64
  %p1_name = getelementptr i8, ptr %p1_ep, i64 19
  %p1_skip = call i32 @is_dot_entry(ptr %p1_name)
  %p1_skip_b = icmp eq i32 %p1_skip, 1
  br i1 %p1_skip_b, label %p1_scan_next, label %p1_incr

p1_incr:
  %p1_acc_inc = add i64 %p1_acc, 1
  br label %p1_scan_next

p1_scan_next:
  %p1_acc_next = phi i64 [ %p1_acc, %p1_entry ], [ %p1_acc_inc, %p1_incr ]
  %p1_off_next = add i64 %p1_off, %p1_rl
  br label %p1_scan

pass1_scan_exit:
  br label %pass1_read

pass1_done:
  %rewind_rc = call i64 @lseek(i32 %fd, i64 0, i32 0)
  %is_empty = icmp eq i64 %p1_count, 0
  br i1 %is_empty, label %empty_ok, label %pass2_alloc

pass2_alloc:
  %arr_bytes = mul i64 %p1_count, 8
  %arr = call ptr @malloc(i64 %arr_bytes)
  br label %pass2_read

pass2_read:
  %p2_idx = phi i64 [ 0, %pass2_alloc ], [ %p2_idx2, %pass2_scan_exit ]
  %n2 = call i64 @getdents64(i32 %fd, ptr %cbuf_ptr, i64 8192)
  %n2_done = icmp sle i64 %n2, 0
  br i1 %n2_done, label %pass2_done, label %p2_scan_entry

p2_scan_entry:
  br label %p2_scan

p2_scan:
  %p2_off = phi i64 [ 0, %p2_scan_entry ], [ %p2_off_next, %p2_scan_next ]
  %p2_idx2 = phi i64 [ %p2_idx, %p2_scan_entry ], [ %p2_idx2_next, %p2_scan_next ]
  %p2_scan_done = icmp sge i64 %p2_off, %n2
  br i1 %p2_scan_done, label %pass2_scan_exit, label %p2_entry

p2_entry:
  %p2_ep = getelementptr i8, ptr %cbuf_ptr, i64 %p2_off
  %p2_rl_ptr = getelementptr i8, ptr %p2_ep, i64 16
  %p2_rl16 = load i16, ptr %p2_rl_ptr
  %p2_rl = zext i16 %p2_rl16 to i64
  %p2_name = getelementptr i8, ptr %p2_ep, i64 19
  %p2_skip = call i32 @is_dot_entry(ptr %p2_name)
  %p2_skip_b = icmp eq i32 %p2_skip, 1
  br i1 %p2_skip_b, label %p2_scan_next, label %p2_copy

p2_copy:
  %nlen = call i64 @strlen(ptr %p2_name)
  %nlen1 = add i64 %nlen, 1
  %ndst = call ptr @malloc(i64 %nlen1)
  br label %p2_copyloop

p2_copyloop:
  %ci = phi i64 [ 0, %p2_copy ], [ %ci_next, %p2_copybyte ]
  %ci_done = icmp uge i64 %ci, %nlen1
  br i1 %ci_done, label %p2_copy_done, label %p2_copybyte

p2_copybyte:
  %csrc = getelementptr i8, ptr %p2_name, i64 %ci
  %cdst = getelementptr i8, ptr %ndst, i64 %ci
  %cval = load i8, ptr %csrc
  store i8 %cval, ptr %cdst
  %ci_next = add i64 %ci, 1
  br label %p2_copyloop

p2_copy_done:
  %slot = getelementptr ptr, ptr %arr, i64 %p2_idx2
  store ptr %ndst, ptr %slot
  %p2_idx2_inc = add i64 %p2_idx2, 1
  br label %p2_scan_next

p2_scan_next:
  %p2_idx2_next = phi i64 [ %p2_idx2, %p2_entry ], [ %p2_idx2_inc, %p2_copy_done ]
  %p2_off_next = add i64 %p2_off, %p2_rl
  br label %p2_scan

pass2_scan_exit:
  br label %pass2_read

pass2_done:
  %close_rc1 = call i32 @close(i32 %fd)
  store ptr %arr, ptr %out_names
  store i64 %p1_count, ptr %out_count
  ret i32 1

empty_ok:
  %close_rc2 = call i32 @close(i32 %fd)
  store ptr null, ptr %out_names
  store i64 0, ptr %out_count
  ret i32 1

fail_noclose:
  ret i32 0
}

; libera lo devuelto por fsio_list_dir. No-op si names es null.
define void @fsio_free_dir_list(ptr %names, i64 %count) {
entry:
  %isnull = icmp eq ptr %names, null
  br i1 %isnull, label %free_arr, label %loop_init

loop_init:
  br label %loop

loop:
  %i = phi i64 [ 0, %loop_init ], [ %i_next, %loop_body ]
  %done = icmp uge i64 %i, %count
  br i1 %done, label %free_arr, label %loop_body

loop_body:
  %slot = getelementptr ptr, ptr %names, i64 %i
  %s = load ptr, ptr %slot
  call void @free(ptr %s)
  %i_next = add i64 %i, 1
  br label %loop

free_arr:
  call void @free(ptr %names)
  ret void
}
