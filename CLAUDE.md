# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

The Makefile doesn't work with Git Bash path handling. Use this manual build pipeline:

```bash
export PVSNESLIB_HOME=/c/pvsneslib/pvsneslib
export PVBIN="$PVSNESLIB_HOME/devkitsnes/bin"
export PVTOOLS="$PVSNESLIB_HOME/devkitsnes/tools"
export PVLIB="$PVSNESLIB_HOME/pvsneslib/lib/LoROM_SlowROM"
export PVINC="-I$PVSNESLIB_HOME/pvsneslib/include -I$PVSNESLIB_HOME/devkitsnes/include -I/c/dev/odyssey-snes"
export WLASFX="/c/dev/odyssey-snes/tools/wla-dx/wla_dx_v10.6_Win64/wla-superfx.exe"

# Compile C → assembly
"$PVBIN/816-tcc" $PVINC -Wall -c src/raycaster.c -o src/raycaster.ps 2>&1
"$PVTOOLS/816-opt" src/raycaster.ps > src/raycaster.asp
"$PVTOOLS/constify" src/raycaster.c src/raycaster.asp src/raycaster.asm

# Assemble
"$PVBIN/wla-65816" -d -s -x -o src/raycaster.obj src/raycaster.asm
"$PVBIN/wla-65816" -d -s -x -o hdr.obj hdr.asm
"$PVBIN/wla-65816" -d -s -x -o data.obj data.asm
"$WLASFX" -o gsu_raycaster.obj gsu_raycaster.asm

# Link
cat > linkfile << 'EOF'
[objects]
src/raycaster.obj
hdr.obj
data.obj
gsu_raycaster.obj
C:/pvsneslib/pvsneslib/pvsneslib/lib/LoROM_SlowROM/crt0_snes.obj
C:/pvsneslib/pvsneslib/pvsneslib/lib/LoROM_SlowROM/libc.obj
C:/pvsneslib/pvsneslib/pvsneslib/lib/LoROM_SlowROM/libm.obj
C:/pvsneslib/pvsneslib/pvsneslib/lib/LoROM_SlowROM/libtcc.obj
EOF
"$PVBIN/wlalink" -d -s -v -A -c -L "$PVLIB" linkfile odyssey.sfc
```

Regenerate lookup tables: `python tools/generate_tables_c.py`
Regenerate texture/palette data: `python tools/convert_textures_c.py`

## Architecture

**Doom SNES-style hybrid raycaster** with split CPU/GPU responsibilities:

- **65816 (C via PVSnesLib `816-tcc`)**: DDA raycasting math, player input, collision detection. Writes 60 bytes of pre-computed column data to SuperFX RAM at `$70:0000`.
- **SuperFX GSU (assembly via `wla-superfx`)**: Pixel plotter only — reads column data, writes tile-formatted pixels to framebuffer at `$70:0400`. No math on GSU.
- **Display**: Mode 7 with 1.6x scaling matrix (M7A=M7D=$00A0). 160x80 viewport = 20x10 tiles.

### Per-Frame Flow
```
65816: handleInput() → castRays() → writeColumnData($70:0000)
     → startGSU() [launches from WRAM stub to avoid ROM bus conflict]
GSU:  reads column data → writes 12800 bytes of tile pixels → stop
65816: dmaFramebuffer() [forced blank + DMA $70:0400 → VRAM] → screen on
```

### Column Data Format ($70:0000, 60 bytes)
20 columns × 3 bytes: `drawStart(u8), drawEnd(u8), wallColor(u8)`

## Critical Constraints

### 816-tcc Compiler Limitations
- `tcc__mul` is **16×16→16 only** (no 32-bit multiply). `(signed long)` casts are silently ignored.
- All fixed-point math must use decomposed 8-bit partial products via `fp_mul()` or lookup tables.
- `fp_div` is eliminated — use `recip_table[256]` lookup instead.
- `int` is 16-bit, `long` is 32-bit (but multiply/divide don't use 32-bit).
- Function return values go in `tcc__r0`.

### Hardware Register Access
- All PPU/DMA register writes (`$2100`-`$43FF`) **must use `.l` (long addressing)** in assembly because DBR=$7E (WRAM). Without `.l`, writes go to WRAM instead of hardware.

### SuperFX ROM Bus Conflict
- The 65816 **cannot access ROM** while the GSU runs (shared bus).
- `startGSU()` copies a launcher stub to WRAM (`$7E:1E00`) and executes from there.
- GSU ROM addresses = 65816 address minus `$8000` (LoROM mapping).

### PVSnesLib VBlank Handler
- PVSnesLib's NMI handler **corrupts Mode 7 VRAM**. Must call `disableNMI()` after init.
- All display register restoration done manually in `dmaFramebuffer()`.

### WLA-SuperFX Assembler
- `ldb`/`stb`/`ldw`/`stw` only work with R0-R11 (not R12-R15).
- `AND` must be uppercase (lowercase `and` is a reserved keyword).
- `add #N` / `sub #N` immediates limited to 0-15.
- Long branches: use inverted condition + `iwt r15, #label - $8000` + `nop`.
- After `plot`: always `nop` (pipeline). After branches: always `nop` (delay slot).

## Key Files

| File | Purpose |
|------|---------|
| `src/raycaster.c` | C code: DDA raycasting, input, collision, fp_mul/fast_recip math |
| `data.asm` | 65816 asm: Mode 7 init, GSU control, DMA, palette load, I/O helpers |
| `gsu_raycaster.asm` | SuperFX asm: pixel plotter reading from pre-computed column data |
| `hdr.asm` | ROM header: cart type $15 (SuperFX+RAM), SLOWROM LOROM |
| `data/*.h` | Generated: palettes (BGR555), sin/cos tables (8.8), map (10x10), textures |
| `tools/*_c.py` | Asset pipeline: PNG→palette/texture, math→lookup tables |

## Development Philosophy

**Imitate the SNES Doom source code at every step.** The Doom SNES source is at `C:\Users\sator\Downloads\source\Source\` and serves as the authoritative reference for how to solve any rendering, DMA, timing, or architecture problem on the SNES with SuperFX. Before implementing any feature or fix, check how Doom does it first. Do not take shortcuts or diverge from Doom's patterns — they were battle-tested on real hardware. Key files to reference:
- `rlmain.a` — main game loop structure and frame coordination
- `rldraww.a` — wall column rendering on GSU (plot patterns, scaling, color maps)
- `rldrawf.a` / `rldrawf2.a` — floor/ceiling rendering
- `rlgsu.a` — GSU initialization, phase table, CallGSU implementation
- `rlirq.a` — IRQ-driven GSU phase cycling and DMA timing
- `rlnmi.a` — NMI handler and VBlank coordination
- `rlinit.a` — display mode setup, VRAM layout, character base configuration
- `rlmath.a` — fixed-point math on GSU

## Other References
- Lodev raycasting tutorial: https://lodev.org/cgtutor/raycasting.html
- Test with both Mesen (accurate) and ZSNES (compatibility check)
