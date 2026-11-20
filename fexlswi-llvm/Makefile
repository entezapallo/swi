# fexlswi-llvm — interprete Fexl en IR (LLVM) + C residual.
#
# Proyecto autocontenido: los ~47 modulos del nucleo viven en ./*.ll, el C que
# aun no se porto (bn, nacl, type_run, type_regex, type_script) esta en src/,
# y el motor regex en ../regex. Lo compila este Makefile, aparte de swi.
#
#   make fast       -O0 -g, sin LTO optimizado ni strip (iterar/depurar)
#   make opt        -Oz + LTO + internalize/globaldce, musl dinamico
#   make opt-full   opt + adce + flags de link agresivos (por default)
#   make selfh      -Oz + LTO sin internalize/globaldce
#   make clean      borra todos los generados
#
# Productos:
#   lib/fexlswi_lib.bc   bitcode que CONSUME swi: sin internalizar ni globaldce,
#                        con main renombrado a fexl_main.
#   lib/fexlswi.bc       fusionado del standalone (con los pases FUSE).
#   bin/fexlswi, bin/fexlswi0   ELF standalone (el sufijo 0 evita main.fxl).

FEXL_CC ?= clang --target=x86_64-linux-musl -isystem /usr/include/x86_64-linux-musl
OPT     ?= opt-21
LLLINK  ?= llvm-link-21

MODULOS := regex_parser regex_compiler regex_abregex regex_thread \
           regex_runner rx_query rx_runtime

# C residual del interprete (sin semantica de valores Fexl).
FEXL_MODS := bn nacl type_run

# Modulos IR del nucleo. value_types.ll se inyecta por concatenacion.
FEXL_IR  := value memory str parse type_num type_cmp basic type_str type_sym type_output type_record buf buf_str file file_str convert type_rand type_limit type_math type_hex type_tuple type_var type_istr type_input type_buf type_parse type_argv type_stream type_file die format report limit type_fexl type_signal type_crypto test stream base64 type_time show type_bn fexl aot sha256 sha512 crypto
IRDIR    := .
IR_TYPES := $(IRDIR)/value_types.ll
FEXL_IR_BC = $(addprefix $(OBJ)/fexl_,$(addsuffix .bc,$(FEXL_IR)))

SRC := src
OBJ := obj
LIB := lib
BIN := bin
RXDIR := ../regex
RXBUILD := $(RXDIR)/build

MUSL_LINK := -L/usr/lib/x86_64-linux-musl \
             -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1 \
             -Wl,-rpath,/usr/lib/x86_64-linux-musl

# codegen del .bc fusionado (ocurre en el link; estos flags no viven en el IR)
CG := -ffunction-sections -fdata-sections \
      -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-pic -fno-pie

# --icf=safe, no --icf=all: Fexl usa value.T como tag de tipo (puntero a
# funcion); --icf=all pliega funciones con direccion tomada y crashea el driver.
LINK := -Oz -no-pie $(CG) -fuse-ld=lld $(MUSL_LINK) -Wl,--gc-sections \
        -Wl,--icf=safe -Wl,-O2 -Wl,--build-id=none -Wl,-z,noseparate-code -s
FULL_LINK := $(LINK) -Wl,-z,norelro -Wl,--hash-style=gnu -Wl,--no-rosegment

# agrega nounwind/optsize/minsize a los define del IR (clang -Oz lo hace en C)
ATTR_FILTER = sed -E '/^define /{/\)[^)]*([ ](section|align|gc|prefix|prologue|personality|comdat)[ ]|!)[^)]*\{$$/b;s/ \{$$/ nounwind optsize minsize {/}'

# archivos C viejos compilados con headers glibc; -include lo garantiza en musl
EXTRA_INC := -include fcntl.h

COPT := -Oz -ffunction-sections -fdata-sections -fvisibility=hidden \
        -fno-pic -fno-pie \
        -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-ident \
        -fno-stack-protector -Wall -Werror -Wunused-parameter \
        -Wdeclaration-after-statement -Dtimelocal=mktime -I src $(EXTRA_INC)

LDFLAGS ?= $(LINK)
FUSE    ?= verify
RXFILT  ?= cat
RXPASS  ?= verify
FAST_COPT := -O0 -g -fno-stack-protector -Dtimelocal=mktime -I src $(EXTRA_INC)

FEXL_CORE_BC := $(addprefix $(OBJ)/,$(addsuffix .bc,$(FEXL_MODS)))
RX_BC := $(addprefix $(RXBUILD)/,$(addsuffix .bc,$(MODULOS)))

