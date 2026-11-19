# Makefile unificado — swi + fexlswi (repo anidado).
#
#   make opt        fexlswi opt + swi opt
#   make opt-full   fexlswi opt-full + swi opt-full, de una sola corrida
#   make fast       fexlswi fast + swi fast (iterar/debug)
#   make selfh      fexlswi selfh + swi selfh
#   make clean all  limpia ambos proyectos y no compila nada
#   make install    empaqueta build/ con un binario y una carpeta
#
# Las recetas de fexlswi viven aca (Makefile mas nuevo, 20:09); las de swi
# se portaron del Makefile anterior sin restaurar archivos.

LLVM_PREFIX ?=
FEXL_CC ?= clang --target=x86_64-linux-musl -isystem /usr/include/x86_64-linux-musl
OPT     ?= opt-21
CLANG   := $(LLVM_PREFIX)clang-21 --target=x86_64-linux-musl
LLC     := $(LLVM_PREFIX)llc-21
LLLINK  := $(LLVM_PREFIX)llvm-link-21
LLSTRIP := $(LLVM_PREFIX)llvm-strip-21
LDFLAG_LTO := -fuse-ld=lld-21 -Wl,--icf=all

# Los .ll no declaran target datalayout: sin -mtriple la ABI se rompe.
OPT_TRIPLE := -mtriple=x86_64-linux-musl

MUSL_LINK := -L/usr/lib/x86_64-linux-musl \
             -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1 \
             -Wl,-rpath,/usr/lib/x86_64-linux-musl
TEST_LDFLAGS := $(MUSL_LINK) -lm

FEXL ?= fexlswi/bin/fexlswi0
UI_SCRIPT ?= ui.fxl
EVAL_DEF := -DSWI_FEXL_BIN="\"$(abspath $(FEXL))\""
UI_SCRIPT_DEF := -DSWI_UI_SCRIPT="\"$(abspath $(UI_SCRIPT))\""

CFLAGS ?= -std=c11 -Wall -Wextra -Wpedantic

MODULOS := regex_parser regex_compiler regex_abregex regex_thread \
           regex_runner rx_query rx_runtime

# --- fexlswi: perfiles ---
FAST_COPT := -O0 -g
FAST_LINK := -fuse-ld=lld $(MUSL_LINK)
OPT_COPT := -Oz -ffunction-sections -fdata-sections \
            -fno-unwind-tables -fno-asynchronous-unwind-tables \
            -fno-stack-protector -Dtimelocal=mktime
OPT_LINK := -Oz -fuse-ld=lld $(MUSL_LINK) -Wl,--gc-sections -Wl,--icf=all \
            -Wl,-O2 -Wl,--build-id=none -s
FULL_LINK := $(OPT_LINK) -Wl,-z,norelro -Wl,--hash-style=gnu -Wl,--no-rosegment

ATTR_FILTER = sed -E '/^define /{/\)[^)]*([ ](section|align|gc|prefix|prologue|personality|comdat)[ ]|!)[^)]*\{$$/b;s/ \{$$/ nounwind optsize minsize {/}'

# --- swi: perfiles (BUILD cambiado segun MODE) ---
ifneq ($(filter opt selfh opt-full,$(MODE)),)
BUILD      := build/$(MODE)
OPT_PASS   := -passes='verify,default<Oz>'
ifeq ($(MODE),opt-full)
OPT_LTO    := -passes='verify,internalize<preserve-gv=main>,globaldce,default<Oz>,verify'
else ifeq ($(MODE),opt)
OPT_LTO    := -passes='verify,internalize<preserve-gv=main>,globaldce,default<Oz>,verify'
else
OPT_LTO    := -passes='verify,internalize<preserve-gv=main>,default<Oz>,verify'
endif
LLC_OPTS   := -O2 -relocation-model=pic
LLC_LTO    := -O2 -relocation-model=pic -function-sections -data-sections
CFLAGS     += -Oz -DNDEBUG -ffunction-sections -fdata-sections
CBCFLAGS   := -Oz -DNDEBUG -ffunction-sections -fdata-sections -emit-llvm \
              -fno-unwind-tables -fno-asynchronous-unwind-tables \
              -fno-stack-protector -fno-ident
