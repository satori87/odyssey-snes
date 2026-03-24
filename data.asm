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
.define MAXZ            8192

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

    ; Unrolled 112-column DMA — all long addressing, no DP/DBR tricks
    rep #$20
.ACCU 16

.define _COL 0
.REPT 112
    lda #80
    sta.l $4305          ; DMA length
    lda #(_COL * 128 + 8)
    sta.l $2116          ; VMADD
    lda #$0001
    sta.l $420B          ; trigger DMA (also writes $00 to $420C)
.REDEFINE _COL _COL + 1
.ENDR
.UNDEFINE _COL

    ; Display on
    sep #$20
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
;; testWMADD -- write a single byte to screenbuffer via WMADD
;; Tests if ANY WMADD write corrupts the display
;; -------------------------------------------------------
testWMADD:
    php
    sep #$20
    rep #$10
    ; WMBANK already $7F from clearFramebuffer DMA
    ; Write all 112 columns × wall portion (drawStart=20, drawEnd=60)
    ; Approach: for each column, set WMADD to base+20, write 40 wall bytes

    ldx #$0000           ; column index
@Col:
    ; Read from C arrays (test if this causes corruption)
    lda.l colDrawStart,x
    sta $10              ; drawStart from array
    lda.l colDrawEnd,x
    sta $11              ; drawEnd from array
    lda.l colWallColor,x
    sta $12              ; wallColor from array

    ; WMADD = columnstart[col] + drawStart
    phx
    rep #$20
    txa
    and #$00FF
    asl a
    tax
    lda.l columnstart,x
    sep #$20
    clc
    adc $10              ; + drawStart (8-bit add to low byte)
    sta.l $2181          ; WMADDL
    rep #$20
    lda.l columnstart,x
    sep #$20
    xba                  ; high byte of column base
    adc #$00             ; + carry
    sta.l $2182          ; WMADDM
    plx

    ; Write (drawEnd - drawStart) pixels
    lda $11
    sec
    sbc $10
    beq @Next
    tay
@Pix:
    lda $12
    sta.l $2180
    dey
    bne @Pix

@Next:
    inx
    cpx #112
    bne @Col

    plp
    rtl

;; -------------------------------------------------------
;; renderColumns -- write wall portions to screenbuffer
;; Reads colDrawStart[112], colDrawEnd[112], colWallColor[112]
;; Only overwrites the wall band (ceiling/floor from DMA clear)
;; WMBANK ($2183) already set by clearFramebuffer DMA
;; -------------------------------------------------------
renderColumns:
    php
    sep #$20
    rep #$10

    ldx #$0000           ; column index
@Col:
    ; Read column data from C arrays
    lda.l colDrawStart,x
    sta $10
    lda.l colDrawEnd,x
    sta $11
    lda.l colWallColor,x
    sta $12

    ; WMADD = columnstart[col] + drawStart
    phx
    rep #$20
    txa
    and #$00FF
    asl a
    tax
    lda.l columnstart,x
    sep #$20
    clc
    adc $10              ; low byte + drawStart
    sta.l $2181          ; WMADDL
    rep #$20
    lda.l columnstart,x
    sep #$20
    xba                  ; high byte of column base
    adc #$00             ; + carry from low add
    sta.l $2182          ; WMADDM
    plx

    ; Write (drawEnd - drawStart) pixels
    lda $11
    sec
    sbc $10
    beq @Next
    tay
@Pix:
    lda $12
    sta.l $2180
    dey
    bne @Pix

@Next:
    inx
    cpx #112
    bne @Col

    plp
    rtl

;; Column start address table: columnstart[col] = FB_BASE + col*80
columnstart:
.define _CS 0
.REPT 112
.dw FB_BASE + _CS
.REDEFINE _CS _CS + 80
.ENDR
.UNDEFINE _CS

;; -------------------------------------------------------
;; initColumnArrays -- clear column arrays (no wall)
;; -------------------------------------------------------
initColumnArrays:
    php
    sep #$20
    rep #$10
    ldx #$0000
@L:
    lda #40
    sta.l colDrawStart,x
    sta.l colDrawEnd,x
    lda #$00
    sta.l colWallColor,x
    sta.l colDrawn,x
    inx
    cpx #112
    bne @L
    plp
    rtl

