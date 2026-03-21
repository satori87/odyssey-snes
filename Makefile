# Odyssey SNES -- Custom build (no PVSnesLib runtime)
#
# Uses PVSnesLib's toolchain binaries (816-tcc, wla-65816, wlalink, 816-opt, constify)
# but does NOT link against PVSnesLib's crt0_snes.obj, libc.obj, libm.obj, or libtcc.obj.
# Instead we provide our own crt0.asm and tcclib.asm.

ifeq ($(strip $(PVSNESLIB_HOME)),)
$(error "Please set PVSNESLIB_HOME environment variable")
endif

# Toolchain paths
CC      := $(PVSNESLIB_HOME)/devkitsnes/bin/816-tcc
AS      := $(PVSNESLIB_HOME)/devkitsnes/bin/wla-65816
LD      := $(PVSNESLIB_HOME)/devkitsnes/bin/wlalink
OPT     := $(PVSNESLIB_HOME)/devkitsnes/tools/816-opt
CTF     := $(PVSNESLIB_HOME)/devkitsnes/tools/constify
ASFX    := tools/wla-dx/wla_dx_v10.6_Win64/wla-superfx

# Include paths (for 816-tcc to find headers)
CFLAGS  := -I$(PVSNESLIB_HOME)/pvsneslib/include -I$(PVSNESLIB_HOME)/devkitsnes/include -I.

ROMNAME := odyssey

# Object files (order matters for linkfile)
OBJS := crt0.obj tcclib.obj src/raycaster.obj hdr.obj data.obj gsu_raycaster.obj

.PHONY: all clean

all: $(ROMNAME).sfc

# --- SuperFX assembly ---
gsu_raycaster.obj: gsu_raycaster.asm
	@echo [ASM-SFX] $<
	$(ASFX) -d -s -x -o $@ $<

# --- C compilation pipeline: .c -> .ps -> .asp -> .asm ---
src/raycaster.ps: src/raycaster.c
	@echo [CC] $<
	$(CC) $(CFLAGS) -Wall -c $< -o $@

src/raycaster.asm: src/raycaster.ps src/raycaster.c
	@echo [OPT] $<
	$(OPT) $< > src/raycaster.asp
	@echo [CTF] constify
	$(CTF) src/raycaster.c src/raycaster.asp $@
	@rm -f src/raycaster.asp

# --- 65816 assembly ---
src/raycaster.obj: src/raycaster.asm
	@echo [ASM] $<
	$(AS) -d -s -x -o $@ $<

hdr.obj: hdr.asm
	@echo [ASM] $<
	$(AS) -d -s -x -o $@ $<

data.obj: data.asm
	@echo [ASM] $<
	$(AS) -d -s -x -o $@ $<

crt0.obj: crt0.asm hdr.asm
	@echo [ASM] $<
	$(AS) -d -s -x -o $@ $<

tcclib.obj: tcclib.asm hdr.asm
	@echo [ASM] $<
	$(AS) -d -s -x -o $@ $<

# --- Link ---
$(ROMNAME).sfc: $(OBJS) linkfile
	@echo [LINK] $@
	@rm -f $(ROMNAME).sym
	$(LD) -d -s -v -A -c linkfile $@
	@sed -i 's/://' $(ROMNAME).sym 2>/dev/null || true
	@sed -i '/ SECTIONSTART_/d;/ SECTIONEND_/d;/ RAM_USAGE_SLOT_/d;' $(ROMNAME).sym 2>/dev/null || true
	@echo
	@echo Build finished successfully!
	@echo

clean:
	rm -f $(OBJS) $(ROMNAME).sfc $(ROMNAME).sym
	rm -f src/raycaster.ps src/raycaster.asp src/raycaster.asm
