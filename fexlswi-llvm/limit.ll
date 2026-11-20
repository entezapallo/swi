; fexl/limit.ll — limites de recursos (antes src/limit.c).

%Rlimit = type { i64, i64 }

@.getrlimit = private constant [10 x i8] c"getrlimit\00"
@.setrlimit = private constant [10 x i8] c"setrlimit\00"

declare i32  @getrlimit(i32, ptr)
declare i32  @setrlimit(i32, ptr)
declare void @perror(ptr)
declare void @die(ptr)

define private void @set_limit(i32 %resource, i64 %n) {
entry:
  %rlim = alloca %Rlimit, align 8
  %r = call i32 @getrlimit(i32 %resource, ptr %rlim)
  %bad = icmp slt i32 %r, 0
  br i1 %bad, label %dieget, label %set
dieget:
  call void @perror(ptr @.getrlimit)
  call void @die(ptr null)
  unreachable
set:
  %cur = getelementptr %Rlimit, ptr %rlim, i32 0, i32 0
  store i64 %n, ptr %cur
  %s = call i32 @setrlimit(i32 %resource, ptr %rlim)
  %bad2 = icmp slt i32 %s, 0
  br i1 %bad2, label %dieset, label %done
dieset:
  call void @perror(ptr @.setrlimit)
  call void @die(ptr null)
  unreachable
done:
  ret void
}

define void @limit_time(i64 %n) {
entry:
  call void @set_limit(i32 0, i64 %n)
  ret void
}

define void @limit_stack(i64 %n) {
entry:
  call void @set_limit(i32 3, i64 %n)
  ret void
}

define void @limit_memory(i64 %n) {
entry:
  call void @set_limit(i32 9, i64 %n)
  ret void
}
