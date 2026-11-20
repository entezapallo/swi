# Makefile unificado — swi + fexlswi (repo anidado), UN SOLO BINARIO en los
# perfiles de tamano.
#
#   make fast       swi -O0 -g; fexlswi aparte (proceso hijo, como antes)
#   make opt        UN binario: swi + interprete Fexl fusionados (LTO, -Oz)
#   make opt-full   opt + segunda ronda de Oz + flags de link agresivos
#   make selfh      como opt pero sin globaldce en el fusionado
#   make clean all  limpia ambos proyectos y no compila nada
#   make install    empaqueta build/ con un binario y una carpeta
#
# Un solo binario (perfiles LTO):
#   - El interprete entra como bitcode (fexlswi/lib/fexlswi_lib.bc, que
#     fexlswi/Makefile debe generar SIN internalizar y con main -> fexl_main).
#   - tui/main.c se compila con -Dmain=swi_main y un dispatch.c generado aca
#     decide por basename(argv[0]): "fexl*" -> fexl_main, otro -> swi_main.
#   - fexlswi0 es un symlink a swi (build/fexlswi/bin/fexlswi0 -> ../../swi).
#     SWI_FEXL_BIN apunta a ese symlink; el hijo hereda argv[0]=ese path.
#   - El motor regex viene dentro de fexlswi_lib.bc: no se duplica aqui.
#
# Los .o por modulo (arneses de test) siguen en PIC y sin filtros: solo el
# camino .bc/LTO recibe nounwind/optsize/minsize y -no-pie.

LLVM_PREFIX ?=
FEXL_CC ?= clang --target=x86_64-linux-musl -isystem /usr/include/x86_64-linux-musl
OPT     ?= opt-21
CLANG   := $(LLVM_PREFIX)clang-21 --target=x86_64-linux-musl
LLC     := $(LLVM_PREFIX)llc-21
LLLINK  := $(LLVM_PREFIX)llvm-link-21
LLSTRIP := $(LLVM_PREFIX)llvm-strip-21
# --icf=safe, no --icf=all: Fexl guarda punteros a funcion en value.T y los
# compara como tag de tipo; --icf=all los pliega y el driver crashea.
LDFLAG_LTO := -fuse-ld=lld-21 -Wl,--icf=safe

# Los .ll no declaran target datalayout: sin -mtriple la ABI se rompe.
OPT_TRIPLE := -mtriple=x86_64-linux-musl

MUSL_INC  := -isystem /usr/include/x86_64-linux-musl
MUSL_LINK := -L/usr/lib/x86_64-linux-musl \
             -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1 \
             -Wl,-rpath,/usr/lib/x86_64-linux-musl
TEST_LDFLAGS := $(MUSL_LINK) -lm

UI_SCRIPT ?= ui.fxl
UI_SCRIPT_DEF = -DSWI_UI_SCRIPT="\"$(abspath $(UI_SCRIPT))\""

CFLAGS ?= -std=c11 -Wall -Wextra -Wpedantic
CFLAGS += $(MUSL_INC)

# agrega nounwind/optsize/minsize a los define del IR (clang -Oz lo hace en C).
# Se salta los define con section/align/gc/prefix/prologue/personality/comdat
# o metadata tras la lista de argumentos; verify falla fuerte si algo queda mal.
ATTR_FILTER = sed -E '/^define /{/\)[^)]*([ ](section|align|gc|prefix|prologue|personality|comdat)[ ]|!)[^)]*\{$$/b;s/ \{$$/ nounwind optsize minsize {/}'

# fexlswi tiene su propio Makefile: los perfiles y flags viven en fexlswi/Makefile.
# Aca solo se delega; no se duplican reglas de build ni de modulos regex.

