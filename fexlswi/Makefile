# fexlswi — capa de compatibilidad y runtime del lenguaje.
#
# El lenguaje se compila APARTE en ../fexlswi-llvm (intérprete en IR + C
# residual). Este Makefile solo delega y publica los productos en bin/ y lib/,
# que es donde el Makefile raíz los espera. En src/ queda unicamente el
# runtime Fexl (.fxl); los .c migrados a IR ya no estan aca.

LLVMDIR := ../fexlswi-llvm

.PHONY: all fast opt opt-full selfh clean
all: opt-full

fast opt opt-full selfh:
	$(MAKE) -C $(LLVMDIR) clean
	$(MAKE) -C $(LLVMDIR) $@
	mkdir -p bin lib
	cp -a $(LLVMDIR)/bin/. bin/
	cp -a $(LLVMDIR)/lib/. lib/

clean:
	$(MAKE) -C $(LLVMDIR) clean
	rm -rf bin lib obj build
	@echo "fexlswi limpio"
