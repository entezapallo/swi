; fexl/value.ll — reducer y managed de referencias del intérprete Fexl.
; Reemplaza fexlswi/src/value.c. Expone las mismas funciones C, así que los
; módulos `type_*.c` que siguen en C linkan sin cambios.
;
; %value viene de value_types.ll (se inyecta por concatenación en el build).

@free_list = internal global ptr null
@drop_list = internal global ptr null
@cur_steps = global i64 0

declare ptr  @new_memory(i64)
declare void @free_memory(ptr, i64)
declare void @end_memory()

; f = free_list ? saco de la lista : new_memory(32)
define ptr @new_value() {
entry:
  %f = load ptr, ptr @free_list
  %nonnull = icmp ne ptr %f, null
  br i1 %nonnull, label %reuse, label %fresh
reuse:
  %nextp = getelementptr %value, ptr %f, i32 0, i32 0
  %next = load ptr, ptr %nextp
  store ptr %next, ptr @free_list
  ret ptr %f
fresh:
  %p = call ptr @new_memory(i64 32)
  ret ptr %p
}

; Devuelve f a la free list (f->next = free_list; free_list = f).
define void @recycle(ptr %f) {
entry:
  %fl = load ptr, ptr @free_list
  %nextp = getelementptr %value, ptr %f, i32 0, i32 0
  store ptr %fl, ptr %nextp
  store ptr %f, ptr @free_list
  ret void
}

; Decrementa el refcount y encola en drop_list si llega a cero.
define private void @drop_child(ptr %f) {
entry:
  %np = getelementptr %value, ptr %f, i32 0, i32 0
  %n = load i64, ptr %np
  %n1 = sub i64 %n, 1
  store i64 %n1, ptr %np
  %is0 = icmp eq i64 %n1, 0
  br i1 %is0, label %push, label %done
push:
  %dl = load ptr, ptr @drop_list
  ; reutilizo el mismo slot (N/next) como enlace de la lista
  %nextp = getelementptr %value, ptr %f, i32 0, i32 0
  store ptr %dl, ptr %nextp
  store ptr %f, ptr @drop_list
  br label %done
done:
  ret void
}

; Suelta los hijos de f y lo recicla. Si f->L es un data value, llama a su
; `clear` (que está en el mismo slot que T del hijo).
define private void @vacate(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %hasL = icmp ne ptr %L, null
  br i1 %hasL, label %check, label %recycle
check:
  %LNp = getelementptr %value, ptr %L, i32 0, i32 0
  %LN = load i64, ptr %LNp
  %isdata = icmp eq i64 %LN, 0
  br i1 %isdata, label %doclear, label %dropchildren
; f->L->clear(f): el slot T del hijo es el puntero a clear
doclear:
  %Tp = getelementptr %value, ptr %L, i32 0, i32 1
  %clr = load ptr, ptr %Tp
  call void %clr(ptr %f)
  br label %recycle
dropchildren:
  call void @drop_child(ptr %L)
  %Rp = getelementptr %value, ptr %f, i32 0, i32 3
  %R = load ptr, ptr %Rp
  call void @drop_child(ptr %R)
  br label %recycle
recycle:
  call void @recycle(ptr %f)
  ret void
}

; descarta(f) y procesa la drop_list completa.
define private void @discard(ptr %f) {
entry:
  call void @vacate(ptr %f)
  br label %loop
loop:
  %d = load ptr, ptr @drop_list
  %nonnull = icmp ne ptr %d, null
  br i1 %nonnull, label %body, label %done
body:
  %nextp = getelementptr %value, ptr %d, i32 0, i32 0
  %next = load ptr, ptr %nextp
  store ptr %next, ptr @drop_list
  call void @vacate(ptr %d)
  br label %loop
done:
  ret void
}

define ptr @hold(ptr %f) {
entry:
  %np = getelementptr %value, ptr %f, i32 0, i32 0
  %n = load i64, ptr %np
  %n1 = add i64 %n, 1
  store i64 %n1, ptr %np
  ret ptr %f
}

define void @drop(ptr %f) {
entry:
  %np = getelementptr %value, ptr %f, i32 0, i32 0
  %n = load i64, ptr %np
  %n1 = sub i64 %n, 1
  store i64 %n1, ptr %np
  %is0 = icmp eq i64 %n1, 0
  br i1 %is0, label %discardf, label %done
discardf:
  call void @discard(ptr %f)
  br label %done
done:
  ret void
}

define void @clear_free_list() {
entry:
  br label %loop
loop:
  %f = load ptr, ptr @free_list
  %nonnull = icmp ne ptr %f, null
  br i1 %nonnull, label %body, label %done
body:
  %nextp = getelementptr %value, ptr %f, i32 0, i32 0
  %next = load ptr, ptr %nextp
  store ptr %next, ptr @free_list
  call void @free_memory(ptr %f, i64 32)
  br label %loop
done:
  ret void
}

define void @end_value() {
entry:
  call void @clear_free_list()
  call void @end_memory()
  ret void
}