# --- swi: perfiles (BUILD cambiado segun MODE) ---
ifneq ($(filter opt selfh opt-full,$(MODE)),)
BUILD      := build/$(MODE)
OPT_PASS   := -passes='verify,default<Oz>'
ifeq ($(MODE),opt-full)
OPT_LTO    := -passes='verify,internalize<preserve-gv=main>,globaldce,default<Oz>,globaldce,default<Oz>,verify'
else ifeq ($(MODE),opt)
OPT_LTO    := -passes='verify,internalize<preserve-gv=main>,globaldce,default<Oz>,verify'
else
OPT_LTO    := -passes='verify,internalize<preserve-gv=main>,default<Oz>,verify'
endif
LLC_OPTS   := -O2 -relocation-model=pic
# fusionado: ejecutable no-PIE, sin PIC, una seccion por funcion/dato
LLC_LTO    := -O2 -relocation-model=static -function-sections -data-sections
CFLAGS     += -Oz -DNDEBUG -ffunction-sections -fdata-sections
# solo el camino LTO (.bc) va sin PIC; CFLAGS (los .o de los tests, que
# linkean PIE) NO lleva -fno-pic
CBCFLAGS   := -Oz -DNDEBUG -ffunction-sections -fdata-sections -emit-llvm \
              -fno-pic -fno-pie -fno-unwind-tables -fno-asynchronous-unwind-tables \
              -fno-stack-protector -fno-ident $(MUSL_INC)
LDFLAGS    := -Oz -no-pie $(LDFLAG_LTO) $(MUSL_LINK) -Wl,--gc-sections -Wl,--strip-all \
              -Wl,--build-id=none -Wl,-z,noseparate-code
ifeq ($(MODE),opt-full)
LDFLAGS    += -Wl,-z,norelro -Wl,--hash-style=gnu -Wl,--no-rosegment
endif
LTO        := 1
FEXL       ?= build/fexlswi/bin/fexlswi0
else
BUILD      := build
OPT_PASS   := -passes=verify
LLC_OPTS   := -O0 -relocation-model=pic
CFLAGS     += -O0 -g $(MUSL_LINK)
LDFLAGS    := $(MUSL_LINK)
LTO        :=
FEXL       ?= fexlswi/bin/fexlswi0
endif

# ruta ABSOLUTA al interprete (en LTO: el symlink a swi)
EVAL_DEF = -DSWI_FEXL_BIN="\"$(abspath $(FEXL))\""

CORE  := core
REGEX := regex
RX_TYPES := regex/rx_types.ll
# Modulos de regex/ que se linkean en swi (inyectan RX_TYPES al compilar).
REGEX_LL := replace format regex_parser regex_compiler regex_thread regex_runner
FSIO  := fsio
# Nucleo Fexl en IR (Paso 1). value_types.ll se inyecta por concatenacion.
FEXL_IR := value memory str parse type_num type_cmp basic type_str type_sym type_output type_record buf buf_str file file_str convert type_rand type_limit type_math type_hex type_tuple type_var type_istr type_input type_buf type_parse type_argv type_stream type_file die format report limit type_fexl type_signal type_crypto test stream base64 type_time
FEXL_IR_DIR := fexl
FEXL_IR_TYPES := fexl/value_types.ll
vpath %.ll tui $(CORE) $(REGEX) $(FSIO) $(FEXL_IR_DIR)

.PHONY: all fast opt opt-full selfh install clean \
        swi-build swi-fast swi-opt swi-only run run-opt \
        test test-opt test-selfh size size-opt size-selfh

# `make clean all`: clean limpia ambos y all no vuelve a compilar.
ifneq ($(filter clean,$(MAKECMDGOALS)),)
all:
	@echo "swi + fexlswi limpios"
else
all: opt
endif

