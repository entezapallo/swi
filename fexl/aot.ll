; fexl/aot.ll — prototipo AOT ( ahead-of-time ) del Paso 1.
;
; Detector automatico: recorre el grafo de un valor y decide si es apto para
; evaluacion especializada. Condiciones: profundidad acotada (32), ningun
; tipo dinamico (evaluate / load_* ) y todos los T conocidos.
; Escape: @aot fuerza, @noaot fuerza interpretacion.
; Fallback: si un guard falla, se cae a eval(hold(f)) del intérprete.
;
; La via rapida llama directo al reductor (g->T(f)) sin el trampolin step,
; preservando hold/drop. Es la semilla para la generacion de IR especializado.

@QI = external global ptr

declare ptr  @eval(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)

declare ptr @type_evaluate(ptr)
declare ptr @type_load_argv(ptr)
declare ptr @type_load_basic(ptr)
declare ptr @type_load_bn(ptr)
declare ptr @type_load_buf(ptr)
declare ptr @type_load_cmp(ptr)
declare ptr @type_load_crypto(ptr)
declare ptr @type_load_extend(ptr)
declare ptr @type_load_fexl(ptr)
declare ptr @type_load_file(ptr)
declare ptr @type_load_hex(ptr)
declare ptr @type_load_istr(ptr)
declare ptr @type_load_limit(ptr)
declare ptr @type_load_main(ptr)
declare ptr @type_load_math(ptr)
declare ptr @type_load_num(ptr)
declare ptr @type_load_output(ptr)
declare ptr @type_load_parse(ptr)
declare ptr @type_load_rand(ptr)
declare ptr @type_load_record(ptr)
declare ptr @type_load_regex(ptr)
declare ptr @type_load_script(ptr)
declare ptr @type_load_run(ptr)
declare ptr @type_load_signal(ptr)
declare ptr @type_load_str(ptr)
declare ptr @type_load_stream(ptr)
declare ptr @type_load_sym(ptr)
declare ptr @type_load_test(ptr)
declare ptr @type_load_time(ptr)
declare ptr @type_load_tuple(ptr)
declare ptr @type_load_var(ptr)

@.aot_depth = private constant [5 x i8] c"@aot\00"
@.noaot_depth = private constant [7 x i8] c"@noaot\00"

; ---- detector automatico -------------------------------------------------
; Devuelve 1 si el arbol es apto, 0 si contiene algo dinamico/desconocido.
define private i32 @aot_probe(ptr %f, i64 %depth) {
entry:
  %lim = icmp sgt i64 %depth, 32
  br i1 %lim, label %fail, label %check
check:
  %tp = getelementptr %value, ptr %f, i32 0, i32 1
  %t = load ptr, ptr %tp
  %null = icmp eq ptr %t, null
  br i1 %null, label %recurse, label %known
known:
  ; tipos dinamicos -> no apto
  %d0 = icmp eq ptr %t, @type_evaluate
  %d1 = icmp eq ptr %t, @type_load_main
  %dyn = or i1 %d0, %d1
  br i1 %dyn, label %fail, label %recurse
recurse:
  %lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %lp
  %hasL = icmp ne ptr %L, null
  br i1 %hasL, label %checkdata, label %okay
checkdata:
  ; Si f->L->N == 0 es un data value: su R es un puntero opaco
  ; (string/FILE*/bn), no un value. No recorrer.
  %LNp = getelementptr %value, ptr %L, i32 0, i32 0
  %LN = load i64, ptr %LNp
  %isdata = icmp eq i64 %LN, 0
  br i1 %isdata, label %okay, label %dol
dol:
  %d1v = add i64 %depth, 1
  %okL = call i32 @aot_probe(ptr %L, i64 %d1v)
  %yes = icmp eq i32 %okL, 1
  br i1 %yes, label %maybeR, label %fail
maybeR:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %R = load ptr, ptr %rp
  %hasR = icmp ne ptr %R, null
  br i1 %hasR, label %dor, label %okay
dor:
  %d1v2 = add i64 %depth, 1
  %okR = call i32 @aot_probe(ptr %R, i64 %d1v2)
  %yes2 = icmp eq i32 %okR, 1
  br i1 %yes2, label %okay, label %fail
okay:
  ret i32 1
fail:
  ret i32 0
}

; ---- via rapida ----------------------------------------------------------
; f = A(g, x) con g reductor puro conocido. Llama g(f) directo.
define private ptr @aot_step(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %g = load ptr, ptr %Lp
  %Tptr = getelementptr %value, ptr %g, i32 0, i32 1
  %T = load ptr, ptr %Tptr
  %null = icmp eq ptr %T, null
  br i1 %null, label %fallback, label %direct
direct:
  ; Igual que step(): el reductor no suelta f, lo hacemos aca.
  %r = call ptr %T(ptr %f)
  call void @drop(ptr %f)
  ret ptr %r
fallback:
  ; f ya tiene el hold que hizo aot_eval; eval lo consume via step().
  %r2 = call ptr @eval(ptr %f)
  ret ptr %r2
}

; ---- entrada publica -----------------------------------------------------
; (aot_eval x) intenta la via rapida; si el detector dice no, interpreta.
define ptr @aot_eval(ptr %f) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %ok = call i32 @aot_probe(ptr %rv, i64 0)
  %eligible = icmp eq i32 %ok, 1
  br i1 %eligible, label %fast, label %interp
fast:
  %h = call ptr @hold(ptr %rv)
  %r = call ptr @aot_step(ptr %h)
  ret ptr %r
interp:
  %h2 = call ptr @hold(ptr %rv)
  %r2 = call ptr @eval(ptr %h2)
  ret ptr %r2
}