; V(T,L,R): refcount 1
define ptr @V(ptr %T, ptr %L, ptr %R) {
entry:
  %f = call ptr @new_value()
  %np = getelementptr %value, ptr %f, i32 0, i32 0
  store i64 1, ptr %np
  %Tp = getelementptr %value, ptr %f, i32 0, i32 1
  store ptr %T, ptr %Tp
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  store ptr %L, ptr %Lp
  %Rp = getelementptr %value, ptr %f, i32 0, i32 3
  store ptr %R, ptr %Rp
  ret ptr %f
}

define ptr @Q(ptr %T) {
entry:
  %f = call ptr @V(ptr %T, ptr null, ptr null)
  ret ptr %f
}

; A(x,y) es una aplicación: T == 0.
define ptr @A(ptr %x, ptr %y) {
entry:
  %f = call ptr @V(ptr null, ptr %x, ptr %y)
  ret ptr %f
}

; keep(f): copia el T de f->L y hace hold.
define ptr @keep(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %Lp
  %LTp = getelementptr %value, ptr %L, i32 0, i32 1
  %LT = load ptr, ptr %LTp
  %Tp = getelementptr %value, ptr %f, i32 0, i32 1
  store ptr %LT, ptr %Tp
  %r = call ptr @hold(ptr %f)
  ret ptr %r
}

; tail(f): hold(f->R), drop(f).
define ptr @tail(ptr %f) {
entry:
  %Rp = getelementptr %value, ptr %f, i32 0, i32 3
  %R = load ptr, ptr %Rp
  %x = call ptr @hold(ptr %R)
  call void @drop(ptr %f)
  ret ptr %x
}

declare ptr @aot_step_fast(ptr)
@aot_enabled = external global i32

; step(f) — el corazón del trampolín. Publico para el AOT (aot_step_fast
; delega aca cuando la aplicacion no esta lista).
define ptr @step(ptr %f) {
entry:
  %Lf = getelementptr %value, ptr %f, i32 0, i32 2
  %g = load ptr, ptr %Lf
  %Tgp = getelementptr %value, ptr %g, i32 0, i32 1
  %Tg = load ptr, ptr %Tgp
  %isapp = icmp eq ptr %Tg, null
  br i1 %isapp, label %app, label %callmerge_pre

app:
  %Nfp = getelementptr %value, ptr %f, i32 0, i32 0
  %N = load i64, ptr %Nfp
  %isone = icmp eq i64 %N, 1
  br i1 %isone, label %inplace, label %copy

; g = (f->L = eval(g))
inplace:
  %g1 = call ptr @eval(ptr %g)
  store ptr %g1, ptr %Lf
  br label %callmerge_pre

copy:
  %gh = call ptr @hold(ptr %g)
  %g2 = call ptr @eval(ptr %gh)
  %oldL = load ptr, ptr %Lf
  %same = icmp eq ptr %g2, %oldL
  br i1 %same, label %dropg, label %newapp

dropg:
  call void @drop(ptr %g2)
  br label %callmerge_pre

; f = A(g2, tail(f)); g queda g2
newapp:
  %t = call ptr @tail(ptr %f)
  %nf = call ptr @A(ptr %g2, ptr %t)
  br label %callmerge_new

callmerge_pre:
  %fp = phi ptr [ %f, %entry ], [ %f, %inplace ], [ %f, %dropg ]
  %gp = phi ptr [ %g, %entry ], [ %g1, %inplace ], [ %g, %dropg ]
  br label %call

callmerge_new:
  br label %call

call:
  %fphi = phi ptr [ %fp, %callmerge_pre ], [ %nf, %callmerge_new ]
  %gphi = phi ptr [ %gp, %callmerge_pre ], [ %g2, %callmerge_new ]
  %Tp = getelementptr %value, ptr %gphi, i32 0, i32 1
  %T = load ptr, ptr %Tp
  %r = call ptr %T(ptr %fphi)
  call void @drop(ptr %fphi)
  %s = load i64, ptr @cur_steps
  %s1 = add i64 %s, 1
  store i64 %s1, ptr @cur_steps
  ret ptr %r
}

; eval(f): mientras f->T == 0, step(). Si @aot_enabled, usa la via rapida
; del AOT (default 0, comportamiento original).
define ptr @eval(ptr %f) {
entry:
  br label %loop
loop:
  %fp = phi ptr [ %f, %entry ], [ %next, %steptime ]
  %Tp = getelementptr %value, ptr %fp, i32 0, i32 1
  %T = load ptr, ptr %Tp
  %isapp = icmp eq ptr %T, null
  br i1 %isapp, label %again, label %done
again:
  %flagon = load i32, ptr @aot_enabled
  %useaot = icmp ne i32 %flagon, 0
  br i1 %useaot, label %aotstep, label %normstep
aotstep:
  %ra = call ptr @aot_step_fast(ptr %fp)
  br label %steptime
normstep:
  %rn = call ptr @step(ptr %fp)
  br label %steptime
steptime:
  %next = phi ptr [ %ra, %aotstep ], [ %rn, %normstep ]
  br label %loop
done:
  ret ptr %fp
}

; arg(f) = eval(hold(f))
define ptr @arg(ptr %f) {
entry:
  %h = call ptr @hold(ptr %f)
  %r = call ptr @eval(ptr %h)
  ret ptr %r
}
