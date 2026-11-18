; core/macros.ll — capa de orquestación específica de macros. Sabe qué es
; un .def, qué es macros/.build/, y coordina fsio (I/O genérico) +
; regex_abregex (parse/resolve) + regex_compiler/rxprog_cache (compile/cache)
; sin que ninguna de esas capas de abajo sepa nada de "macro".
;
; Modelo de dep_hash: "grueso" — un solo hash global combinando TODOS los
; .def de macros/, no uno por macro. Se persiste en macros/.build/.dep_hash
; y sobrevive entre sesiones (abrir/cerrar sin editar macros no recalcula
; nada). Se recalcula solo cuando gui/ dispara el evento "macro cambió"
; (llamando abregex_recompute_dep_hash) — el CUÁNDO es responsabilidad de
; gui/, event-driven; esta capa solo expone las funciones puras.

declare ptr @malloc(i64)
declare void @free(ptr)

declare i32  @fsio_read_file(ptr, ptr, ptr)
declare i32  @fsio_write_file(ptr, ptr, i64)
declare void @fsio_free_buffer(ptr)
declare i32  @fsio_list_dir(ptr, ptr, ptr)
declare void @fsio_free_dir_list(ptr, i64)
declare i32  @fsio_ensure_dir(ptr)
declare i32  @fsio_delete_file(ptr)
declare ptr  @fsio_path_join(ptr, ptr)
declare void @fsio_filter_by_ext(ptr, i64, ptr, ptr, ptr)

declare i64  @fnv1a_hash(ptr, i64)
declare ptr  @rxprog_deserialize(ptr, i64, i64)
declare i32  @rxprog_serialize(ptr, i64, i64, ptr)

declare ptr  @symtab_create()
declare void @symtab_destroy(ptr)
declare i32  @abregex_parse_defs(ptr, i64, ptr)
declare ptr  @abregex_resolve(ptr, ptr, i64)
declare ptr  @rx_compile(ptr)
declare void @rx_ast_destroy(ptr)

; --- dep_hash global ---

; recorre %macros_dir (ej. "macros"), hashea el contenido de cada .def
; encontrado, combina todo con XOR (conmutativo — no depende del orden que
; devuelva fsio_list_dir). Devuelve el hash combinado, o 0 si el dir está
; vacío/no se pudo listar.
define i64 @abregex_compute_dep_hash(ptr %macros_dir) {
entry:
  %names_slot = alloca ptr
  %count_slot = alloca i64
  %list_ok = call i32 @fsio_list_dir(ptr %macros_dir, ptr %names_slot, ptr %count_slot)
  %list_ok_b = icmp eq i32 %list_ok, 1
  br i1 %list_ok_b, label %filter, label %ret_zero

filter:
  %names = load ptr, ptr %names_slot
  %count = load i64, ptr %count_slot
  %def_ext = getelementptr [5 x i8], ptr @str_dot_def, i32 0, i32 0
  %fnames_slot = alloca ptr
  %fcount_slot = alloca i64
  call void @fsio_filter_by_ext(ptr %names, i64 %count, ptr %def_ext, ptr %fnames_slot, ptr %fcount_slot)
  %fnames = load ptr, ptr %fnames_slot
  %fcount = load i64, ptr %fcount_slot
  br label %hashloop

hashloop:
  %i = phi i64 [ 0, %filter ], [ %i_next, %next ]
  %acc = phi i64 [ 0, %filter ], [ %acc_next, %next ]
  %done = icmp uge i64 %i, %fcount
  br i1 %done, label %finish, label %hash_one

hash_one:
  %slot = getelementptr ptr, ptr %fnames, i64 %i
  %fname = load ptr, ptr %slot
  %full_path = call ptr @fsio_path_join(ptr %macros_dir, ptr %fname)
  %data_slot = alloca ptr
  %len_slot = alloca i64
  %read_ok = call i32 @fsio_read_file(ptr %full_path, ptr %data_slot, ptr %len_slot)
  call void @free(ptr %full_path)
  %read_ok_b = icmp eq i32 %read_ok, 1
  br i1 %read_ok_b, label %hash_it, label %next

hash_it:
  %data = load ptr, ptr %data_slot
  %len = load i64, ptr %len_slot
  %h = call i64 @fnv1a_hash(ptr %data, i64 %len)
  call void @fsio_free_buffer(ptr %data)
  br label %next

next:
  %h_or_zero = phi i64 [ %h, %hash_it ], [ 0, %hash_one ]
  %acc_next = xor i64 %acc, %h_or_zero
  %i_next = add i64 %i, 1
  br label %hashloop

finish:
  call void @free(ptr %fnames)
  call void @fsio_free_dir_list(ptr %names, i64 %count)
  ret i64 %acc

ret_zero:
  ret i64 0
}