LDFLAGS    := -Oz $(LDFLAG_LTO) $(MUSL_LINK) -Wl,--gc-sections -Wl,--strip-all
LTO        := 1
else
BUILD      := build
OPT_PASS   := -passes=verify
LLC_OPTS   := -O0 -relocation-model=pic
CFLAGS     += -O0 -g $(MUSL_LINK)
LDFLAGS    := $(MUSL_LINK)
LTO        :=
endif

CORE  := core
REGEX := regex
RX_TYPES := regex/rx_types.ll
# Modulos de regex/ que se linkean en swi (inyectan RX_TYPES al compilar).
REGEX_LL := replace format regex_parser regex_compiler regex_thread regex_runner
FSIO  := fsio
vpath %.ll tui $(CORE) $(REGEX) $(FSIO)

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

# Receta comun de fexlswi. Las variables P_* se fijan por objetivo mas abajo.
define BUILD_FEXL
	cd fexlswi/src && ./build clean
	rm -rf fexlswi/build/$(P)
	mkdir -p regex/build
	@for m in $(MODULOS); do \
		{ cat $(RX_TYPES); $(P_FILT) regex/$$m.ll; } \
		| $(OPT) -mtriple=x86_64-linux-musl -passes='$(P_MOD)' - -o regex/build/$$m.bc || exit 1; \
	done
	cd fexlswi/src && \
		FEXL_CC="$(FEXL_CC)" FEXL_COPT='$(P_COPT)' \
		FEXL_LDFLAGS='$(P_LINK)' \
		FEXL_FUSE_OPT='$(P_FUSE)' \
		./build && \
		FEXL_CC="$(FEXL_CC)" FEXL_COPT='$(P_COPT)' \
		FEXL_LDFLAGS='$(P_LINK)' \
		FEXL_FUSE_OPT='$(P_FUSE)' \
		./build_regex
	mkdir -p fexlswi/build/$(P)/bin fexlswi/build/$(P)/lib
	cp -a fexlswi/bin/. fexlswi/build/$(P)/bin/
	cp fexlswi/lib/fexlswi.bc fexlswi/build/$(P)/lib/
	@echo "listo: fexlswi/build/$(P)/bin/fexlswi0 ($(P_MSG))"
endef

fast: P := fast
fast: P_COPT := $(FAST_COPT)
fast: P_LINK := $(FAST_LINK)
fast: P_FUSE := verify
fast: P_MOD  := verify
fast: P_FILT := cat
fast: P_MSG  := dinamico musl, -O0 -g
fast:
	$(BUILD_FEXL)
	$(MAKE) MODE=fast swi-build

opt: P := opt
opt: P_COPT := $(OPT_COPT)
opt: P_LINK := $(OPT_LINK)
opt: P_FUSE := default<Oz>,globaldce
opt: P_MOD  := verify,default<Oz>
opt: P_FILT := $(ATTR_FILTER)
opt: P_MSG  := dinamico musl, -Oz + LTO
opt:
	$(BUILD_FEXL)
	$(MAKE) MODE=opt swi-build

opt-full: P := opt-full
opt-full: P_COPT := $(OPT_COPT)
opt-full: P_LINK := $(FULL_LINK)
opt-full: P_FUSE := internalize<preserve-gv=main>,globaldce,default<Oz>
opt-full: P_MOD  := verify,default<Oz>
opt-full: P_FILT := $(ATTR_FILTER)
opt-full: P_MSG  := dinamico musl, -Oz + LTO + internalize
opt-full:
	$(BUILD_FEXL)
	$(MAKE) MODE=opt-full swi-build

