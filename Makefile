# Makefile — swi: dos perfiles, AMBOS con la TUI completa.
#
#   make / make fast   build/       verify + opt verify + llc -O0 + clang -O0 -g
#                                   -> compila rapido, con simbolos (valgrind)
#   make opt           build-opt/   verify + opt default<Oz> por modulo,
#                                   bitcode de todos los modulos + C -> llvm-link
#                                   -> internalize(main) + globaldce + default<Oz> (LTO)
#                                   -> llc -O2 static -function/data-sections
#                                   -> clang -Oz -no-pie + lld --icf=all --gc-sections
#                                      --strip-all -> binario de tamano minimo
#
# Por que Oz y no O3 (doc oficial de Clang):
#   -O3 "may generate larger code (in an attempt to make the program run
#        faster)"; -Oz "reduces code size further". O3 es para velocidad,
#        y ese binario ya existe en otro lado. Aca solo importa el tamano.
#   Se midio Oz(106824) vs Os(102024 con ICF) vs Oz+ICF(99616): gana Oz+ICF.
#   llc solo acepta -O0..-O3 (no -Oz): la reduccion la hace `opt default<Oz>`
#   sobre el IR, antes de llc. LTO es full (llvm-link + opt sobre el fused).
#
# Ajustes de tamano (perfil opt):
#   - internalize<preserve-gv=main> + globaldce: solo `main` queda exportado,
#     el resto de funciones/globales sin uso se elimina entre modulos.
#   - llc del fusionado con -function-sections/-data-sections: sin esto
#     --gc-sections e --icf no tienen secciones sobre las que trabajar.
#   - -no-pie + relocation static (sin PIC) en el fusionado.
#   - sin unwind tables, stack protector, build-id, relro, separate-code,
#     .comment.
#   - dinamico contra la libc del sistema (no estatico).
#
# Los dos perfiles producen el MISMO swi: main/in/out (termbox), state,
# window, canvas, console, win_editor (con todas sus features) y el motor.
# La diferencia es solo compilacion: iterar rapido vs. binario chico.
#
# verify es gate en todos los niveles, incluido el modulo fusionado.
#
# Nota: ENGINE_LL lista tambien fsio_ensure_dir, fsio_list_dir, fsio_actions
# y format; en el binario swi opt, globaldce elimina lo que nadie llama.
# (Los tests de win_editor linkean LL_OBJ completo, por eso siguen en la lista.)

LLVM_PREFIX ?=
CLANG   := $(LLVM_PREFIX)clang-21 --target=x86_64-linux-musl
OPT     := $(LLVM_PREFIX)opt-21
LLC     := $(LLVM_PREFIX)llc-21
LLLINK  := $(LLVM_PREFIX)llvm-link-21
LLSTRIP := $(LLVM_PREFIX)llvm-strip-21
LDFLAG_LTO := -fuse-ld=lld-21 -Wl,--icf=all

# Los .ll no declaran `target datalayout`. Sin triple, `opt` usa el layout
# LLVM por defecto (i64 alineado a 4) y reescribe los GEP de los structs
# con offsets 4/12/20 en vez de 8/16/24; llc despues los compila con el
# layout del host y la ABI se rompe. --mtriple lo evita.
OPT_TRIPLE := -mtriple=x86_64-linux-musl

# Link dinamico musl, minimo: mismo esquema que el repo anidado fexlswi.
MUSL_LINK := -L/usr/lib/x86_64-linux-musl \
             -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1 \
             -Wl,-rpath,/usr/lib/x86_64-linux-musl
TEST_LDFLAGS := $(MUSL_LINK) -lm

# ruta ABSOLUTA al interprete batch, derivada del directorio del Makefile
# (CURDIR = ~/swi -> fexlswi/bin/fexlswi0)
# Fexl vive en el repo anidado ~/fexlswi. Override:
#   make FEXL=/otro/fexlswi0 swi-fast
FEXL ?= fexlswi/bin/fexlswi0
EVAL_DEF := -DSWI_FEXL_BIN="\"$(abspath $(FEXL))\""
UI_SCRIPT_DEF := -DSWI_UI_SCRIPT="\"$(abspath $(CURDIR)/ui.fxl)\""

CFLAGS ?= -std=c11 -Wall -Wextra -Wpedantic

# Dos perfiles finales (opt / selfh), ambos dinamicos musl y de tamano minimo.
# `fast` sigue disponible para iterar (objetos por modulo, sin LTO).
ifneq ($(filter opt selfh,$(MODE)),)
BUILD      := build/$(MODE)
OPT_PASS   := -passes='verify,default<Oz>'
ifeq ($(MODE),opt)
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
FSIO  := fsio

vpath %.ll tui $(CORE) $(REGEX) $(FSIO)

.PHONY: all fast opt selfh swi-fast swi-opt swi-only run run-opt \
        test test-opt test-selfh size size-opt size-selfh clean

all: $(BUILD)/swi $(BUILD)/test_state $(BUILD)/test_window $(BUILD)/test_canvas \
     $(BUILD)/test_win_editor $(BUILD)/test_console $(BUILD)/test_memory \
     $(BUILD)/test_fexl_ui
	@$(MAKE) --no-print-directory size MODE=$(if $(MODE),$(MODE),fast)

fast:
	$(MAKE) MODE=fast all

opt:
	$(MAKE) MODE=opt all

selfh:
	$(MAKE) MODE=selfh all

# solo el binario swi (sin arneses de test) -- targets pedidos desde la raiz.
# swi-only se resuelve DENTRO del sub-make (ahi BUILD=build o build-opt segun MODE).
swi-fast:
	$(MAKE) MODE=fast swi-only

swi-opt:
	$(MAKE) MODE=opt swi-only

swi-only: $(BUILD)/swi
	@ls -lh $< | awk '{print "swi: " $$5}'

$(BUILD):
	mkdir -p $(BUILD)

# --- C: frontera con termbox ---
# En perfil opt se generan bitcode ademas del .o (el .o lo usan los tests,
# el bitcode se fusiona para el swi LTO).

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

# --- IR: un modulo por objeto (lo usan los tests en ambos perfiles) ---

$(BUILD)/%.o: %.ll | $(BUILD)
	$(OPT) $(OPT_TRIPLE) $(OPT_PASS) $< -o - | $(LLC) $(LLC_OPTS) -filetype=obj - -o $@

# --- IR: un modulo por bitcode (solo perfil opt, para el LTO) ---

$(BUILD)/%.bc: %.ll | $(BUILD)
	$(OPT) $(OPT_TRIPLE) $(OPT_PASS) $< -o $@

# --- modulos que entran en el swi ---

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

# --- binario swi ---

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

clean:
	rm -rf build build-opt