.PHONY: all fast opt opt-full selfh clean
all: opt-full

# --- perfiles: un solo lugar con los flags ---
fast: LDFLAGS := -fuse-ld=lld $(MUSL_LINK)
fast: COPT := $(FAST_COPT)
fast: FUSE := verify
fast: RXFILT := cat
fast: RXPASS := verify

opt: FUSE := internalize<preserve-gv=main>,globaldce,default<Oz>
opt: RXFILT := $(ATTR_FILTER)
opt: RXPASS := verify,default<Oz>

opt-full: LDFLAGS := $(FULL_LINK)
# adce en vez de segunda ronda de default<Oz> (redundante). Segmentos agresivos
# (-z norelro, --no-rosegment, --hash-style=gnu) siguen activos por default.
opt-full: FUSE := internalize<preserve-gv=main>,globaldce,default<Oz>,adce,globaldce
opt-full: RXFILT := $(ATTR_FILTER)
opt-full: RXPASS := verify,default<Oz>

selfh: FUSE := default<Oz>
selfh: RXFILT := $(ATTR_FILTER)
selfh: RXPASS := verify,default<Oz>

fast opt opt-full selfh: $(BIN)/fexlswi $(BIN)/fexlswi0 $(LIB)/fexlswi_lib.bc

# --- directorios ---
$(OBJ) $(LIB) $(BIN) $(RXBUILD):
	mkdir -p $@

# --- C -> bitcode ---
$(OBJ)/%.bc: $(SRC)/%.c | $(OBJ)
	$(FEXL_CC) -c -emit-llvm $(COPT) $< -o $@

# main del standalone (el fusionado usa dispatch.c del Makefile raiz).
$(OBJ)/fexl_main_standalone.bc: $(IRDIR)/standalone_main.ll | $(OBJ)
	$(OPT) -mtriple=x86_64-linux-musl -passes='$(RXPASS)' $< -o $@

# --- 7 modulos IR de regex: rx_types.ll se inyecta por concatenacion ---
$(RXBUILD)/%.bc: $(RXDIR)/%.ll $(RXDIR)/rx_types.ll | $(RXBUILD)
	{ cat $(RXDIR)/rx_types.ll; $(RXFILT) $<; } \
	| $(OPT) -mtriple=x86_64-linux-musl -passes='$(RXPASS)' - -o $@

# --- nucleo Fexl en IR: value_types.ll se inyecta por concatenacion ---
$(OBJ)/fexl_%.bc: $(IRDIR)/%.ll $(IR_TYPES) | $(OBJ)
	{ cat $(IR_TYPES); $(RXFILT) $<; } \
	| $(OPT) -mtriple=x86_64-linux-musl -passes='$(RXPASS)' - -o $@

# --- bitcode fusionado para swi (un solo binario): fexl.ll da fexl_main ---
$(LIB)/fexlswi_lib.bc: $(FEXL_CORE_BC) $(FEXL_IR_BC) \
                       $(OBJ)/type_regex.bc $(OBJ)/type_script.bc $(RX_BC) | $(LIB)
	$(LLLINK) $(FEXL_CORE_BC) $(FEXL_IR_BC) \
		$(OBJ)/type_regex.bc $(OBJ)/type_script.bc $(RX_BC) -o $@

# --- bitcode fusionado del standalone: main propio + pases FUSE ---
$(LIB)/fexlswi.bc: $(FEXL_CORE_BC) $(FEXL_IR_BC) $(OBJ)/fexl_main_standalone.bc \
                   $(OBJ)/type_regex.bc $(OBJ)/type_script.bc $(RX_BC) | $(LIB)
	$(LLLINK) $(FEXL_CORE_BC) $(FEXL_IR_BC) $(OBJ)/fexl_main_standalone.bc \
		$(OBJ)/type_regex.bc $(OBJ)/type_script.bc $(RX_BC) -o $@
	@if [ "$(FUSE)" != "verify" ]; then \
		$(OPT) -mtriple=x86_64-linux-musl -passes='$(FUSE)' $@ -o $@.tmp && \
		mv $@.tmp $@; \
	fi

# --- binarios finales ---
$(BIN)/fexlswi: $(LIB)/fexlswi.bc | $(BIN)
	$(FEXL_CC) $(LDFLAGS) $< -lm -o $@

# copia real, no symlink: el sufijo 0 evita cargar main.fxl.
$(BIN)/fexlswi0: $(BIN)/fexlswi
	cp $< $@

clean:
	rm -rf $(BIN) $(LIB) $(OBJ) $(RXBUILD) build
	@echo "fexlswi-llvm limpio"
