; fexl/type_hex.ll — conversion hex <-> bytes (antes src/type_hex.c).

@QI    = external global ptr
@Qvoid = external global ptr

@.s_unpack = private constant [7 x i8] c"unpack\00"
@.s_pack   = private constant [5 x i8] c"pack\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Qstr(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare void @define(ptr, ptr)
declare ptr  @str_new(i64)
declare ptr  @type_str(ptr)

define private i8 @nibble_to_hex(i8 %n) {
entry:
  %lt = icmp ult i8 %n, 10
  br i1 %lt, label %digit, label %alpha
digit:
  %d = add i8 %n, 48
  ret i8 %d
alpha:
  %a = sub i8 %n, 10
  %v = add i8 %a, 97
  ret i8 %v
}

define private i8 @hex_to_nibble(i8 %n) {
entry:
  %ge0 = icmp uge i8 %n, 48
  %le9 = icmp ule i8 %n, 57
  %dig = and i1 %ge0, %le9
  br i1 %dig, label %d, label %checklower
d:
  %v = sub i8 %n, 48
  ret i8 %v
checklower:
  %gea = icmp uge i8 %n, 97
  %lef = icmp ule i8 %n, 102
  %low = and i1 %gea, %lef
  br i1 %low, label %lo, label %checkupper
lo:
  %v2 = sub i8 %n, 87
  ret i8 %v2
checkupper:
  %geA = icmp uge i8 %n, 65
  %leF = icmp ule i8 %n, 70
  %up = and i1 %geA, %leF
  br i1 %up, label %hi, label %zero
hi:
  %v3 = sub i8 %n, 55
  ret i8 %v3
zero:
  ret i8 0
}

define private ptr @unpack(ptr %raw) {
entry:
  %lp = getelementptr i8, ptr %raw, i64 0
  %len = load i64, ptr %lp
  %n = shl i64 %len, 1
  %hex = call ptr @str_new(i64 %n)
  br label %loop
loop:
  %pos = phi i64 [ 0, %entry ], [ %pos1, %body ]
  %cont = icmp ult i64 %pos, %len
  br i1 %cont, label %body, label %done
body:
  %rd = getelementptr i8, ptr %raw, i64 8
  %src = getelementptr i8, ptr %rd, i64 %pos
  %ch = load i8, ptr %src
  %shift = lshr i8 %ch, 4
  %h = call i8 @nibble_to_hex(i8 %shift)
  %mask = and i8 %ch, 15
  %l = call i8 @nibble_to_hex(i8 %mask)
  %hd = getelementptr i8, ptr %hex, i64 8
  %p2 = shl i64 %pos, 1
  %dst0 = getelementptr i8, ptr %hd, i64 %p2
  %p1 = add i64 %p2, 1
  %dst1 = getelementptr i8, ptr %hd, i64 %p1
  store i8 %h, ptr %dst0
  store i8 %l, ptr %dst1
  %pos1 = add i64 %pos, 1
  br label %loop
done:
  ret ptr %hex
}

define private ptr @pack(ptr %hex) {
entry:
  %lp = getelementptr i8, ptr %hex, i64 0
  %hlen = load i64, ptr %lp
  %len = lshr i64 %hlen, 1
  %raw = call ptr @str_new(i64 %len)
  br label %loop
loop:
  %pos = phi i64 [ 0, %entry ], [ %pos1, %body ]
  %cont = icmp ult i64 %pos, %len
  br i1 %cont, label %body, label %done
body:
  %hd = getelementptr i8, ptr %hex, i64 8
  %p2 = shl i64 %pos, 1
  %s0 = getelementptr i8, ptr %hd, i64 %p2
  %p1 = add i64 %p2, 1
  %s1 = getelementptr i8, ptr %hd, i64 %p1
  %hc = load i8, ptr %s0
  %lc = load i8, ptr %s1
  %hi = call i8 @hex_to_nibble(i8 %hc)
  %lo = call i8 @hex_to_nibble(i8 %lc)
  %hshift = shl i8 %hi, 4
  %byte = or i8 %hshift, %lo
  %rd = getelementptr i8, ptr %raw, i64 8
  %dst = getelementptr i8, ptr %rd, i64 %pos
  store i8 %byte, ptr %dst
  %pos1 = add i64 %pos, 1
  br label %loop
done:
  ret ptr %raw
}

define private ptr @type_unpack(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %xvp
  %r = call ptr @unpack(ptr %s)
  %q = call ptr @Qstr(ptr %r)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %res = phi ptr [ %q, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %res
}

define private ptr @type_pack(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_str
  br i1 %is, label %yes, label %void
yes:
  %xvp = getelementptr %value, ptr %x, i32 0, i32 3
  %s = load ptr, ptr %xvp
  %r = call ptr @pack(ptr %s)
  %q = call ptr @Qstr(ptr %r)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %res = phi ptr [ %q, %yes ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %res
}

define ptr @type_load_hex(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_unpack)
  call void @define(ptr @.s_unpack, ptr %q0)
  %q1 = call ptr @Q(ptr @type_pack)
  call void @define(ptr @.s_pack, ptr %q1)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
