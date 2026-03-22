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
Regenerate BSP data: `python tools/wad2snes.py testmap_bsp.wad data/bsp_data.asm`
Regenerate GSU trig tables: `python tools/wad2snes.py --tables data/gsu_tables.asm`

## Architecture

**Doom SNES-style BSP renderer** with split CPU/GSU responsibilities:

- **65816 (C via PVSnesLib `816-tcc`)**: Player input, movement, writes ViewX/ViewY/ViewAngle to SuperFX RAM at `$70:0000`.
- **SuperFX GSU (assembly via `wla-superfx`)**: BSP traversal, vertex rotation, wall height computation, column fill, tile rendering. All rendering on GSU.
- **Display**: Mode 3 (BG1 8bpp), hardware window (WH0=20, WH1=235) masks to 216px centered. Viewport 27x18 tiles (216x144 pixels) + 4-row HUD = 22 rows (176px) centered vertically in 224px screen.

### Per-Frame Flow
```
65816: handleInput() → writePlayerState($70:0000-0005)
     → startGSU() [launches from WRAM stub to avoid ROM bus conflict]
GSU:  BSP traversal → vertex rotation → projection → column fill → tile rendering → stop
65816: dmaFramebuffer() [6-batch VBlank DMA $70:0400 → VRAM] → loop
```

### Column Data Format ($70:0040, 81 bytes)
27 columns × 3 arrays: `drawStart[27]@$0040, drawEnd[27]@$0060, wallColor[27]@$0080`
columnFilled[27]@$00A0 tracks which columns have been filled (front-to-back BSP)

### Player State ($70:0000)
- $0000: ViewX (s16, world coordinates)
- $0002: ViewY (s16, world coordinates)
- $0004: ViewAngle (byte, 0-255)

## Critical Constraints