@str_dot_def = private constant [5 x i8] c".def\00"

; --- persistencia del dep_hash en macros/.build/.dep_hash ---

; lee el hash persistido. out_hash recibe el valor. Devuelve 1 si había uno
; guardado y se leyó, 0 si no existe / archivo corrupto (< 8 bytes).
define i32 @abregex_read_dep_hash(ptr %hashfile_path, ptr %out_hash) {
entry:
  %data_slot = alloca ptr
  %len_slot = alloca i64
  %ok = call i32 @fsio_read_file(ptr %hashfile_path, ptr %data_slot, ptr %len_slot)
  %ok_b = icmp eq i32 %ok, 1
  br i1 %ok_b, label %check_len, label %fail

check_len:
  %data = load ptr, ptr %data_slot
  %len = load i64, ptr %len_slot
  %len_ok = icmp uge i64 %len, 8
  br i1 %len_ok, label %read_val, label %fail_free

read_val:
  %val = load i64, ptr %data
  store i64 %val, ptr %out_hash
  call void @fsio_free_buffer(ptr %data)
  ret i32 1

fail_free:
  call void @fsio_free_buffer(ptr %data)
  ret i32 0

fail:
  ret i32 0
}

; escribe %hash a %hashfile_path (8 bytes crudos). Devuelve 1 ok, 0 fail.
define i32 @abregex_write_dep_hash(ptr %hashfile_path, i64 %hash) {
entry:
  %slot = alloca i64
  store i64 %hash, ptr %slot
  %ok = call i32 @fsio_write_file(ptr %hashfile_path, ptr %slot, i64 8)
  ret i32 %ok
}

; evento "macro cambió": recalcula el dep_hash global y lo persiste.
; Llamar desde gui/ después de guardar una edición vía la consola de
; macros en vivo (o al agregar/quitar un .def). No recompila ni recarga
; ningún RxProgram por sí sola — solo actualiza el valor de referencia;
; el próximo use_macro_load de cada macro es quien nota el mismatch de
; hash y recompila esa macro puntual.
define i64 @abregex_recompute_dep_hash(ptr %macros_dir, ptr %hashfile_path) {
entry:
  %hash = call i64 @abregex_compute_dep_hash(ptr %macros_dir)
  %write_ok = call i32 @abregex_write_dep_hash(ptr %hashfile_path, i64 %hash)
  ret i64 %hash
}

; boot/apertura: usa el hash persistido si existe, si no lo calcula y lo
; guarda (primera vez / fue borrado). Es la función que gui/ llama UNA vez
; al abrir, no en cada use_macro_load.
define i64 @abregex_load_or_init_dep_hash(ptr %macros_dir, ptr %hashfile_path) {
entry:
  %hash_slot = alloca i64
  %had_one = call i32 @abregex_read_dep_hash(ptr %hashfile_path, ptr %hash_slot)
  %had_one_b = icmp eq i32 %had_one, 1
  br i1 %had_one_b, label %use_existing, label %compute_new

use_existing:
  %existing = load i64, ptr %hash_slot
  ret i64 %existing

compute_new:
  %fresh = call i64 @abregex_recompute_dep_hash(ptr %macros_dir, ptr %hashfile_path)
  ret i64 %fresh
}

