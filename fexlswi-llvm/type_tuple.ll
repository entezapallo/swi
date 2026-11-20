; fexl/type_tuple.ll — tuplas (antes src/type_tuple.c).

@QI     = external global ptr
@Qvoid  = external global ptr
@Qnull  = external global ptr
@Qtuple = global ptr null

@.s_is_tuple       = private constant [9 x i8] c"is_tuple\00"
@.s_tuple_to_list  = private constant [14 x i8] c"tuple_to_list\00"
@.s_list_to_tuple  = private constant [14 x i8] c"list_to_tuple\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @V(ptr, ptr, ptr)
declare ptr  @A(ptr, ptr)
declare ptr  @Qnum(double)
declare ptr  @cons(ptr, ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare ptr  @eval(ptr)
declare ptr  @tail(ptr)
declare ptr  @boolean(i32)
declare void @define(ptr, ptr)
declare ptr  @type_list(ptr)
declare ptr  @type_null(ptr)
declare ptr  @type_pair(ptr)

define ptr @type_tuple(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LRp = getelementptr %value, ptr %L, i32 0, i32 3
  %args0 = load ptr, ptr %LRp
  %args1 = call ptr @hold(ptr %args0)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %exp0 = load ptr, ptr %rp
  %exp1 = call ptr @hold(ptr %exp0)
  br label %loop
loop:
  %args = phi ptr [ %args1, %entry ], [ %args3, %listcase ]
  %exp = phi ptr [ %exp1, %entry ], [ %exp3, %listcase ]
  %ev = call ptr @eval(ptr %args)
  %tp = getelementptr %value, ptr %ev, i32 0, i32 1
  %t = load ptr, ptr %tp
  %islist = icmp eq ptr %t, @type_list
  br i1 %islist, label %listcase, label %checknull
listcase:
  %lp = getelementptr %value, ptr %ev, i32 0, i32 2
  %first = load ptr, ptr %lp
  %hf = call ptr @hold(ptr %first)
  %exp3 = call ptr @A(ptr %exp, ptr %hf)
  %args3 = call ptr @tail(ptr %ev)
  br label %loop
checknull:
  %isnull = icmp eq ptr %t, @type_null
  br i1 %isnull, label %nullcase, label %bad
nullcase:
  call void @drop(ptr %ev)
  ret ptr %exp
bad:
  call void @drop(ptr %exp)
  call void @drop(ptr %ev)
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  ret ptr %h
}

define private ptr @type_is_tuple(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %ist = icmp eq ptr %t, @type_tuple
  %isp = icmp eq ptr %t, @type_pair
  %ok = or i1 %ist, %isp
  %ci = zext i1 %ok to i32
  %res = call ptr @boolean(i32 %ci)
  call void @drop(ptr %x)
  ret ptr %res
}

define private ptr @type_tuple_to_list(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %ist = icmp eq ptr %t, @type_tuple
  br i1 %ist, label %tup, label %checkpair
tup:
  %xrp = getelementptr %value, ptr %x, i32 0, i32 3
  %r = load ptr, ptr %xrp
  %res = call ptr @hold(ptr %r)
  br label %done
checkpair:
  %isp = icmp eq ptr %t, @type_pair
  br i1 %isp, label %paircase, label %void
paircase:
  %xlp = getelementptr %value, ptr %x, i32 0, i32 2
  %l = load ptr, ptr %xlp
  %xrp2 = getelementptr %value, ptr %x, i32 0, i32 3
  %r2 = load ptr, ptr %xrp2
  %hl = call ptr @hold(ptr %l)
  %hr = call ptr @hold(ptr %r2)
  %qn = load ptr, ptr @Qnull
  %hqn = call ptr @hold(ptr %qn)
  %inner = call ptr @cons(ptr %hr, ptr %hqn)
  %res2 = call ptr @cons(ptr %hl, ptr %inner)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h = call ptr @hold(ptr %qv)
  br label %done
done:
  %result = phi ptr [ %res, %tup ], [ %res2, %paircase ], [ %h, %void ]
  call void @drop(ptr %x)
  ret ptr %result
}

define private ptr @type_list_to_tuple(ptr %f) {
entry:
  %qt = load ptr, ptr @Qtuple
  %hqt = call ptr @hold(ptr %qt)
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %hr = call ptr @hold(ptr %rv)
  %res = call ptr @V(ptr @type_tuple, ptr %hqt, ptr %hr)
  ret ptr %res
}

define ptr @type_load_tuple(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_is_tuple)
  call void @define(ptr @.s_is_tuple, ptr %q0)
  %q1 = call ptr @Q(ptr @type_tuple_to_list)
  call void @define(ptr @.s_tuple_to_list, ptr %q1)
  %q2 = call ptr @Q(ptr @type_list_to_tuple)
  call void @define(ptr @.s_list_to_tuple, ptr %q2)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

define void @beg_tuple() {
entry:
  %q = call ptr @Q(ptr @type_tuple)
  store ptr %q, ptr @Qtuple
  ret void
}

define void @end_tuple() {
entry:
  %q = load ptr, ptr @Qtuple
  call void @drop(ptr %q)
  ret void
}
