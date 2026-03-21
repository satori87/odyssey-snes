ifeq ($(strip $(PVSNESLIB_HOME)),)
$(error "Please create an environment variable PVSNESLIB_HOME with path to PVSnesLib")
endif

include ${PVSNESLIB_HOME}/devkitsnes/snes_rules

export ROMNAME := odyssey

all: $(ROMNAME).sfc

clean: cleanBuildRes cleanRom cleanGfx

# Source files in src/ are compiled automatically by snes_rules.
# Data headers in data/ are included directly by the C source.
