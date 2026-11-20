; fexl/standalone_main.ll — entry point para el standalone fexlswi.
; El binario fusionado usa dispatch.c (raiz) en vez de este main.

declare i32 @fexl_main(i32, ptr)

define i32 @main(i32 %argc, ptr %argv) {
entry:
  %r = call i32 @fexl_main(i32 %argc, ptr %argv)
  ret i32 %r
}
