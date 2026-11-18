; fsio/fsio_ensure_dir.ll — crea un directorio si no existe. No recursivo
; (no crea padres intermedios — mismo alcance que mkdir(2), no mkdir -p).

declare i32 @mkdir(ptr, i32)
declare ptr @__errno_location()

; devuelve 1 si el dir existe al terminar (ya existía o se creó ahora), 0 si
; el mkdir falló por otra razón (permisos, padre inexistente, etc.)
define i32 @fsio_ensure_dir(ptr %path) {
entry:
  %rc = call i32 @mkdir(ptr %path, i32 493)   ; 0755 octal = 493 decimal
  %ok = icmp eq i32 %rc, 0
  br i1 %ok, label %success, label %check_exists

check_exists:
  %errno_ptr = call ptr @__errno_location()
  %errno_val = load i32, ptr %errno_ptr
  %is_eexist = icmp eq i32 %errno_val, 17     ; EEXIST
  br i1 %is_eexist, label %success, label %fail

success:
  ret i32 1
fail:
  ret i32 0
}
