# fexlswi — Fexl + extension regex + motor jotter.
#
#   make opt     dinamico musl, -Oz + LTO optimizado al minimo
#   make selfh   dinamico musl, -Oz + LTO, build desde fuentes sin pases extra
#   make clean   borra bin/, lib/, obj/, regex/build/ y build/
#
# Unicos binarios finales: fexlswi y fexlswi0 (mismo ELF, el sufijo 0
# evita cargar main.fxl). Ambos perfiles dejan sus copias en build/<perfil>/bin
# y refrescan bin/ (que es lo que usa el proyecto hermano ~/swi).
#
# Ajustes de tamano (ambos perfiles):
#   - musl dinamico real: -L al dir de musl + dynamic-linker + rpath (mismo
#     esquema que ~/swi). Sin -L, clang con --target=...-musl puede terminar
#     enlazando glibc (se vio en el binario: __gconv, _nl_load_domain, stapsdt).
#   - C sin unwind tables ni stack protector, con function/data-sections.
#   - lld con --gc-sections, --icf=all, -O2, sin build-id, strip.
#   - los .ll de regex reciben nounwind/optsize/minsize antes de opt (clang -Oz
#     los pone solo en C; los .ll no los traen).

FEXL_CC ?= clang --target=x86_64-linux-musl -isystem /usr/include/x86_64-linux-musl
OPT     ?= opt-21

MODULOS := regex_parser regex_compiler regex_abregex regex_thread \
           regex_runner rx_query rx_runtime

# musl dinamico, tamano minimo: mismo esquema que ~/swi
MUSL_LINK := -L/usr/lib/x86_64-linux-musl \
             -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1 \
             -Wl,-rpath,/usr/lib/x86_64-linux-musl
LINK := -Oz -fuse-ld=lld $(MUSL_LINK) -Wl,--gc-sections -Wl,--icf=all \
        -Wl,-O2 -Wl,--build-id=none -s
# flags de compilacion C: sin unwind tables ni stack protector
COPT := -Oz -ffunction-sections -fdata-sections \
        -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-stack-protector \
        -Dtimelocal=mktime
        
.PHONY: all opt selfh clean

all: opt selfh

# compilar los 7 modulos IR, todos con target musl y tamano minimo.
# El sed agrega nounwind optsize minsize a cada `define` (se salta las que
# llevan section/align/gc/prefix/prologue/personality/comdat o metadata tras
# la lista de argumentos).
define REGLAS_REGEX
	mkdir -p regex/build
	@for m in $(MODULOS); do \
		sed -E '/^define /{/\)[^)]*([ ](section|align|gc|prefix|prologue|personality|comdat)[ ]|!)[^)]*\{$$/b;s/ \{$$/ nounwind optsize minsize {/}' regex/$$m.ll \
		| $(OPT) -mtriple=x86_64-linux-musl -passes='verify,default<Oz>' - -o regex/build/$$m.bc || exit 1; \
	done
endef

opt:
	cd src && ./build clean
	rm -rf build/opt
	$(REGLAS_REGEX)
	cd src && \
		FEXL_CC="$(FEXL_CC)" FEXL_COPT='$(COPT)' \
		FEXL_LDFLAGS='$(LINK)' \
		FEXL_FUSE_OPT='default<Oz>,globaldce' \
		./build && \
		FEXL_CC="$(FEXL_CC)" FEXL_COPT='$(COPT)' \
		FEXL_LDFLAGS='$(LINK)' \
		FEXL_FUSE_OPT='default<Oz>,globaldce' \
		./build_regex
	mkdir -p build/opt/bin build/opt/lib
	cp -a bin/. build/opt/bin/
	cp lib/fexlswi.bc build/opt/lib/
	@echo "listo: build/opt/bin/fexlswi0 (dinamico musl, -Oz + LTO)"

selfh:
	cd src && ./build clean
	rm -rf build/selfh
	$(REGLAS_REGEX)
	cd src && \
		FEXL_CC="$(FEXL_CC)" FEXL_COPT='$(COPT)' \
		FEXL_LDFLAGS='$(LINK)' \
		FEXL_FUSE_OPT='default<Oz>' \
		./build && \
		FEXL_CC="$(FEXL_CC)" FEXL_COPT='$(COPT)' \
		FEXL_LDFLAGS='$(LINK)' \
		FEXL_FUSE_OPT='default<Oz>' \
		./build_regex
	mkdir -p build/selfh/bin build/selfh/lib
	cp -a bin/. build/selfh/bin/
	cp lib/fexlswi.bc build/selfh/lib/
	@echo "listo: build/selfh/bin/fexlswi0 (dinamico musl, -Oz + LTO)"

clean:
	cd src && ./build clean
	rm -rf build bin lib obj regex/build
	@echo "limpio"
