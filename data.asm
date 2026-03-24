;; Noah's Ark style Mode 7 display pipeline
;; Column-major tiles: tile = col*16 + row + 1
;; Per-column DMA with VMAINC=$8C for screenbuffer blit

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

.section ".display_code" superfree

.define SCREEN_W        112
.define SCREEN_H        80
.define FB_BASE         $2000
.define FB_BANK         $7F
.define FB_SIZE         8960
.define CEIL_COLOR      16
.define FLOOR_COLOR     17

initMode7Display:
    php
    phb
    sep #$20
    rep #$10

    ; Force blank
    lda #$80
    sta.l $2100

    ; Mode 7
    lda #$07
    sta.l $2105
    lda #$01
    sta.l $212C          ; TM = BG1

    ; 2x zoom: M7A=M7D=$0080
    lda #$80
    sta.l $211B
    lda #$00
    sta.l $211B          ; M7A=$0080
    lda #$00
    sta.l $211C
    sta.l $211C          ; M7B=0
    sta.l $211D
    sta.l $211D          ; M7C=0
    lda #$80
    sta.l $211E
    lda #$00
    sta.l $211E          ; M7D=$0080

    ; Scroll=0, Center=0
    lda #$00
    sta.l $210D
    sta.l $210D
    sta.l $210E
    sta.l $210E
    sta.l $211F
    sta.l $211F
    sta.l $2120
    sta.l $2120

    ; Palette
    lda #$00
    sta.l $2121
    ldx #$0000
@Pal:
    lda.l shared_palette,x
    sta.l $2122
    inx
    cpx #$0020
    bne @Pal
    lda #16
    sta.l $2121
    ldx #$0000
@ExPal:
    lda.l extra_palette,x
    sta.l $2122
    inx
    cpx #$0004
    bne @ExPal
    lda #18
    sta.l $2121
    lda #$FF
    sta.l $2122
    lda #$03
    sta.l $2122

    ; ============================================
    ; CLEAR VRAM (all words to 0)
    ; Write 0 to $2118, VMAINC=$00, 32768 times
    ; ============================================
    lda #$00
    sta.l $2115          ; VMAINC=$00: incr after low byte
    rep #$20
    lda #$0000
    sta.l $2116          ; VRAM addr 0
    ; DMA 32768 zeros to $2118
    sep #$20
    lda #$08             ; fixed source, A->B
    sta.l $4300
    lda #$18             ; B-bus: $2118 (VMDATAL)
    sta.l $4301
    rep #$20
    lda #zero_byte
    sta.l $4302
    sep #$20
    lda #:zero_byte
    sta.l $4304
    rep #$20
    lda #$0000           ; 65536 bytes = wraps to 0 = 64KB
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B          ; trigger — clears all VRAM low bytes

    ; Now clear high bytes too
    lda #$80
    sta.l $2115          ; VMAINC=$80: incr after high byte
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20
    lda #$08
    sta.l $4300
    lda #$19             ; B-bus: $2119 (VMDATAH)
    sta.l $4301
    rep #$20
    lda #zero_byte
    sta.l $4302
    sep #$20
    lda #:zero_byte
    sta.l $4304
    rep #$20
    lda #$0000           ; 64KB
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; ============================================
    ; TILEMAP: write LOW bytes only ($2118, VMAINC=$00)
    ; Noah's formula: tile = (col-1)*16 + (row-1) + 1
    ; Rows 1-10 viewport, cols 1-14 viewport
    ; ============================================
    lda #$00
    sta.l $2115          ; VMAINC=$00

    stz $40              ; tilemap row (0-127)
@TmR:
    ; Set VRAM address to row*128
    rep #$20
    lda $40
    and #$00FF
    xba                  ; *256
    lsr a                ; *128
    sta.l $2116
    sep #$20

    stz $41              ; tilemap col (0-127)
@TmC:
    ; Default tile 0
    lda #$00

    ; Viewport: row 1-10, col 1-14
    lda $40
    beq @TmW             ; row 0 = border
    cmp #11
    bcs @TmBdr           ; row >= 11 = not viewport
    lda $41
    beq @TmW0            ; col 0 = border
    cmp #15
    bcs @TmW0            ; col >= 15 = border

    ; Tile = (col-1)*16 + (row-1) + 1
    lda $41
    dec a                ; col-1 (0-13)
    asl a
    asl a
    asl a
    asl a                ; (col-1)*16
    sta $42
    lda $40
    dec a                ; row-1 (0-9)
    clc
    adc $42
    inc a                ; +1
    sta.l $2118
    bra @TmN

@TmBdr:
    ; Rows 11-12: HUD (tile 225 for now)
    lda $40
    cmp #13
    bcs @TmW0            ; row >= 13 = bottom border
    lda $41
    beq @TmW0
    cmp #15
    bcs @TmW0
    lda #225             ; HUD tile
    sta.l $2118
    bra @TmN

@TmW0:
    lda #$00
@TmW:
    sta.l $2118
@TmN:
    inc $41
    lda $41
    cmp #$80
    bne @TmC
    inc $40
    lda $40
    cmp #$80
    bne @TmR

    ; ============================================
    ; TILE PIXEL DATA: write HIGH bytes only ($2119, VMAINC=$80)
    ; Tile 0 already cleared to 0 (black) by VRAM clear
    ; Write viewport tiles 1-224 with 3-band pattern
    ; Tile T: col=(T-1)/16, row=(T-1)&15
    ; ============================================
    lda #$80
    sta.l $2115          ; VMAINC=$80
    rep #$20
    lda #$0040           ; word 64 = tile 1 start
    sta.l $2116
    sep #$20

    ; Write 224 tiles (14 cols * 16 rows per col) * 64 bytes
    ; For tile T=1..224: row = (T-1)&15
    ;   row 0-2: ceiling, row 3-6: wall, row 7-9: floor, row 10-15: black
    stz $40              ; tile col (0-13)