selfh: P := selfh
selfh: P_COPT := $(OPT_COPT)
selfh: P_LINK := $(OPT_LINK)
selfh: P_FUSE := default<Oz>
selfh: P_MOD  := verify,default<Oz>
selfh: P_FILT := $(ATTR_FILTER)
selfh: P_MSG  := dinamico musl, -Oz + LTO
selfh:
	$(BUILD_FEXL)
	$(MAKE) MODE=selfh swi-build

clean:
	cd fexlswi/src && ./build clean
	rm -rf fexlswi/build fexlswi/bin fexlswi/lib fexlswi/obj regex/build
	rm -rf build build-opt .install-build
	@echo "swi + fexlswi limpios"

# Install: NO compila; empaqueta lo que produjo make opt.
install:
	@test -f build/opt/swi -o -f build/opt-full/swi || \
		{ echo "correr make opt u opt-full primero"; exit 1; }
	@test -f fexlswi/bin/fexlswi0 || { echo "compilar fexlswi primero"; exit 1; }
	rm -rf .install-tmp
	mkdir -p .install-tmp
	@if [ -f build/opt-full/swi ]; then cp build/opt-full/swi .install-tmp/swi; \
	 else cp build/opt/swi .install-tmp/swi; fi
	cp fexlswi/bin/fexlswi0 .install-tmp/fexlswi0
	cp -a fexlswi/src/lib .install-tmp/lib
	cp ui.fxl .install-tmp/ui.fxl
	rm -rf build
	mkdir -p build/fexlswi/bin build/fexlswi/src
	cp .install-tmp/swi build/swi
	cp .install-tmp/fexlswi0 build/fexlswi/bin/fexlswi0
	cp -a .install-tmp/lib build/fexlswi/src/lib
	cp .install-tmp/ui.fxl build/fexlswi/ui.fxl
	rm -rf .install-tmp
	@echo "install listo: build/swi + build/fexlswi/"

swi-fast:
	$(MAKE) MODE=fast swi-build

swi-opt:
	$(MAKE) MODE=opt swi-build

swi-only: swi-build

swi-build: $(BUILD)/swi
	@ls -lh $< | awk '{print "swi: " $$5}'

$(BUILD):
	mkdir -p $(BUILD)

# --- C: frontera con termbox ---
$(BUILD)/in.o: tui/in.c tui/in.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@

$(BUILD)/out.o: tui/out.c tui/out.h tui/termbox2.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@

$(BUILD)/main.o: tui/main.c tui/in.h tui/out.h tui/eval.h tui/fexl_ui.h tui/termbox2.h abi/tui_abi.h | $(BUILD)
	$(CLANG) $(CFLAGS) $(EVAL_DEF) $(UI_SCRIPT_DEF) -I. -c $< -o $@

$(BUILD)/eval.o: tui/eval.c tui/eval.h | $(BUILD)
	$(CLANG) $(CFLAGS) $(EVAL_DEF) -I. -c $< -o $@

$(BUILD)/in.bc: tui/in.c tui/in.h | $(BUILD)
	$(CLANG) $(CBCFLAGS) -I. -c $< -o $@

$(BUILD)/out.bc: tui/out.c tui/out.h tui/termbox2.h | $(BUILD)
	$(CLANG) $(CBCFLAGS) -I. -c $< -o $@

$(BUILD)/main.bc: tui/main.c tui/in.h tui/out.h tui/eval.h tui/fexl_ui.h tui/termbox2.h abi/tui_abi.h | $(BUILD)
	$(CLANG) $(CBCFLAGS) $(EVAL_DEF) $(UI_SCRIPT_DEF) -I. -c $< -o $@

$(BUILD)/eval.bc: tui/eval.c tui/eval.h | $(BUILD)
	$(CLANG) $(CBCFLAGS) $(EVAL_DEF) -I. -c $< -o $@

$(BUILD)/fexl_ui.o: tui/fexl_ui.c tui/fexl_ui.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@

$(BUILD)/fexl_ui.bc: tui/fexl_ui.c tui/fexl_ui.h | $(BUILD)
	$(CLANG) $(CBCFLAGS) -I. -c $< -o $@