; comando explícito "limpiar cache de macros": borra .dep_hash. Los .rxc
; individuales NO se borran acá (quedan huérfanos en disco pero inofensivos
; — al no existir ya un dep_hash de referencia coherente, el próximo
; use_macro_load con el hash recién calculado no va a matchear contra
; ningún .rxc viejo, así que se recompilan solos igual, sin necesidad de
; borrar cada .rxc a mano).
define i32 @abregex_clear_dep_hash(ptr %hashfile_path) {
entry:
  %ok = call i32 @fsio_delete_file(ptr %hashfile_path)
  ret i32 %ok
}

; --- cache-or-compile por macro puntual ---

; dado un nombre de macro y los paths a su .def y su .rxc, devuelve
; RxProgram*: desde cache si el self_hash del .def matchea Y el dep_hash
; pasado coincide con el guardado en el .rxc, o compila fresco y cachea.
; %global_dep_hash: el valor devuelto por abregex_load_or_init_dep_hash al
; boot (gui/ lo guarda y lo pasa en cada llamada — no se relee del disco
; acá, para no pagar I/O extra por cada macro pedida).
define ptr @use_macro_load(ptr %def_path, ptr %rxc_path, ptr %name, i64 %name_len, i64 %global_dep_hash) {
entry:
  %data_slot = alloca ptr
  %len_slot = alloca i64
  %read_ok = call i32 @fsio_read_file(ptr %def_path, ptr %data_slot, ptr %len_slot)
  %read_ok_b = icmp eq i32 %read_ok, 1
  br i1 %read_ok_b, label %hash_it, label %fail

hash_it:
  %data = load ptr, ptr %data_slot
  %len = load i64, ptr %len_slot
  %self_hash = call i64 @fnv1a_hash(ptr %data, i64 %len)

  %cached = call ptr @rxprog_deserialize(ptr %rxc_path, i64 %self_hash, i64 %global_dep_hash)
  %cache_hit = icmp ne ptr %cached, null
  br i1 %cache_hit, label %use_cache, label %compile_fresh

use_cache:
  call void @fsio_free_buffer(ptr %data)
  ret ptr %cached

compile_fresh:
  %symtab = call ptr @symtab_create()
  %parse_ok = call i32 @abregex_parse_defs(ptr %data, i64 %len, ptr %symtab)
  %parse_ok_b = icmp eq i32 %parse_ok, 1
  br i1 %parse_ok_b, label %do_resolve, label %fail_cleanup

do_resolve:
  %resolved = call ptr @abregex_resolve(ptr %symtab, ptr %name, i64 %name_len)
  %resolved_null = icmp eq ptr %resolved, null
  br i1 %resolved_null, label %fail_cleanup, label %do_compile

do_compile:
  %prog = call ptr @rx_compile(ptr %resolved)
  call void @rx_ast_destroy(ptr %resolved)
  call void @symtab_destroy(ptr %symtab)
  %save_ok = call i32 @rxprog_serialize(ptr %prog, i64 %self_hash, i64 %global_dep_hash, ptr %rxc_path)
  call void @fsio_free_buffer(ptr %data)
  ret ptr %prog

fail_cleanup:
  call void @symtab_destroy(ptr %symtab)
  call void @fsio_free_buffer(ptr %data)
  ret ptr null

fail:
  ret ptr null
}

; version sin cache, para tests: compila un nombre desde texto .def en
; memoria y devuelve RxProgram* directo (o null si falla parse/resolve).
define ptr @abregex_compile_named(ptr %src, i64 %src_len, ptr %name, i64 %name_len) {
entry:
  %symtab = call ptr @symtab_create()
  %parse_ok = call i32 @abregex_parse_defs(ptr %src, i64 %src_len, ptr %symtab)
  %parse_ok_b = icmp eq i32 %parse_ok, 1
  br i1 %parse_ok_b, label %do_resolve, label %fail_cleanup

do_resolve:
  %resolved = call ptr @abregex_resolve(ptr %symtab, ptr %name, i64 %name_len)
  %resolved_null = icmp eq ptr %resolved, null
  br i1 %resolved_null, label %fail_cleanup, label %do_compile

do_compile:
  %prog = call ptr @rx_compile(ptr %resolved)
  call void @rx_ast_destroy(ptr %resolved)
  call void @symtab_destroy(ptr %symtab)
  ret ptr %prog

fail_cleanup:
  call void @symtab_destroy(ptr %symtab)
  ret ptr null
}