# fexlswi se compila con su propio Makefile: aca solo se delega.
define BUILD_FEXL
	rm -rf fexlswi/build/$(P) fexlswi/bin fexlswi/lib fexlswi/obj regex/build
	$(MAKE) -C fexlswi $(P)
	mkdir -p fexlswi/build/$(P)/bin fexlswi/build/$(P)/lib
	cp -a fexlswi/bin/. fexlswi/build/$(P)/bin/
	cp fexlswi/lib/*.bc fexlswi/build/$(P)/lib/
	@echo "listo: fexlswi/build/$(P)/bin/fexlswi0"
endef

fast: P := fast
fast:
	$(BUILD_FEXL)
	$(MAKE) MODE=fast swi-build

opt: P := opt
opt:
	$(BUILD_FEXL)
	$(MAKE) MODE=opt swi-build

opt-full: P := opt-full
opt-full:
	$(BUILD_FEXL)
	$(MAKE) MODE=opt-full swi-build

selfh: P := selfh
selfh:
	$(BUILD_FEXL)
	$(MAKE) MODE=selfh swi-build

clean:
	$(MAKE) -C fexlswi clean
	rm -rf build build-opt .install-build
	@echo "swi + fexlswi limpios"

# Install: NO compila; empaqueta lo que produjo make opt / opt-full.
# build/ queda con UN binario (swi), el symlink fexlswi0 y la carpeta fexlswi/
# (Fexl busca sus librerias en ../src/lib respecto al "binario" fexlswi0).
install:
	@test -f build/opt-full/swi -o -f build/opt/swi || \
		{ echo "correr make opt u opt-full primero"; exit 1; }
	rm -rf .install-tmp
	mkdir -p .install-tmp
	@if [ -f build/opt-full/swi ]; then cp build/opt-full/swi .install-tmp/swi; \
	 else cp build/opt/swi .install-tmp/swi; fi
	cp -a fexlswi/src/lib .install-tmp/lib
	cp ui.fxl .install-tmp/ui.fxl
	rm -rf build
	mkdir -p build/fexlswi/bin build/fexlswi/src
	cp .install-tmp/swi build/swi
	ln -s ../../swi build/fexlswi/bin/fexlswi0
	cp -a .install-tmp/lib build/fexlswi/src/lib
	cp .install-tmp/ui.fxl build/fexlswi/ui.fxl
	rm -rf .install-tmp
	@echo "install listo: build/swi + build/fexlswi/ (fexlswi0 -> swi)"

swi-fast:
	$(MAKE) MODE=fast swi-build

swi-opt:
	$(MAKE) MODE=opt swi-build

swi-only: swi-build

swi-build: $(BUILD)/swi
	@ls -lh $< | awk '{print "swi: " $$5}'
ifeq ($(LTO),1)
	@mkdir -p build/fexlswi/bin
	@ln -sfn ../../swi build/fexlswi/bin/fexlswi0
	@test -e build/fexlswi/src || ln -sfn $(abspath fexlswi/src) build/fexlswi/src
endif

$(BUILD):
	mkdir -p $(BUILD)

# --- C: frontera con termbox ---
$(BUILD)/in.o: tui/in.c tui/in.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@

$(BUILD)/out.o: tui/out.c tui/out.h tui/termbox2.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@

$(BUILD)/main.o: tui/main.c tui/in.h tui/out.h tui/eval.h tui/fexl_ui.h tui/termbox2.h abi/tui_abi.h | $(BUILD)
	$(CLANG) $(CFLAGS) $(EVAL_DEF) $(UI_SCRIPT_DEF) -I. -c $< -o $@

$(BUILD)/in.bc: tui/in.c tui/in.h | $(BUILD)
	$(CLANG) $(CBCFLAGS) -I. -c $< -o $@

$(BUILD)/out.bc: tui/out.c tui/out.h tui/termbox2.h | $(BUILD)
	$(CLANG) $(CBCFLAGS) -I. -c $< -o $@

# main de swi pasa a swi_main; el main real es dispatch.c (solo en LTO)
$(BUILD)/main.bc: tui/main.c tui/in.h tui/out.h tui/eval.h tui/fexl_ui.h tui/termbox2.h abi/tui_abi.h | $(BUILD)
	$(CLANG) $(CBCFLAGS) -Dmain=swi_main $(EVAL_DEF) $(UI_SCRIPT_DEF) -I. -c $< -o $@

define DISPATCH_C
/* generado por el Makefile: un ELF, dos personalidades (swi / fexlswi) */
extern int swi_main(int, char **);
extern int fexl_main(int, char **);
int main(int argc, char **argv) {
    const char *b = "", *p;
    if (argc > 0 && argv[0]) {
        b = argv[0];
        for (p = b; *p; p++)
            if (*p == '/') b = p + 1;
    }
    if (b[0] == 'f' && b[1] == 'e' && b[2] == 'x' && b[3] == 'l')
        return fexl_main(argc, argv);
    return swi_main(argc, argv);
}
endef
export DISPATCH_C

