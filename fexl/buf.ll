; fexl/buf.ll — buffer de bytes dinamico (antes src/buf.c).
; struct buffer { size_t len; size_t size; char *data; }

%Buffer = type { i64, i64, ptr }

@cur_blocks = external global i64
@cur_bytes  = external global i64

declare ptr  @resize_memory(ptr, i64, i64)
declare ptr  @memcpy(ptr, ptr, i64)
declare void @free(ptr)

define private void @buf_grow(ptr %buf, i64 %delta) {
entry:
  %sp = getelementptr %Buffer, ptr %buf, i32 0, i32 1
  %osize = load i64, ptr %sp
  %nsize = add i64 %osize, %delta
  %dp = getelementptr %Buffer, ptr %buf, i32 0, i32 2
  %data = load ptr, ptr %dp
  %new = call ptr @resize_memory(ptr %data, i64 %osize, i64 %nsize)
  store ptr %new, ptr %dp
  store i64 %nsize, ptr %sp
  ret void
}

define private void @buf_need(ptr %buf, i64 %need) {
entry:
  %sp = getelementptr %Buffer, ptr %buf, i32 0, i32 1
  %size = load i64, ptr %sp
  %lp = getelementptr %Buffer, ptr %buf, i32 0, i32 0
  %len = load i64, ptr %lp
  %room = sub i64 %size, %len
  %lack = icmp ult i64 %room, %need
  br i1 %lack, label %grow, label %done
grow:
  %mind = sub i64 %need, %room
  %zero = icmp eq i64 %size, 0
  br i1 %zero, label %base, label %checkmark
base:
  br label %mincheck
checkmark:
  %big = icmp ugt i64 %size, 1048576
  br i1 %big, label %half, label %mincheck
half:
  %halfv = lshr i64 %size, 1
  br label %mincheck
mincheck:
  %delta = phi i64 [ 64, %base ], [ %size, %checkmark ], [ %halfv, %half ]
  %enough = icmp uge i64 %delta, %mind
  br i1 %enough, label %callgrow, label %usemind
usemind:
  br label %callgrow
callgrow:
  %d = phi i64 [ %delta, %mincheck ], [ %mind, %usemind ]
  call void @buf_grow(ptr %buf, i64 %d)
  br label %done
done:
  ret void
}

define void @buf_add(ptr %buf, i8 %ch) {
entry:
  call void @buf_need(ptr %buf, i64 1)
  %lp = getelementptr %Buffer, ptr %buf, i32 0, i32 0
  %len = load i64, ptr %lp
  %dp = getelementptr %Buffer, ptr %buf, i32 0, i32 2
  %data = load ptr, ptr %dp
  %at = getelementptr i8, ptr %data, i64 %len
  store i8 %ch, ptr %at
  %len1 = add i64 %len, 1
  store i64 %len1, ptr %lp
  ret void
}

define void @buf_addn(ptr %buf, ptr %str, i64 %len) {
entry:
  call void @buf_need(ptr %buf, i64 %len)
  %lp = getelementptr %Buffer, ptr %buf, i32 0, i32 0
  %cur = load i64, ptr %lp
  %dp = getelementptr %Buffer, ptr %buf, i32 0, i32 2
  %data = load ptr, ptr %dp
  %dst = getelementptr i8, ptr %data, i64 %cur
  %r = call ptr @memcpy(ptr %dst, ptr %str, i64 %len)
  %newlen = add i64 %cur, %len
  store i64 %newlen, ptr %lp
  ret void
}

define void @buf_discard(ptr %buf) {
entry:
  %dp = getelementptr %Buffer, ptr %buf, i32 0, i32 2
  %data = load ptr, ptr %dp
  %nonnull = icmp ne ptr %data, null
  br i1 %nonnull, label %decblocks, label %decbytes
decblocks:
  %b = load i64, ptr @cur_blocks
  %b1 = sub i64 %b, 1
  store i64 %b1, ptr @cur_blocks
  br label %decbytes
decbytes:
  call void @free(ptr %data)
  %sp = getelementptr %Buffer, ptr %buf, i32 0, i32 1
  %size = load i64, ptr %sp
  %y = load i64, ptr @cur_bytes
  %y1 = sub i64 %y, %size
  store i64 %y1, ptr @cur_bytes
  store i64 0, ptr %sp
  %lp = getelementptr %Buffer, ptr %buf, i32 0, i32 0
  store i64 0, ptr %lp
  store ptr null, ptr %dp
  ret void
}