;; -------------------------------------------------------
;; renderOneWall -- project a wall segment, fill column arrays
;;
;; Input (DP scratch, set by caller):
;;   $20/$21 = wall endpoint 1 X (s16, 8.8 fixed)
;;   $22/$23 = wall endpoint 1 Y
;;   $24/$25 = wall endpoint 2 X
;;   $26/$27 = wall endpoint 2 Y
;;   $28/$29 = perpendicular distance (u16, 8.8)
;;   $2A     = wall color (u8)
;;
;; Uses player state: posX, posY, dirX, dirY (C globals)
;; Uses colDrawn[] for front-to-back coverage
;; -------------------------------------------------------

;; Helper: fp_mul_hw — 8.8 fixed multiply using hardware $4202/$4203
;; Input: A = multiplicand (s16), Y = multiplier (s16)
;; Output: A = (A * Y) >> 8 (s16)
;; Clobbers: $30-$35
fp_mul_hw:
.ACCU 16
.INDEX 16
    ; Handle signs
    sta $30              ; save A
    sty $32              ; save Y
    stz $34              ; neg flag = 0
    lda $30
    bpl @APos
    eor #$FFFF
    inc a                ; negate A
    sta $30
    lda #$0001
    sta $34              ; neg = 1
@APos:
    lda $32
    bpl @BPos
    eor #$FFFF
    inc a
    sta $32
    lda $34
    eor #$0001
    sta $34              ; flip neg
@BPos:
    ; Now $30 = |A| (u16), $32 = |Y| (u16), $34 = neg flag
    ; result = (ah*bh)<<8 + ah*bl + al*bh + (al*bl)>>8
    sep #$20
    lda $31              ; ah
    sta.l $4202
    lda $33              ; bh
    sta.l $4203
    rep #$20
    nop                  ; wait for multiply
    lda.l $4216          ; ah*bh
    xba                  ; <<8 (swap bytes)
    and #$FF00           ; keep only high part of <<8
    sta $36              ; partial result

    sep #$20
    lda $31              ; ah
    sta.l $4202
    lda $32              ; bl
    sta.l $4203
    rep #$20
    nop
    lda.l $4216          ; ah*bl
    clc
    adc $36
    sta $36

    sep #$20
    lda $30              ; al
    sta.l $4202
    lda $33              ; bh
    sta.l $4203
    rep #$20
    nop
    lda.l $4216          ; al*bh
    clc
    adc $36
    sta $36

    sep #$20
    lda $30              ; al
    sta.l $4202
    lda $32              ; bl
    sta.l $4203
    rep #$20
    nop
    lda.l $4216          ; al*bl
    xba                  ; >>8
    and #$00FF
    clc
    adc $36              ; total result
    sta $36

.ACCU 16
    ; Apply sign
    lda $34
    beq @NoNeg
    lda $36
    eor #$FFFF
    inc a
    sta $36
@NoNeg:
    lda $36
    rts

;; projectX_asm — project world point to screen column
;; Input: $38/$39 = worldX (s16), $3A/$3B = worldY (s16)
;; Output: A = screen column (s16), or -999 if behind camera
;; Uses: fp_mul_hw, posX, posY, dirX, dirY
projectX_asm:
.ACCU 16
.INDEX 16
    ; dx = worldX - posX
    rep #$20
    lda $38
    sec
    sbc.l posX
    sta $3C              ; dx

    ; dy = worldY - posY
    lda $3A
    sec
    sbc.l posY
    sta $3E              ; dy

    ; vz = fp_mul(dx, dirX) + fp_mul(dy, dirY)
    lda.l dirX
    tay                  ; Y = dirX
    lda $3C              ; A = dx
    jsr fp_mul_hw
    sta $40              ; fp_mul(dx, dirX)

    lda.l dirY
    tay                  ; Y = dirY
    lda $3E              ; A = dy
    jsr fp_mul_hw        ; fp_mul(dy, dirY)
    clc
    adc $40
    sta $40              ; vz

    ; if vz < 16, behind camera
    cmp #$0010
    bcs @InFront
    lda #$FC19           ; -999
    rts