$(BUILD)/dispatch.c: Makefile | $(BUILD)
	@printf '%s\n' "$$DISPATCH_C" > $@

$(BUILD)/dispatch.bc: $(BUILD)/dispatch.c
	$(CLANG) $(CBCFLAGS) -c $< -o $@

# --- IR: un modulo por objeto / bitcode ---
# Los modulos de regex/ reciben RX_TYPES concatenado (LLVM IR no tiene include),
# para que %RxInst/%RxProgram tengan UNA sola definicion compartida.
# .o: arneses de test, sin filtro de atributos.
$(foreach m,$(REGEX_LL),$(BUILD)/$(m).o): $(BUILD)/%.o: regex/%.ll $(RX_TYPES) | $(BUILD)
	cat $(RX_TYPES) $< | $(OPT) $(OPT_TRIPLE) $(OPT_PASS) - -o - \
	  | $(LLC) $(LLC_OPTS) -filetype=obj - -o $@

# .bc: solo LTO; reciben nounwind/optsize/minsize.
$(foreach m,$(REGEX_LL),$(BUILD)/$(m).bc): $(BUILD)/%.bc: regex/%.ll $(RX_TYPES) | $(BUILD)
	{ cat $(RX_TYPES); $(ATTR_FILTER) $<; } | $(OPT) $(OPT_TRIPLE) $(OPT_PASS) - -o $@

$(BUILD)/%.o: %.ll | $(BUILD)
	$(OPT) $(OPT_TRIPLE) $(OPT_PASS) $< -o - | $(LLC) $(LLC_OPTS) -filetype=obj - -o $@

$(BUILD)/%.bc: %.ll | $(BUILD)
	$(ATTR_FILTER) $< | $(OPT) $(OPT_TRIPLE) $(OPT_PASS) - -o $@

# nucleo Fexl en IR: value_types.ll inyectado, mismo pipeline que regex/
$(BUILD)/fexl_%.o: $(FEXL_IR_DIR)/%.ll $(FEXL_IR_TYPES) | $(BUILD)
	{ cat $(FEXL_IR_TYPES); $(ATTR_FILTER) $<; } | $(OPT) $(OPT_TRIPLE) $(OPT_PASS) - -o - \
	  | $(LLC) $(LLC_OPTS) -filetype=obj - -o $@

TUI_LL := state window canvas win_editor console memory fileman fexl_ui eval shell draw
ENGINE_LL := fsio_posix fsio_ensure_dir fsio_list_dir fsio_actions fsio_getdents \
             textbuffer lineindex document history find chunk \
             replace regex_parser regex_compiler regex_thread regex_runner format
ALL_LL := $(TUI_LL) $(ENGINE_LL)
ALL_C  := main in out

LL_OBJ := $(addprefix $(BUILD)/,$(addsuffix .o,$(ALL_LL)))
C_OBJ  := $(addprefix $(BUILD)/,$(addsuffix .o,$(ALL_C)))
LL_BC  := $(addprefix $(BUILD)/,$(addsuffix .bc,$(ALL_LL)))
C_BC   := $(addprefix $(BUILD)/,$(addsuffix .bc,$(ALL_C)))

ifeq ($(LTO),1)
C_BC += $(BUILD)/dispatch.bc

# el motor regex ya viene dentro de fexlswi_lib.bc: no duplicarlo
FEXL_LIB    := fexlswi/lib/fexlswi_lib.bc
FUSED_LL_BC := $(filter-out $(addprefix $(BUILD)/,$(addsuffix .bc,regex_parser regex_compiler regex_thread regex_runner)),$(LL_BC))

$(BUILD)/fused.bc: $(FUSED_LL_BC) $(C_BC) $(FEXL_LIB)
	$(LLLINK) $(FUSED_LL_BC) $(C_BC) $(FEXL_LIB) -o $@

$(BUILD)/fused.opt.bc: $(BUILD)/fused.bc
	$(OPT) $(OPT_TRIPLE) $(OPT_LTO) $< -o $@

