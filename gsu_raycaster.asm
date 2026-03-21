; Mode 3 + plot: 3 horizontal bands (ceiling/wall/floor)
; Tests that plot with color changes produces correct output
.MEMORYMAP
  SLOTSIZE $8000
  DEFAULTSLOT 0
  SLOT 0 $8000
  SLOT 1 $0 $2000
  SLOT 2 $2000 $E000
  SLOT 3 $0 $10000
.ENDME

.ROMBANKSIZE $8000
.ROMBANKS 8

.BANK 0
.SECTION "GSUCode" SUPERFREE

gsu_fill_screen:
    iwt r0, #$70
    ramb

    ; === Band 1: Ceiling (rows 0-23, color 16) ===
    ibt r14, #16
    color
    ibt r2, #0
_ceil_row:
    ibt r1, #0
_ceil_col:
    plot
    nop
    iwt r3, #160
    from r1
    cmp r3
    blt _ceil_col
    nop
    inc r2
    iwt r3, #24
    from r2
    cmp r3
    blt _ceil_row
    nop

    ; === Band 2: Wall (rows 24-71, color 5) ===
    ibt r14, #5
    color
_wall_row:
    ibt r1, #0
_wall_col:
    plot
    nop
    iwt r3, #160
    from r1
    cmp r3
    blt _wall_col
    nop
    inc r2
    iwt r3, #72
    from r2
    cmp r3
    blt _wall_row
    nop

    ; === Band 3: Floor (rows 72-95, color 17) ===
    ibt r14, #17
    color
_floor_row:
    ibt r1, #0
_floor_col:
    plot
    nop
    iwt r3, #160
    from r1
    cmp r3
    blt _floor_col
    nop
    inc r2
    iwt r3, #96
    from r2
    cmp r3
    blt _floor_row
    nop

    stop
    nop

.ENDS
