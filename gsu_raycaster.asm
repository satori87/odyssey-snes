; Minimal Mode 3 plot test — solid fill with color 5
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

    ibt r14, #5
    color

    ibt r2, #0
_row:
    ibt r1, #0
_col:
    plot
    nop
    iwt r3, #160
    from r1
    cmp r3
    blt _col
    nop
    inc r2
    iwt r3, #96
    from r2
    cmp r3
    blt _row
    nop

    stop
    nop

.ENDS