$(BUILD)/fused.o: $(BUILD)/fused.opt.bc
	$(LLC) $(LLC_LTO) -filetype=obj $< -o $@

SWI_DEPS := $(BUILD)/fused.o
else
SWI_DEPS := $(C_OBJ) $(LL_OBJ)
endif

$(BUILD)/swi: $(SWI_DEPS)
	$(CLANG) $(LDFLAGS) $^ -o $@
ifeq ($(LTO),1)
	$(LLSTRIP) --strip-all -R .comment -R .note.gnu.property $@
endif
	@if [ "$(BUILD)" != "build" ]; then \
		mkdir -p build && cp -a $@ build/swi; \
	fi

# --- arneses por modulo ---
$(BUILD)/test_state.o: test/test_state.c tui/in.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_state: $(BUILD)/test_state.o $(BUILD)/state.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_window.o: test/test_window.c | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_window: $(BUILD)/test_window.o $(BUILD)/window.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_canvas.o: test/test_canvas.c | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_canvas: $(BUILD)/test_canvas.o $(BUILD)/canvas.o $(BUILD)/window.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_win_editor.o: test/test_win_editor.c tui/in.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/shell_globals.o: test/shell_globals.c abi/tui_abi.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_win_editor: $(BUILD)/test_win_editor.o $(BUILD)/shell_globals.o $(BUILD)/win_editor.o $(LL_OBJ)
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_console.o: test/test_console.c tui/in.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_console: $(BUILD)/test_console.o $(BUILD)/console.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_fileman.o: test/test_fileman.c | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_fileman: $(BUILD)/test_fileman.o $(BUILD)/fileman.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_memory.o: test/test_memory.c | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_memory: $(BUILD)/test_memory.o $(BUILD)/memory.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_fexl_ui.o: test/test_fexl_ui.c tui/fexl_ui.h | $(BUILD)
	$(CLANG) $(CFLAGS) $(EVAL_DEF) -I. -c $< -o $@
$(BUILD)/test_fexl_ui: $(BUILD)/test_fexl_ui.o $(BUILD)/fexl_ui.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

# nucleo Fexl migrado a IR (value/memory/str) + stubs de die/fput en el arnes
$(BUILD)/test_fexl_value.o: test/test_fexl_value.c abi/fexl_abi.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_fexl_value: $(BUILD)/test_fexl_value.o \
                          $(BUILD)/fexl_value.o $(BUILD)/fexl_memory.o $(BUILD)/fexl_str.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_integration.o: test/test_integration.c tui/in.h tui/eval.h \
                             tui/fexl_ui.h abi/tui_abi.h | $(BUILD)
	$(CLANG) $(CFLAGS) $(EVAL_DEF) $(UI_SCRIPT_DEF) -I. -c $< -o $@
$(BUILD)/test_integration: $(BUILD)/test_integration.o $(BUILD)/shell_globals.o $(LL_OBJ)
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

run: $(BUILD)/swi
	./$(BUILD)/swi

run-opt:
	$(MAKE) MODE=opt run

test: $(BUILD)/test_state $(BUILD)/test_window $(BUILD)/test_canvas \
      $(BUILD)/test_win_editor $(BUILD)/test_console $(BUILD)/test_fileman \
      $(BUILD)/test_memory $(BUILD)/test_fexl_ui $(BUILD)/test_fexl_value \
      $(BUILD)/test_integration $(BUILD)/swi
	./$(BUILD)/test_state
	./$(BUILD)/test_window
	./$(BUILD)/test_canvas
	./$(BUILD)/test_win_editor
	./$(BUILD)/test_console
	./$(BUILD)/test_fileman
	./$(BUILD)/test_memory
	./$(BUILD)/test_fexl_ui
	./$(BUILD)/test_fexl_value
	./$(BUILD)/test_integration

test-opt:
	$(MAKE) MODE=opt test

test-selfh:
	$(MAKE) MODE=selfh test

size: $(BUILD)/swi
	@ls -lh $(BUILD)/swi | awk '{print "swi ($(if $(MODE),$(MODE),fast)): " $$5}'

size-opt:
	$(MAKE) MODE=opt size

size-selfh:
	$(MAKE) MODE=selfh size