@InFront:

    ; vx = fp_mul(dy, dirX) - fp_mul(dx, dirY)
    lda.l dirX
    tay                  ; Y = dirX
    lda $3E              ; A = dy
    jsr fp_mul_hw
    sta $42              ; fp_mul(dy, dirX)

    lda.l dirY
    tay                  ; Y = dirY
    lda $3C              ; A = dx
    jsr fp_mul_hw        ; fp_mul(dx, dirY)
    sta $44
    lda $42
    sec
    sbc $44
    sta $42              ; vx

    ; screenX = 56 - (vx * 7) / (vz / 8)
    ; vz8 = vz >> 3
    lda $40
    lsr a
    lsr a
    lsr a
    sta $44              ; vz8
    beq @Clip
    ; num = vx * 7
    lda $42
    asl a                ; *2
    adc $42              ; *3 (approximate, carry might be set)
    asl a                ; *6
    sec                  ; fix: clear approach
    ; Redo: vx*7 = vx*8 - vx
    lda $42
    asl a
    asl a
    asl a                ; vx*8
    sec
    sbc $42              ; vx*8 - vx = vx*7
    sta $46              ; num

    ; Unsigned divide: |num| / vz8
.ACCU 16
    bpl @NumPos
    eor #$FFFF
    inc a                ; negate
    sta $46
    ; Divide
    sep #$20
    lda $45              ; num high byte
    sta.l $4204
    lda $44              ; WAIT: need to use $4204/$4205 for dividend, $4206 for divisor
    ; SNES hardware divide: $4204=dividend_lo, $4205=dividend_hi, $4206=divisor (triggers)
    ; Result after 16 cycles: $4214=quotient, $4216=remainder
    rep #$20
    lda $46              ; |num| (unsigned)
    sep #$20
    sta.l $4204          ; dividend low
    xba
    sta.l $4205          ; dividend high
    lda $44              ; vz8 low byte (vz8 < 256 for reasonable distances)
    sta.l $4206          ; divisor — triggers divide
    rep #$20
    nop                  ; wait ~16 cycles
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    lda.l $4214          ; quotient
    ; num was negative: screenX = 56 + quotient
    clc
    adc #56
    rts

@NumPos:
    ; num positive: divide
    sep #$20
    lda $46              ; num low
    sta.l $4204
    lda $47              ; num high
    sta.l $4205
    lda $44              ; vz8 low byte
    sta.l $4206
    rep #$20
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    lda.l $4214          ; quotient
    ; screenX = 56 - quotient
    sta $46
    lda #56
    sec
    sbc $46
    rts

@Clip:
    lda #$FC19           ; -999 (vz8 == 0)
    rts

;; -------------------------------------------------------
;; renderOneWall -- main entry point
;; Inputs in DP $20-$2A (set by caller before jsl)
;; -------------------------------------------------------
renderOneWall:
    php
    rep #$30             ; 16-bit A, X, Y
.ACCU 16
.INDEX 16

    ; Project endpoint 1
    lda $20
    sta $38
    lda $22
    sta $3A
    jsr projectX_asm
    sta $4A              ; sx1

    ; Project endpoint 2
    lda $24
    sta $38
    lda $26
    sta $3A
    jsr projectX_asm
    sta $4C              ; sx2

    ; Ensure sx1 <= sx2 (swap if needed)
    lda $4A
    cmp $4C
    bcc @NoSwap
    beq @NoSwap
    lda $4C
    ldx $4A
    sta $4A
    stx $4C
@NoSwap:

    ; Clip to screen
    lda $4C
    cmp #$0001           ; sx2 <= 0?
    bpl @NotBehind
    jmp @Done
@NotBehind:
    beq @Done2
    bra @ChkLeft
@Done2:
    jmp @Done
@ChkLeft:
    lda $4A
    cmp #112             ; sx1 >= 112?
    bmi @Visible
    jmp @Done
@Visible:

    ; Clamp
    lda $4A
    bpl @NoClampL
    stz $4A              ; sx1 = 0
@NoClampL:
    lda $4C
    cmp #112
    bcc @NoClampR
    lda #112
    sta $4C
@NoClampR:

    ; Wall height from scaleatz[perpDist]
    lda $28              ; perpDist
    cmp #MAXZ
    bcc @NoCZ
    lda #MAXZ-1
@NoCZ:
    asl a                ; *2 for word index
    tax
    lda.l scaleatz,x     ; scale (u16)
    xba                  ; >>8 = wallHeight
    and #$00FF
    cmp #80
    bcc @NoClampH
    lda #80
@NoClampH:
    ; halfH = wallHeight / 2
    lsr a
    sta $4E              ; halfH
    ; drawStart = 40 - halfH
    lda #40
    sec
    sbc $4E
    sep #$20
    sta $50              ; drawStart (u8)
    ; drawEnd = 40 + halfH
    lda #40
    clc
    adc $4E
    cmp #80
    bcc @NoClampE
    lda #80