### 816-tcc Compiler Limitations
- `tcc__mul` is **16x16→16 only** (no 32-bit multiply). `(signed long)` casts are silently ignored.
- All fixed-point math must use decomposed 8-bit partial products via `fp_mul()` or lookup tables.
- `int` is 16-bit, `long` is 32-bit (but multiply/divide don't use 32-bit).
- Function return values go in `tcc__r0`.

### Hardware Register Access
- All PPU/DMA register writes (`$2100`-`$43FF`) **must use `.l` (long addressing)** in assembly because DBR=$7E (WRAM). Without `.l`, writes go to WRAM instead of hardware.

### SuperFX ROM Bus Conflict
- The 65816 **cannot access ROM** while the GSU runs (shared bus).
- `startGSU()` copies a launcher stub to WRAM (`$7E:1E00`) and executes from there.
- GSU ROM addresses = 65816 address minus `$8000` (LoROM mapping).

### PVSnesLib VBlank Handler
- PVSnesLib's NMI handler **corrupts VRAM**. Must call `disableNMI()` after init.
- All display register restoration done manually in `dmaFramebuffer()`.

### WLA-SuperFX Assembler — CRITICAL BUGS AND QUIRKS
- `ldb`/`stb`/`ldw`/`stw` only work with R0-R11 (not R12-R15).
- `AND` must be uppercase (lowercase `and` is a reserved keyword).
- `add #N` / `sub #N` immediates limited to 0-15.
- Long branches: use inverted condition + `iwt r15, #label - $8000` + `nop`.
- After branches: always `nop` (delay slot).
- **STACKED `from/to` PREFIXES ARE BROKEN**: `from rA; to rB; op rC` does NOT work — the `from` prefix gets consumed by `to`. Use `move rB, rA; with rB; op rC` instead. Single prefixes (`from rN`, `to rN`, `with rN`) work fine.
- **`ldb`/`ldw` DO NOT SET FLAGS**: After `ldb (rN)` or `ldw (rN)`, you MUST add `add #0` before `bne`/`beq` to set the zero flag. Without this, branch checks stale flags.
- **`loop` instruction requires `cache`/`cachee` setup**: Use `dec r12; bne _label; nop` instead of `loop; nop` for simple loops.
- **`sm`/`lm` at addresses > $0100 may have encoding issues**: Keep scratch RAM in range $0006-$003F (sms/lms short encoding). Or use `stw (rN)`/`ldw (rN)` with register pointers.
- `dec rN` and `inc rN` DO exist for all registers r0-r15 (despite some docs saying otherwise).
- `ibt` sign-extends: `ibt r0, #$FF` gives $FFFF, need `lob` for $00FF.

## Key Files

| File | Purpose |
|------|---------|
| `src/raycaster.c` | C code: player input, movement, writePlayerState |
| `data.asm` | 65816 asm: Mode 3 init, GSU control, DMA, palette, HW window, joypad |
| `gsu_raycaster.asm` | SuperFX asm: BSP traversal + vertex rotation + column fill + tile renderer |
| `hdr.asm` | ROM header: cart type $15 (SuperFX+RAM), SLOWROM LOROM |
| `data/bsp_data.asm` | Generated BSP data (Doom SNES format): vertices, nodes, areas, segs |
| `data/gsu_tables.asm` | Generated sin/cos tables (1.15 format for fmult+rol) |
| `data/*.h` | Generated: palettes (BGR555), sin/cos tables (8.8 for 65816), map |
| `tools/wad2snes.py` | WAD→SNES converter + GSU trig table generator |

## BSP Data Format (Doom SNES conventions from rle.i)

- **BSP Node (28 bytes)**: LineY, DeltaX, LineX, DeltaY, LeftBBox(4×2), LeftChild, RightBBox(4×2), RightChild
- **Area (4 bytes)**: NumSegs(1), SegOffset(2), Sector(1)
- **Seg (11 bytes)**: V1offset(2), V2offset(2), Flags(1), WallColor(1), pad(5)
- **Vertex (4 bytes)**: X(2), Y(2)
- Child pointers: positive = node byte offset, $8000|offset = subsector/area

## GSU RAM Map ($70:0000)

```
$0000-$0005: Player state (ViewX, ViewY, ViewAngle)
$0006-$003F: Scratch (BSP/rotation/projection temporaries)
$0040-$005A: drawStart[27]
$0060-$007A: drawEnd[27]
$0080-$009A: wallColor[27]
$00A0-$00BA: columnFilled[27]
$00C0-$00DF: Rotated vertex cache (8 verts × 4 bytes)
$00E0-$00E7: Row color types (Phase 2)
$00E8-$00EB: Sin/Cos values
$00F0-$0107: Bitplane precompute (ceil/wall/floor BP)
$0110-$014F: BSP stack
$0400-$7FFF: Framebuffer (486 tiles × 64 bytes)
```

## Development Philosophy

**Imitate the SNES Doom source code at every step.** The Doom SNES source is at `C:\Users\sator\Downloads\source\Source\` and serves as the authoritative reference. Key files:
- `rlbsp.a` — BSP traversal (cross-product side test, sight-line culling)
- `rlsegs.a/2/3/4` — segment projection, vertex rotation, clipping
- `rldraww.a` — wall column rendering on GSU
- `rlgsu.a` — GSU initialization, phase system
- `rlirq.a` — IRQ-driven display windowing
- `rle.i` — all structure definitions

## Current Status (as of 2026-03-22)

BSP rendering pipeline is partially working:
- ✅ BSP tree traversal (visits all 8 subsectors correctly)
- ✅ Vertex rotation (fmult+rol matching Doom's rlsegs2.a)
- ✅ Per-segment column projection (binary divide, col1/col2)
- ✅ Column fill with colFilled front-to-back check
- ✅ Phase 2 stb tile rendering
- ✅ Doom-style hardware window display
- ❌ **Per-column depth interpolation** — currently uses single depth per segment, giving uniform wall height. Need to interpolate depth between segment vertices across columns.

## Other References
- Lodev raycasting tutorial: https://lodev.org/cgtutor/raycasting.html
- Test with both Mesen (accurate) and ZSNES (compatibility check)
