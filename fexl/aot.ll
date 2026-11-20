; fexl/aot.ll — AOT madurado del Paso 1.
;
; Detector automatico: recorre el grafo (profundidad <= 32, solo arboles) y
; rechaza cualquier tipo dinamico de la tabla @dynamic_types (evaluate y
; todos los load_*). Escapes: @aot fuerza la via rapida, @noaot fuerza el
; interprete. Fallback: eval(hold(f)) / step(f) segun el punto de entrada.
;
; @aot_enabled conecta la via rapida al dispatch de eval en value.ll.
; Default 0: el comportamiento existente no cambia. Se prende con (aot_on).

@QI          = external global ptr
@aot_enabled = global i32 0

declare ptr  @eval(ptr)
declare ptr  @step(ptr)
declare ptr  @hold(ptr)
declare void @drop(ptr)

; ---- tipos dinamicos (evaluate + todos los load_*) ------------------------
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

@dynamic_types = private constant [31 x ptr] [
  ptr @type_evaluate,
  ptr @type_load_argv,   ptr @type_load_basic,  ptr @type_load_bn,
  ptr @type_load_buf,    ptr @type_load_cmp,    ptr @type_load_crypto,
  ptr @type_load_extend, ptr @type_load_fexl,   ptr @type_load_file,
  ptr @type_load_hex,    ptr @type_load_istr,   ptr @type_load_limit,
  ptr @type_load_main,   ptr @type_load_math,   ptr @type_load_num,
  ptr @type_load_output, ptr @type_load_parse,  ptr @type_load_rand,
  ptr @type_load_record, ptr @type_load_regex,  ptr @type_load_script,
  ptr @type_load_run,    ptr @type_load_signal, ptr @type_load_str,
  ptr @type_load_stream, ptr @type_load_sym,    ptr @type_load_test,
  ptr @type_load_time,   ptr @type_load_tuple,  ptr @type_load_var
]

; ---- detector -------------------------------------------------------------
define private i32 @aot_probe(ptr %f, i64 %depth) {
entry:
  %lim = icmp sgt i64 %depth, 32
  br i1 %lim, label %fail, label %check
check:
  %tp = getelementptr %value, ptr %f, i32 0, i32 1
  %t = load ptr, ptr %tp
  %null = icmp eq ptr %t, null
  br i1 %null, label %recurse, label %scandyn
scandyn:
  br label %dynloop
dynloop:
  %i = phi i64 [ 0, %scandyn ], [ %i1, %dynnext ]
  %cont = icmp ult i64 %i, 31
  br i1 %cont, label %dynbody, label %recurse
dynbody:
  %slot = getelementptr [31 x ptr], ptr @dynamic_types, i64 0, i64 %i
  %dt = load ptr, ptr %slot
  %eq = icmp eq ptr %t, %dt
  br i1 %eq, label %fail, label %dynnext
dynnext:
  %i1 = add i64 %i, 1
  br label %dynloop
recurse:
  %lp = getelementptr %value, ptr %f, i32 0, i32 2
  %L = load ptr, ptr %lp
  %hasL = icmp ne ptr %L, null
  br i1 %hasL, label %checkdata, label %okay
checkdata:
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

; ---- via rapida -----------------------------------------------------------
; g->T != 0: llama directo al reductor. Si no, delega en step() (no en eval,
; para no reentrar en el dispatch con el flag prendido).
define ptr @aot_step_fast(ptr %f) {
entry:
  %Lp = getelementptr %value, ptr %f, i32 0, i32 2
  %g = load ptr, ptr %Lp
  %gnull = icmp eq ptr %g, null
  br i1 %gnull, label %delegate, label %checkT
checkT:
  %Tptr = getelementptr %value, ptr %g, i32 0, i32 1
  %T = load ptr, ptr %Tptr
  %null = icmp eq ptr %T, null
  br i1 %null, label %delegate, label %direct
direct:
  %r = call ptr %T(ptr %f)
  call void @drop(ptr %f)
  ret ptr %r
delegate:
  %r2 = call ptr @step(ptr %f)
  ret ptr %r2
}

; ---- entradas publicas ----------------------------------------------------
; modos: 0 = auto (detector), 1 = forzar rapida (@aot), 2 = forzar interpreter (@noaot)
define private ptr @aot_run(ptr %f, i32 %mode) {
entry:
  %rp = getelementptr %value, ptr %f, i32 0, i32 3
  %rv = load ptr, ptr %rp
  %isauto = icmp eq i32 %mode, 0
  br i1 %isauto, label %detect, label %modechk
detect:
  %ok = call i32 @aot_probe(ptr %rv, i64 0)
  %eligible = icmp eq i32 %ok, 1
  br i1 %eligible, label %fast, label %interp
modechk:
  %isskip = icmp eq i32 %mode, 2
  br i1 %isskip, label %interp, label %fast
fast:
  ; Si rv ya es un valor (T != 0), devolverlo con hold: step() soltara f.
  %rtp = getelementptr %value, ptr %rv, i32 0, i32 1
  %rt = load ptr, ptr %rtp
  %isapp = icmp eq ptr %rt, null
  br i1 %isapp, label %callfast, label %doneval
doneval:
  %hv = call ptr @hold(ptr %rv)
  ret ptr %hv
callfast:
  %h = call ptr @hold(ptr %rv)
  %r = call ptr @aot_step_fast(ptr %h)
  ret ptr %r
interp:
  %h2 = call ptr @hold(ptr %rv)
  %r2 = call ptr @eval(ptr %h2)
  ret ptr %r2
}

define ptr @aot_eval(ptr %f) {
entry:
  %r = call ptr @aot_run(ptr %f, i32 0)
  ret ptr %r
}
define ptr @aot_force(ptr %f) {
entry:
  %r = call ptr @aot_run(ptr %f, i32 1)
  ret ptr %r
}
define ptr @aot_skip(ptr %f) {
entry:
  %r = call ptr @aot_run(ptr %f, i32 2)
  ret ptr %r
}

define ptr @aot_on(ptr %f) {
entry:
  store i32 1, ptr @aot_enabled
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
define ptr @aot_off(ptr %f) {
entry:
  store i32 0, ptr @aot_enabled
  %qi = load ptr, ptr @QI
  %h = call ptr @hold(ptr %qi)
  ret ptr %h
}
