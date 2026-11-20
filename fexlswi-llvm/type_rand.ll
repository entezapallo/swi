; fexl/type_rand.ll — numeros pseudoaleatorios (antes src/type_rand.c).

@QI = external global ptr

@.s_seed = private constant [10 x i8] c"seed_rand\00"
@.s_rand = private constant [5 x i8] c"rand\00"

declare ptr  @arg(ptr)
declare ptr  @Q(ptr)
declare ptr  @Q0(ptr)
declare ptr  @Qnum(double)
declare ptr  @hold(ptr)
declare void @drop(ptr)
declare void @define(ptr, ptr)
declare ptr  @type_num(ptr)
declare void @srand(i32)
declare i32  @rand()

define private ptr @type_seed_rand(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %x = call ptr @arg(ptr %rv)
  %tp = getelementptr %value, ptr %x, i32 0, i32 1
  %t = load ptr, ptr %tp
  %is = icmp eq ptr %t, @type_num
  br i1 %is, label %yes, label %void
yes:
  %dp = getelementptr %value, ptr %x, i32 0, i32 3
  %d = load double, ptr %dp
  %scaled = fmul double %d, 2147483647.0
  %seed = fptosi double %scaled to i32
  call void @srand(i32 %seed)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  br label %done
void:
  %qv = load ptr, ptr @Qvoid
  %h2 = call ptr @hold(ptr %qv)
  br label %done
done:
  %r = phi ptr [ %h, %yes ], [ %h2, %void ]
  call void @drop(ptr %x)
  ret ptr %r
}

define private ptr @type_rand(ptr %f) {
entry:
  %r = call i32 @rand()
  %d = sitofp i32 %r to double
  %v = fdiv double %d, 2147483647.0
  %q = call ptr @Qnum(double %v)
  ret ptr %q
}

define ptr @type_load_rand(ptr %f) {
entry:
  %q0 = call ptr @Q(ptr @type_seed_rand)
  call void @define(ptr @.s_seed, ptr %q0)
  %q1 = call ptr @Q0(ptr @type_rand)
  call void @define(ptr @.s_rand, ptr %q1)
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}

@Qvoid = external global ptr
