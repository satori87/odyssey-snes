# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

The Makefile doesn't work with Git Bash path handling. Use this manual build pipeline:

```bash
export PVSNESLIB_HOME=/c/pvsneslib/pvsneslib
export PVBIN="$PVSNESLIB_HOME/devkitsnes/bin"
export PVTOOLS="$PVSNESLIB_HOME/devkitsnes/tools"
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
"$PVBIN/wla-65816" -d -s -x -o crt0.obj crt0.asm
"$PVBIN/wla-65816" -d -s -x -o tcclib.obj tcclib.asm
"$WLASFX" -o gsu_raycaster.obj gsu_raycaster.asm

# Link (uses project linkfile, NOT PVSnesLib libs)
"$PVBIN/wlalink" -d -s -v -A -c linkfile odyssey.sfc
```

Regenerate lookup tables: `python tools/generate_tables_c.py`
Regenerate texture/palette data: `python tools/convert_textures_c.py`

## Architecture

**DDA raycaster on SuperFX GSU at 21MHz** (Wolfenstein 3D SNES approach):

- **65816 (C via `816-tcc`)**: Player input, movement, collision detection, direction/plane vector computation. Writes 12 bytes of player state to `$70:0000`.
- **SuperFX GSU (assembly via `wla-superfx`)**: Complete DDA raycasting — ray direction, delta distances, DDA stepping, wall height, tile rendering. All math on GSU at 21MHz.
- **Display**: Mode 7 with 2× zoom (M7A=M7D=$0080). 128×96 viewport = 16×12 tiles + 2 HUD rows = 224 tiles total (within Mode 7's 256-tile limit). Fills 256×224 screen exactly.

### Per-Frame Flow
```
65816: handleInput() → writePlayerState($70:0000-000B, 12 bytes)
     → startGSU() [launches from WRAM stub to avoid ROM bus conflict]
GSU:  reads player state → DDA raycast 16 columns → writes tile pixels → stop
65816: dmaFramebuffer() [3-batch VBlank DMA $70:0400 → VRAM] → loop
```

### Player State ($70:0000, 12 bytes, all 8.8 fixed-point)
```
$0000: posX    (2 bytes)    $0006: dirY    (2 bytes)
$0002: posY    (2 bytes)    $0008: planeX  (2 bytes)
$0004: dirX    (2 bytes)    $000A: planeY  (2 bytes)
```

### GSU RAM Map ($70:xxxx)
```
$0000-$000B: Player state (6 words, 8.8 fixed-point)
$0010-$003F: Scratch (rayDir, deltaDist, sideDist, step, map, perpDist, etc.)
$0400-$3FFF: Framebuffer (192 viewport tiles × 64 bytes = 12288 bytes)
```

### DMA Strategy
3-batch VBlank DMA (flicker-free):
- Each batch: 4096 bytes (~24 of 38 VBlank scanlines, safe margin)
- Only 192 viewport tiles transferred; HUD tile 193 stays as init data
- 3 frames per render cycle (~20fps effective)

## Critical Constraints

### 816-tcc Compiler Limitations
- `tcc__mul` is **16×16→16 only** (no 32-bit multiply). `(signed long)` casts are silently ignored.
- All fixed-point math must use decomposed 8-bit partial products via `fp_mul()` or lookup tables.
- `int` is 16-bit, `long` is 32-bit (but multiply/divide don't use 32-bit).
- Function return values go in `tcc__r0`.

### Hardware Register Access
- All PPU/DMA register writes (`$2100`-`$43FF`) **must use `.l` (long addressing)** in assembly because DBR=$7E (WRAM). Without `.l`, writes go to WRAM instead of hardware.

### SuperFX ROM Bus Conflict
- The 65816 **cannot access ROM** while the GSU runs (shared bus).
- `startGSU()` copies a launcher stub to WRAM (`$7E:1E00`) and executes from there.
- GSU ROM addresses = 65816 address minus `$8000` (LoROM mapping).

### Mode 7 Tile Limit
- Mode 7 tilemap entries are 1 byte (0-255). Maximum 256 unique tiles.
- Current layout: 192 viewport + 1 HUD + 1 black = 194 used, 62 spare.
- Cannot exceed 256 tiles without switching to Mode 3 (which requires slow bitplane format).

### WLA-SuperFX Assembler Quirks
- `ldb`/`stb`/`ldw`/`stw` only work with R0-R11 (not R12-R15).
- `AND` must be uppercase (lowercase `and` is a reserved keyword).
- `add #N` / `sub #N` immediates limited to 0-15.
- `ibt` sign-extends: `ibt r0, #$90` gives $FF90 (use `iwt` for values ≥ 128).
- Long branches: use inverted condition + `iwt r15, #label - $8000` + `nop`.
- After branches: always `nop` (delay slot).

## Key Files

| File | Purpose |
|------|---------|
| `src/raycaster.c` | C code: player input, movement, collision, direction vectors |
| `data.asm` | 65816 asm: Mode 7 init, GSU control, 3-batch VBlank DMA, palette, IRQ infra |
| `gsu_raycaster.asm` | SuperFX asm: complete DDA raycaster + tile renderer |
| `hdr.asm` | ROM header: cart type $15 (SuperFX+RAM), SLOWROM LOROM |
| `crt0.asm` | Custom CRT0 runtime (not PVSnesLib standard) |
| `tcclib.asm` | TCC runtime support |
| `data/*.h` | Generated: palettes (BGR555), sin/cos tables (8.8), map (10×10) |
| `tools/*_c.py` | Asset pipeline: PNG→palette/texture, math→lookup tables |

## Map Format
- 10×10 byte grid in `data/map.h` (`world_map[10][10]`)
- 0 = empty, 1 = wall type 1 (bright/dark sides), 2 = wall type 2
- Player starts at (2.5, 2.5) in 8.8 fixed-point

## Other References
- Lodev raycasting tutorial: https://lodev.org/cgtutor/raycasting.html
- Test with both Mesen (accurate) and ZSNES (compatibility check)
- Doom SNES source at `C:\Users\sator\Downloads\source\Source\` for reference
