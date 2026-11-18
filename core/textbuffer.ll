; core/textbuffer.ll — buffer de texto plano, LLVM IR moderno (ptr opaco)
; MVP: create/destroy/insert/length/data.

%TextBuffer = type { ptr, i64, i64 }  ; { data, length, capacity }

declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare ptr @memmove(ptr, ptr, i64)

define ptr @tb_create() {
entry:
  %tb = call ptr @malloc(i64 24)
  %data_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 0
  store ptr null, ptr %data_ptr
  %len_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 1
  store i64 0, ptr %len_ptr
  %cap_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 2
  store i64 0, ptr %cap_ptr
  ret ptr %tb
}

define void @tb_destroy(ptr %tb) {
entry:
  %data_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 0
  %data = load ptr, ptr %data_ptr
  %isnull = icmp eq ptr %data, null
  br i1 %isnull, label %skip, label %dofree

dofree:
  call void @free(ptr %data)
  br label %skip

skip:
  call void @free(ptr %tb)
  ret void
}

define i64 @tb_length(ptr %tb) {
entry:
  %len_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 1
  %len = load i64, ptr %len_ptr
  ret i64 %len
}

define ptr @tb_data(ptr %tb) {
entry:
  %data_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 0
  %data = load ptr, ptr %data_ptr
  ret ptr %data
}

; devuelve i32 (1=ok, 0=pos>length) en vez de i1: cruzando a C, un i1 sin
; zeroext explícito no tiene representación garantizada en el ABI — i32 es seguro.
define i32 @tb_insert(ptr %tb, i64 %pos, ptr %src, i64 %srclen) {
entry:
  %len_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 1
  %length = load i64, ptr %len_ptr
  %pos_ok = icmp ule i64 %pos, %length
  br i1 %pos_ok, label %proceed, label %fail

proceed:
  %cap_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 2
  %capacity = load i64, ptr %cap_ptr
  %data_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 0
  %data = load ptr, ptr %data_ptr
  %newlen = add i64 %length, %srclen
  %needgrow = icmp ugt i64 %newlen, %capacity
  br i1 %needgrow, label %grow, label %shift

grow:
  %newdata = call ptr @realloc(ptr %data, i64 %newlen)
  store ptr %newdata, ptr %data_ptr
  store i64 %newlen, ptr %cap_ptr
  br label %shift

shift:
  %curdata = load ptr, ptr %data_ptr
  %tail_len = sub i64 %length, %pos
  %has_tail = icmp ugt i64 %tail_len, 0
  br i1 %has_tail, label %domove, label %docopy

domove:
  %destpos = add i64 %pos, %srclen
  %src_off = getelementptr i8, ptr %curdata, i64 %pos
  %dst_off = getelementptr i8, ptr %curdata, i64 %destpos
  call ptr @memmove(ptr %dst_off, ptr %src_off, i64 %tail_len)
  br label %docopy

docopy:
  %ins_off = getelementptr i8, ptr %curdata, i64 %pos
  call ptr @memcpy(ptr %ins_off, ptr %src, i64 %srclen)
  store i64 %newlen, ptr %len_ptr
  ret i32 1

fail:
  ret i32 0
}
; devuelve i32 (1=ok, 0=rango inválido) — mismo criterio que tb_insert.
; no shrinkea capacity: el buffer plano solo crece, libera todo junto en tb_destroy.
define i32 @tb_delete(ptr %tb, i64 %pos, i64 %dellen) {
entry:
  %len_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 1
  %length = load i64, ptr %len_ptr
  %end = add i64 %pos, %dellen
  %pos_ok = icmp ule i64 %pos, %length
  %end_ok = icmp ule i64 %end, %length
  %range_ok = and i1 %pos_ok, %end_ok
  br i1 %range_ok, label %proceed, label %fail

proceed:
  %data_ptr = getelementptr %TextBuffer, ptr %tb, i32 0, i32 0
  %data = load ptr, ptr %data_ptr
  %tail_len = sub i64 %length, %end
  %has_tail = icmp ugt i64 %tail_len, 0
  br i1 %has_tail, label %domove, label %updatelen

domove:
  %src_off = getelementptr i8, ptr %data, i64 %end
  %dst_off = getelementptr i8, ptr %data, i64 %pos
  call ptr @memmove(ptr %dst_off, ptr %src_off, i64 %tail_len)
  br label %updatelen

updatelen:
  %newlen = sub i64 %length, %dellen
  store i64 %newlen, ptr %len_ptr
  ret i32 1

fail:
  ret i32 0
}