@PixC:
    stz $41              ; tile row within col (0-15)
@PixR:
    ; Pick color based on row
    lda $41
    cmp #3
    bcc @PxCeil
    cmp #7
    bcc @PxWall
    cmp #10
    bcc @PxFloor
    lda #$00             ; unused rows: black
    bra @PxFill
@PxCeil:
    lda #CEIL_COLOR
    bra @PxFill
@PxWall:
    lda #5
    bra @PxFill
@PxFloor:
    lda #FLOOR_COLOR
@PxFill:
    ; Write 64 bytes of this color for one tile
    sta $42              ; save color
    ldy #$0000
@PxByte:
    lda $42
    sta.l $2119
    iny
    cpy #64
    bne @PxByte

    inc $41
    lda $41
    cmp #16
    bne @PixR

    inc $40
    lda $40
    cmp #14
    bne @PixC

    ; Write HUD tile 225 pixel data
    ; Tile 225 at VRAM word 225*64 = 14400
    rep #$20
    lda #14400
    sta.l $2116
    sep #$20
    ldy #$0000
@HudPx:
    lda #18              ; yellow
    sta.l $2119
    iny
    cpy #64
    bne @HudPx

    ; Screen on
    lda #$0F
    sta.l $2100

    plb
    plp
    rtl

;; -------------------------------------------------------
;; blitPlay -- per-column DMA, Noah's Ark style
;; VMAINC=$8C, 112 columns of 80 bytes each
;; Source: $7F:2000 (column-major screenbuffer)
;; -------------------------------------------------------
blitPlay:
    php
    phb
    phd

    sep #$20
    rep #$10

    ; Wait for VBlank
@WNV:
    lda.l $4212
    and #$80
    bne @WNV
@WV:
    lda.l $4212
    and #$80
    beq @WV

    ; Forced blank
    lda #$80
    sta.l $2100

    ; VMAINC=$8C: incr after $2119, address translation mode 3
    lda #$8C
    sta.l $2115

    ; DMA setup (constant)
    lda #$00
    sta.l $4300          ; DMA mode: 1 byte, A->B, increment
    lda #$19
    sta.l $4301          ; B-bus: $2119
    lda #FB_BANK
    sta.l $4304          ; source bank $7F

    ; Source address (auto-increments across columns)
    rep #$20
    lda #FB_BASE
    sta.l $4302

    ; Set DBR=0 for absolute addressing, DP=$4300 for DMA regs
    sep #$20
    pea $0000
    plb
    plb
    pea $4300
    pld

    ; Unrolled 112-column DMA (Noah's Ark style)
    ; X = DMA length (80), Y = DMA enable ($0001)
    rep #$30             ; 16-bit A, X, Y
    ldx #$0050           ; 80
    ldy #$0001           ; enable ch0

.define _COL 0
.REPT 112
    stx $05              ; $4305 = 80 (DMA length via DP)
    lda #(_COL * 128 + 8)
    sta $2116            ; VMADD (absolute, bank 0)
    sty $420B            ; trigger DMA (absolute, bank 0)
.REDEFINE _COL _COL + 1
.ENDR
.UNDEFINE _COL

    ; Display on
    lda #$07
    sta.l $2105
    lda #$01
    sta.l $212C
    lda #$0F
    sta.l $2100

    plp
    rtl

;; -------------------------------------------------------
;; clearFramebuffer -- DMA playback data to screenbuffer
;; Noah's Ark style: DMA from ROM → WRAM via WMDATA ($2180)
;; Much faster than CPU WMADD loop (~3ms vs ~27ms)
;; -------------------------------------------------------
clearFramebuffer:
    php
    sep #$20
    rep #$10
    ; Set WMADD to screenbuffer start ($7F:2000)
    lda #FB_BANK
    sta.l $2183
    rep #$20
    lda #FB_BASE
    sta.l $2181
    sep #$20
    ; DMA from ROM playback → WRAM via WMDATA
    lda #$00
    sta.l $4300          ; DMA mode: increment, A→B
    lda #$80             ; B-bus: WMDATA ($2180)
    sta.l $4301
    rep #$20
    lda #playback_bg
    sta.l $4302          ; source address
    sep #$20
    lda #:playback_bg
    sta.l $4304          ; source bank
    rep #$20
    lda #FB_SIZE         ; 8960 bytes
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B          ; trigger DMA
    plp
    rtl

;; -------------------------------------------------------
;; Kept for C compatibility (unused for now)
renderColumns:
    rtl

dmaFramebuffer:
    jmp blitPlay

;; -------------------------------------------------------
disableNMI:
    php
    sep #$20
    lda #$01
    sta.l $4200
    plp
    rtl

readJoypad:
    php
    sep #$20
@WA:
    lda.l $4212
    and #$01
    bne @WA
    rep #$20
    lda.l $4218
    sta.l tcc__r0
    plp
    rtl

IRQTrampoline:
    rti

zero_byte: .db 0

;; -------------------------------------------------------
;; Playback background: 112 columns × 80 rows (ceiling/floor)
;; Noah's Ark stores this in ROM, DMAs to screenbuffer each frame
;; -------------------------------------------------------
playback_bg:
.REPT 112
; 40 bytes ceiling color
.REPT 40
.db CEIL_COLOR
.ENDR
; 40 bytes floor color
.REPT 40
.db FLOOR_COLOR
.ENDR
.ENDR

.ends
