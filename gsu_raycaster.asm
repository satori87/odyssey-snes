; 3-band test with 32 tiles per row (matching sequential tilemap)
; Band 1 (rows 0-3 = tiles 0-127): $00 = black
; Band 2 (rows 4-7 = tiles 128-255): $FF = color 255 (bright)
; Band 3 (rows 8-11 = tiles 256-383): $55 = some pattern

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

    ; Total framebuffer: 384 tiles × 64 bytes = 24576 bytes
    ; $0400 to $6400

    ; Band 1: tiles 0-127 = $00 (black)
    ; 128 tiles × 64 bytes = 8192 bytes ($0400-$2400)
    iwt r1, #$0400
    iwt r2, #$2400
    ibt r0, #0
_b1:
    stb (r1)
    inc r1
    from r1
    cmp r2
    blt _b1
    nop

    ; Band 2: tiles 128-255 = $FF (all bits set = color 255)
    ; 128 tiles × 64 bytes = 8192 bytes ($2400-$4400)
    iwt r2, #$4400
    ibt r0, #$FF
    lob
_b2:
    stb (r1)
    inc r1
    from r1
    cmp r2
    blt _b2
    nop

    ; Band 3: tiles 256-383 = $00 (black, for contrast)
    ; 128 tiles × 64 bytes = 8192 bytes ($4400-$6400)
    iwt r2, #$6400
    ibt r0, #0
_b3:
    stb (r1)
    inc r1
    from r1
    cmp r2
    blt _b3
    nop

    stop
    nop

.ENDS