@NoClampE:
    sta $51              ; drawEnd (u8)

    ; Fill column arrays for sx1..sx2
    rep #$20
    lda $4A              ; sx1
    and #$00FF
    tax                  ; X = column index
    lda $4C              ; sx2
    and #$00FF
    sta $52              ; stop column
    sep #$20
@FillCol:
    lda.l colDrawn,x
    bne @SkipCol         ; already drawn (front-to-back)
    lda #$01
    sta.l colDrawn,x
    lda $50
    sta.l colDrawStart,x
    lda $51
    sta.l colDrawEnd,x
    lda $2A              ; wall color
    sta.l colWallColor,x
@SkipCol:
    inx
    rep #$20
    txa
    cmp $52
    sep #$20
    bcc @FillCol

@Done:
    plp
    rtl

;; colDrawn: 112 bytes in RAM (allocated in .ramsection at end of file)

;; -------------------------------------------------------
;; renderAllWalls -- project all 8 walls for the 10x10 map
;; Calls initColumnArrays then renderOneWall for each wall
;; Uses posX/posY from C globals
;; -------------------------------------------------------
renderAllWalls:
    php
    rep #$30
.ACCU 16
.INDEX 16
    ; Init arrays (inlined, no jsl)
    sep #$20
    ldx #$0000
@Init2:
    lda #40
    sta.l colDrawStart,x
    sta.l colDrawEnd,x
    lda #$00
    sta.l colWallColor,x
    sta.l colDrawn,x
    inx
    cpx #112
    bne @Init2
    rep #$20

    ; DEBUG: marker BEFORE projection — skip everything
    sep #$20
    ldx #$0020
@DbgPre:
    lda #5
    sta.l colDrawStart,x
    lda #75
    sta.l colDrawEnd,x
    lda #17              ; floor green — KNOWN visible color
    sta.l colWallColor,x
    inx
    cpx #$0060
    bne @DbgPre
    rep #$20
    jmp @SkipPN

    ; === Project east wall (X=2304, Y=256..2304) ===
    ; perpDist = 2304 - posX
    lda #2304
    sec
    sbc.l posX
    sta $28              ; perpDist
    cmp #$0001
    bcs @NotBehind0
    jmp @SkipPN          ; behind us
@NotBehind0:

    ; Project endpoint 1: (2304, 256)
    lda #2304
    sta $38
    lda #256
    sta $3A
    jsr projectX_asm
    sta $4A              ; sx1

    ; Project endpoint 2: (2304, 2304)
    lda #2304
    sta $38
    lda #2304
    sta $3A
    jsr projectX_asm
    sta $4C              ; sx2

    ; Sort & clamp
    lda $4A
    cmp $4C
    bcc @NoSwp
    beq @NoSwp
    lda $4C
    ldx $4A
    sta $4A
    stx $4C
@NoSwp:
    lda $4C
    cmp #$0001
    bpl @NotBhd
    jmp @SkipPN
@NotBhd:
    lda $4A
    cmp #112
    bmi @Vis
    jmp @SkipPN
@Vis:
    lda $4A
    bpl @NcL
    stz $4A
@NcL:
    lda $4C
    cmp #112
    bcc @NcR
    lda #112
    sta $4C
@NcR:

    ; Wall height from scaleatz
    lda $28
    cmp #MAXZ
    bcc @NcZ
    lda #MAXZ-1
@NcZ:
    asl a
    tax
    lda.l scaleatz,x
    xba
    and #$00FF
    cmp #80
    bcc @NcH
    lda #80
@NcH:
    lsr a                ; halfH
    sta $4E
    lda #40
    sec
    sbc $4E
    sep #$20
    sta $50              ; drawStart
    lda #40
    clc
    adc $4E
    cmp #80
    bcc @NcE
    lda #80
@NcE:
    sta $51              ; drawEnd

    ; Fill columns sx1..sx2
    rep #$20
    lda $4A
    and #$00FF
    tax
    lda $4C
    and #$00FF
    sta $52
    sep #$20
@Fcol:
    lda.l colDrawn,x
    bne @Fskp
    lda #$01
    sta.l colDrawn,x
    lda $50
    sta.l colDrawStart,x
    lda $51
    sta.l colDrawEnd,x
    lda #18              ; wall color = YELLOW (same as HUD, definitely visible)
    sta.l colWallColor,x