# --- IR: un modulo por objeto / bitcode ---
# Los modulos de regex/ reciben RX_TYPES concatenado (LLVM IR no tiene include),
# para que %RxInst/%RxProgram tengan UNA sola definicion compartida.
$(foreach m,$(REGEX_LL),$(BUILD)/$(m).o): $(BUILD)/%.o: regex/%.ll $(RX_TYPES) | $(BUILD)
	cat $(RX_TYPES) $< | $(OPT) $(OPT_TRIPLE) $(OPT_PASS) - -o - \
	  | $(LLC) $(LLC_OPTS) -filetype=obj - -o $@

$(foreach m,$(REGEX_LL),$(BUILD)/$(m).bc): $(BUILD)/%.bc: regex/%.ll $(RX_TYPES) | $(BUILD)
	cat $(RX_TYPES) $< | $(OPT) $(OPT_TRIPLE) $(OPT_PASS) - -o $@

$(BUILD)/%.o: %.ll | $(BUILD)
	$(OPT) $(OPT_TRIPLE) $(OPT_PASS) $< -o - | $(LLC) $(LLC_OPTS) -filetype=obj - -o $@

$(BUILD)/%.bc: %.ll | $(BUILD)
	$(OPT) $(OPT_TRIPLE) $(OPT_PASS) $< -o $@

TUI_LL := state window canvas win_editor console memory
ENGINE_LL := fsio_posix fsio_ensure_dir fsio_list_dir fsio_actions fsio_getdents \
             textbuffer lineindex document history find chunk \
             replace regex_parser regex_compiler regex_thread regex_runner format
ALL_LL := $(TUI_LL) $(ENGINE_LL)
ALL_C  := main in out eval fexl_ui

LL_OBJ := $(addprefix $(BUILD)/,$(addsuffix .o,$(ALL_LL)))
C_OBJ  := $(addprefix $(BUILD)/,$(addsuffix .o,$(ALL_C)))
LL_BC  := $(addprefix $(BUILD)/,$(addsuffix .bc,$(ALL_LL)))
C_BC   := $(addprefix $(BUILD)/,$(addsuffix .bc,$(ALL_C)))

ifeq ($(LTO),1)
$(BUILD)/fused.bc: $(LL_BC) $(C_BC)
	$(LLLINK) $(LL_BC) $(C_BC) -o $@

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
$(BUILD)/test_win_editor: $(BUILD)/test_win_editor.o $(BUILD)/win_editor.o $(LL_OBJ)
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_console.o: test/test_console.c tui/in.h | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_console: $(BUILD)/test_console.o $(BUILD)/console.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_memory.o: test/test_memory.c | $(BUILD)
	$(CLANG) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/test_memory: $(BUILD)/test_memory.o $(BUILD)/memory.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

$(BUILD)/test_fexl_ui.o: test/test_fexl_ui.c tui/fexl_ui.h | $(BUILD)
	$(CLANG) $(CFLAGS) $(EVAL_DEF) -I. -c $< -o $@
$(BUILD)/test_fexl_ui: $(BUILD)/test_fexl_ui.o $(BUILD)/fexl_ui.o
	$(CLANG) $(TEST_LDFLAGS) $^ -o $@

run: $(BUILD)/swi
	./$(BUILD)/swi

run-opt:
	$(MAKE) MODE=opt run

test: $(BUILD)/test_state $(BUILD)/test_window $(BUILD)/test_canvas \
      $(BUILD)/test_win_editor $(BUILD)/test_console $(BUILD)/test_memory \
      $(BUILD)/test_fexl_ui $(BUILD)/swi
	./$(BUILD)/test_state
	./$(BUILD)/test_window
	./$(BUILD)/test_canvas
	./$(BUILD)/test_win_editor
	./$(BUILD)/test_console
	./$(BUILD)/test_memory
	./$(BUILD)/test_fexl_ui
	./$(BUILD)/swi --selftest

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