@Fskp:
    inx
    rep #$20
    txa
    cmp $52
    sep #$20
    bcc @Fcol

    ; DEBUG: yellow stripe at col 56 to prove we reached here
    sep #$20
    ldx #$0038
    lda #5
    sta.l colDrawStart,x
    lda #75
    sta.l colDrawEnd,x
    lda #18
    sta.l colWallColor,x
    rep #$20
    jmp @SkipPN

    ; === East outer wall at col=9 (X=2304): visible when posX < 2304 ===
    lda.l posX
    cmp #2304
    bcs @SkipE
    ; perpDist = 2304 - posX
    lda #2304
    sec
    sbc.l posX
    sta $28              ; perpDist
    ; endpoints: (2304, 256) to (2304, 2304)
    lda #2304
    sta $20              ; x1
    lda #256
    sta $22              ; y1
    lda #2304
    sta $24              ; x2
    lda #2304
    sta $26              ; y2
    sep #$20
    lda #4               ; wall color
    sta $2A
    rep #$20
    jsl renderOneWall
@SkipE:

    ; === West outer wall at col=1 (X=256): visible when posX > 256 ===
    lda.l posX
    cmp #257
    bcc @SkipW
    lda.l posX
    sec
    sbc #256
    sta $28
    lda #256
    sta $20
    lda #256
    sta $22
    lda #256
    sta $24
    lda #2304
    sta $26
    sep #$20
    lda #4
    sta $2A
    rep #$20
    jsl renderOneWall
@SkipW:

    ; === South outer wall at row=1 (Y=256): visible when posY > 256 ===
    lda.l posY
    cmp #257
    bcc @SkipS
    lda.l posY
    sec
    sbc #256
    sta $28
    lda #256
    sta $20
    lda #256
    sta $22
    lda #2304
    sta $24
    lda #256
    sta $26
    sep #$20
    lda #5
    sta $2A
    rep #$20
    jsl renderOneWall
@SkipS:

    ; === North outer wall at row=9 (Y=2304): visible when posY < 2304 ===
    lda.l posY
    cmp #2304
    bcs @SkipN
    lda #2304
    sec
    sbc.l posY
    sta $28
    lda #256
    sta $20
    lda #2304
    sta $22
    lda #2304
    sta $24
    lda #2304
    sta $26
    sep #$20
    lda #5
    sta $2A
    rep #$20
    jsl renderOneWall
@SkipN:

    ; === Pillar east face at col=6 (X=1536): visible when posX > 1536 ===
    lda.l posX
    cmp #1537
    bcc @SkipPE
    lda.l posX
    sec
    sbc #1536
    sta $28
    lda #1536
    sta $20
    lda #1024
    sta $22
    lda #1536
    sta $24
    lda #1536
    sta $26
    sep #$20
    lda #6
    sta $2A
    rep #$20
    jsl renderOneWall
@SkipPE:

    ; === Pillar west face at col=4 (X=1024): visible when posX < 1024 ===
    lda.l posX
    cmp #1024
    bcs @SkipPW
    lda #1024
    sec
    sbc.l posX
    sta $28
    lda #1024
    sta $20
    lda #1024
    sta $22
    lda #1024
    sta $24
    lda #1536
    sta $26
    sep #$20
    lda #6
    sta $2A
    rep #$20
    jsl renderOneWall
@SkipPW:

    ; === Pillar south face at row=6 (Y=1536): visible when posY > 1536 ===
    lda.l posY
    cmp #1537
    bcc @SkipPS
    lda.l posY
    sec
    sbc #1536
    sta $28
    lda #1024
    sta $20
    lda #1536
    sta $22
    lda #1536
    sta $24
    lda #1536
    sta $26
    sep #$20
    lda #7
    sta $2A
    rep #$20
    jsl renderOneWall
@SkipPS:

    ; === Pillar north face at row=4 (Y=1024): visible when posY < 1024 ===
    lda.l posY
    cmp #1024
    bcs @SkipPN
    lda #1024
    sec
    sbc.l posY
    sta $28
    lda #1024
    sta $20
    lda #1024
    sta $22
    lda #1536
    sta $24
    lda #1024
    sta $26
    sep #$20
    lda #7
    sta $2A
    rep #$20
    jsl renderOneWall
@SkipPN:

    plp
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
; 40 bytes ceiling
.REPT 40
.db CEIL_COLOR
.ENDR
; 40 bytes floor
.REPT 40
.db FLOOR_COLOR
.ENDR
.ENDR

.ends

.ramsection ".coldrawn" slot 2 bank 126
colDrawn dsb 112
.ends
