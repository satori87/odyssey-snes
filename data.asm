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
.define CLIPSHORTANGLE  5888

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
    phb                  ; +1 save DBR
    phd                  ; +2 save DP

    sep #$20
    rep #$10

    ; Noah's Ark approach: enter forced blank at scanline 208
    ; (bottom border = tile 0 = black, invisible blanking)
    ; Gives 16 extra scanlines before VBlank for DMA
@WScan:
    lda.l $2137          ; latch H/V counters
    lda.l $213D          ; V counter low byte (1st read)
    sta $10              ; save scanline
    lda.l $213D          ; V counter high (2nd read, resets flip-flop)
    lda $10
    cmp #208             ; bottom border starts at scanline ~208
    bcc @WScan           ; loop until scanline >= 208

    ; Forced blank (bottom border is already black = invisible)
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

    ; Set DBR=0 for absolute addressing, DP=$4300 for fast DMA regs
    pea $0000
    plb
    plb
    pea $4300
    pld

    ; Fast unrolled DMA: DP=$4300, DBR=0
    rep #$30
.ACCU 16
.INDEX 16
    ldx #$0050           ; 80 (DMA length)
    ldy #$0001           ; DMA enable ch0

.define _COL 0
.REPT 112
    stx $05              ; $4305 via DP (fast: 2 bytes, ~4 cycles)
    lda #(_COL * 128 + 8)
    sta $2116            ; VMADD via absolute (3 bytes, ~4 cycles)
    sty $420B            ; trigger via absolute (3 bytes, ~4 cycles)
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

    pld                  ; -2 restore DP
    plb                  ; -1 restore DBR
    plp                  ; -1 restore P
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
.ACCU 16
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
    rep #$20
.ACCU 16
    and #$00FF           ; zero-extend: clear hidden B byte before tay
    tay
    sep #$20
.ACCU 8
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
.ACCU 8
.INDEX 16

    ldx #$0000           ; column index
@Col:
    ; Quick check: skip if no wall
    lda.l colDrawEnd,x
    sec
    sbc.l colDrawStart,x
    beq @Next            ; drawEnd == drawStart → no wall

    ; Save pixel count and column index
    sta $18              ; count (8-bit)
    stx $16              ; save col index

    ; Read drawStart and wall color
    lda.l colDrawStart,x
    sta $10
    lda.l colWallColor,x
    sta $12

    ; Compute WMADD = columnstart[col] + drawStart
    rep #$20
.ACCU 16
    txa
    and #$00FF
    asl a
    tax
    lda.l columnstart,x
    sta $14
    sep #$20
.ACCU 8
    lda $14
    clc
    adc $10
    sta.l $2181          ; WMADDL
    lda $15
    adc #$00
    sta.l $2182          ; WMADDM

    ; Restore col index
    ldx $16

    ; Write pixels: load color ONCE, loop with sta only
    lda $18              ; count
    rep #$20
.ACCU 16
    and #$00FF           ; zero-extend (clear B register)
    tay
    sep #$20
.ACCU 8
    lda $12              ; wall color (loaded ONCE)
@Pix:
    sta.l $2180          ; 5 cycles
    dey                  ; 2 cycles
    bne @Pix             ; 3 cycles = 10 cycles/pixel (was 13)

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
    ; num = vx * 7 = vx * 8 - vx
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
    ; num was negative (vx left): screenX = 56 - quotient
    sta $46
    lda #56
    sec
    sbc $46
    rts

@NumPos:
    ; num positive (vx right): screenX = 56 + quotient
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
    clc
    adc #56
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
;; -------------------------------------------------------
;; PointToAngle_asm — (x,y) → 16-bit angle from player
;; Input: $38/$39 = worldX, $3A/$3B = worldY
;; Output: A = 16-bit angle (0=east, $4000=north, $8000=west, $C000=south)
;; Uses posX, posY globals. Clobbers $60-$66.
;; -------------------------------------------------------
PointToAngle_asm:
.ACCU 16
.INDEX 16
    ; dx = x - posX (positive = east)
    lda $38
    sec
    sbc.l posX
    sta $60              ; dx
    ; dy = posY - y (positive = north, since Y increases south in our map)
    lda.l posY
    sec
    sbc $3A
    sta $62              ; dy

    ; Octant-based lookup using tantoangle[512]
    ; ax = |dx|, ay = |dy|
    lda $60
    bpl @DxPos
    eor #$FFFF
    inc a
@DxPos:
    sta $64              ; ax = |dx|
    lda $62
    bpl @DyPos
    eor #$FFFF
    inc a
@DyPos:
    sta $66              ; ay = |dy|

    ; AngleFromSlope(y, x) = tantoangle[(y<<9)/x], clamped
    ; Reduce to avoid overflow: while y >= 128, shift both down
    ; Then call internal slope lookup

    lda $60              ; dx
    bpl @Oct_XPos
    ; dx < 0 (target is WEST)
    lda $62              ; dy
    bpl @Oct_XNeg_YPos
    ; dx < 0, dy < 0 (octant 4-5: southwest)
    lda $64              ; ax
    cmp $66              ; compare ax vs ay
    bcc @Oct5
    ; ax > ay → octant 4
    jsr @SlopeCalc       ; A = AngleFromSlope(ay, ax)
    clc
    adc #$8000           ; ANG180 + slope
    rts
@Oct5:
    ; ay >= ax → octant 5
    lda $64
    sta $66              ; swap: pass (ax, ay) as (y, x)
    lda.l posY           ; reload ay... actually just swap
    ; Simpler: call with ay,ax reversed
    jsr @SlopeCalcRev    ; A = AngleFromSlope(ax, ay)
    sta $68
    lda #$C000           ; ANG270
    sec
    sbc $68
    sec
    sbc #$0001           ; ANG270 - 1 - slope
    rts

@Oct_XNeg_YPos:
    ; dx < 0, dy >= 0 (octant 2-3: northwest)
    lda $64
    cmp $66
    bcc @Oct2
    ; ax > ay → octant 3
    jsr @SlopeCalc       ; AngleFromSlope(ay, ax)
    sta $68
    lda #$8000           ; ANG180
    sec
    sbc $68
    sec
    sbc #$0001           ; ANG180 - 1 - slope
    rts
@Oct2:
    ; ay >= ax → octant 2
    jsr @SlopeCalcRev    ; AngleFromSlope(ax, ay)
    clc
    adc #$4000           ; ANG90 + slope
    rts

@Oct_XPos:
    ; dx >= 0 (target is EAST)
    lda $62              ; dy
    bpl @Oct_XPos_YPos
    ; dx >= 0, dy < 0 (octant 7-8: southeast)
    lda $64
    cmp $66
    bcc @Oct7
    ; ax > ay → octant 8 (actually octant 0 mirrored)
    jsr @SlopeCalc       ; AngleFromSlope(ay, ax)
    sta $68
    lda #$0000
    sec
    sbc $68              ; negate = -slope (wraps to large unsigned)
    rts
@Oct7:
    ; ay >= ax → octant 7
    jsr @SlopeCalcRev
    clc
    adc #$C000           ; ANG270 + slope
    rts

@Oct_XPos_YPos:
    ; dx >= 0, dy >= 0 (octant 0-1: northeast)
    lda $64
    cmp $66
    bcc @Oct1
    ; ax > ay → octant 0
    jsr @SlopeCalc       ; AngleFromSlope(ay, ax)
    rts
@Oct1:
    ; ay >= ax → octant 1
    jsr @SlopeCalcRev    ; AngleFromSlope(ax, ay)
    sta $68
    lda #$4000           ; ANG90
    sec
    sbc $68
    sec
    sbc #$0001           ; ANG90 - 1 - slope
    rts

;; Internal: AngleFromSlope(ay=$66, ax=$64) — ay < ax
@SlopeCalc:
    lda $66              ; y = ay
    ldx $64              ; x = ax
    bra @DoSlope
;; Internal: AngleFromSlope(ax=$64, ay=$66) — ax < ay
@SlopeCalcRev:
    lda $64              ; y = ax
    ldx $66              ; x = ay
@DoSlope:
    ; idx = (y << 9) / x, clamped to 512
    ; Reduce both until y < 128 to prevent overflow
    stx $6A
@ReduceLoop:
    cmp #128
    bcc @ReduceDone
    lsr a
    lsr $6A              ; halve x too (unsigned)
    bra @ReduceLoop
@ReduceDone:
    ldx $6A
    beq @MaxAngle        ; x=0 → 90°
    ; y << 9
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a                ; y << 9
    ; Now divide by x using hardware
    sep #$20
.ACCU 8
    sta.l $4204          ; dividend low
    xba
    sta.l $4205          ; dividend high
    txa                  ; x low byte (x < 256 after reduction)
    sta.l $4206          ; trigger divide
    rep #$20
.ACCU 16
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    lda.l $4214          ; quotient = (y<<9)/x
    cmp #512
    bcc @IdxOk
    lda #512
@IdxOk:
    asl a                ; *2 for word index
    tax
    lda.l tantoangle,x
    rts
@MaxAngle:
    lda #$4000           ; 90°
    rts

;; -------------------------------------------------------
;; ScaleFromGlobalAngle_asm — Noah's per-column depth formula
;; Input: A = visangle (16-bit absolute angle)
;; Uses: $28=perpDist, $70=centerangle_fine, $2C=normalangle_fine
;; Returns: A = scale value from scaleatz
;; -------------------------------------------------------
ScaleFromGlobalAngle_asm:
.ACCU 16
.INDEX 16
    ; visangle_fine = visangle >> 5
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    sta $7E              ; visangle_fine

    ; anglea = (512 + (visangle_fine - centerangle_fine)) & 1023
    sec
    sbc $70              ; - centerangle_fine
    clc
    adc #512
    and #$03FF           ; & (FINEANGLES/2 - 1)
    asl a                ; *2 for word index
    tax
    lda.l finesine,x
    and #$00FF           ; sinea (1-255, fits in 8 bits)
    sta $74              ; temp: sinea

    ; angleb = (512 + (visangle_fine - normalangle_fine)) & 1023
    lda $7E              ; visangle_fine
    sec
    sbc $2C              ; - normalangle_fine
    clc
    adc #512
    and #$03FF
    asl a
    tax
    lda.l finesine,x
    and #$00FF           ; sineb
    sta $76              ; temp: sineb
    beq @MaxScale        ; sineb=0 → infinite depth → max scale

    ; tz = perpDist * sinea / sineb (Noah's exact formula)
    ; Step 1: ratio = (sinea << 8) / sineb (8.8 fixed-point ratio)
    lda $74              ; sinea (1-255)
    and #$00FF
    xba                  ; sinea << 8
    sep #$20
.ACCU 8
    sta.l $4204          ; dividend low
    xba
    sta.l $4205          ; dividend high
    lda $76              ; sineb
    sta.l $4206          ; trigger divide
    rep #$20
.ACCU 16
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    lda.l $4214          ; ratio = (sinea/sineb) in 8.8 format
    tay                  ; Y = ratio
    ; Step 2: tz = fp_mul(perpDist, ratio) = (perpDist * ratio) >> 8
    lda $28              ; A = perpDist
    jsr fp_mul_hw        ; result = perpDist * sinea / sineb
    bpl @NoOvf           ; positive = no overflow
    lda #MAXZ-1          ; overflow → max distance
@NoOvf:
    ; Look up scaleatz[tz]
    cmp #MAXZ
    bcc @TzOk
    lda #MAXZ-1
@TzOk:
    asl a
    tax
    lda.l scaleatz,x
    rts

@MaxScale:
    lda #$7FFF           ; max scale
    rts

;; -------------------------------------------------------
;; renderOneWall — Noah's angle-based approach
;; Input DP: $20/$22 = endpoint1 (x,y), $24/$26 = endpoint2 (x,y)
;;           $28 = perpDist, $2A = wall color
;; Uses PointToAngle_asm + viewangletox + scaleatz
;; -------------------------------------------------------
renderOneWall:
    php
    rep #$30
.ACCU 16
.INDEX 16

    ; --- Step 1: PointToAngle for both endpoints ---
    ; Endpoint 1: angle + depth
    lda $20
    sta $38
    lda $22
    sta $3A
    jsr PointToAngle_asm
    sta $4A              ; angle1

    ; Endpoint 2: angle + depth
    lda $24
    sta $38
    lda $26
    sta $3A
    jsr PointToAngle_asm
    sta $4C              ; angle2

    ; --- Step 2: Ensure angle1 > angle2 and check span ---
    ; Noah: angle1 is LEFT (larger), angle2 is RIGHT (smaller)
    ; If angle1 - angle2 >= $8000, swap and retry
    lda $4A
    sec
    sbc $4C
    sta $4E
    cmp #$8000
    bcc @SpanOk
    ; Swap angles and retry
    lda $4C
    ldx $4A
    sta $4A
    stx $4C
    lda $4A
    sec
    sbc $4C
    sta $4E
    cmp #$8000
    bcc @SpanOk
    jmp @Done            ; still invalid → fully behind
@SpanOk:

    ; --- Step 3: Make view-relative, clip to FOV ---
    ; centershort = playerAngle << 8
    lda.l playerAngle
    and #$00FF
    xba                  ; << 8 = centershort
    sta $50

    lda $4A
    sec
    sbc $50              ; a1 = angle1 - centershort (view-relative)
    sta $4A
    lda $4C
    sec
    sbc $50
    inc a                ; a2 = angle2 - centershort + 1 (non-inclusive)
    sta $4C

    ; Clip to clipshortangle
    lda $4A
    clc
    adc #CLIPSHORTANGLE
    cmp #CLIPSHORTANGLE*2
    bcc @NoClipL
    ; tspan > 2*clip → check if entirely off left
    sec
    sbc #CLIPSHORTANGLE*2
    cmp $4E
    bcc @ClipL
    jmp @Done            ; entirely off left
@ClipL:
    lda #CLIPSHORTANGLE
    sta $4A              ; clamp to left edge
@NoClipL:

    lda #CLIPSHORTANGLE
    sec
    sbc $4C
    cmp #CLIPSHORTANGLE*2
    bcc @NoClipR
    sec
    sbc #CLIPSHORTANGLE*2
    cmp $4E
    bcc @ClipR
    jmp @Done            ; entirely off right
@ClipR:
    lda #$0000
    sec
    sbc #CLIPSHORTANGLE
    sta $4C              ; clamp to right edge (-clipshortangle)
@NoClipR:

    ; --- Step 4: Convert angles to screen columns via viewangletox ---
    ; rw_x = viewangletox[(a1 + ANG90) >> ANGLETOFINESHIFT]
    lda $4A
    clc
    adc #$4000           ; + ANG90
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a                ; >> 5 (ANGLETOFINESHIFT)
    and #$03FF           ; mask to 1024 entries
    asl a                ; *2 for word index
    tax
    lda.l viewangletox,x
    sta $52              ; rw_x

    ; rw_stopx = viewangletox[(a2 + ANG90 - 1) >> ANGLETOFINESHIFT]
    lda $4C
    clc
    adc #$3FFF           ; + ANG90 - 1
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    and #$03FF
    asl a
    tax
    lda.l viewangletox,x
    sta $54              ; rw_stopx

    ; Check valid range
    lda $54
    cmp $52
    bne @HasCols2
    jmp @Done            ; rw_stopx == rw_x → less than 1 column
@HasCols2:

    ; --- Step 5: ScaleFromGlobalAngle at both columns (Noah's method) ---
    ; scale = scaleatz[ perpDist * sin(anglea) / sin(angleb) ]
    ; anglea = (512 + (vis_fine - center_fine)) & 1023
    ; angleb = (512 + (vis_fine - normal_fine)) & 1023
    ; $2C = normalangle_fine (set by caller)
    ; centerangle_fine = playerAngle * 8

    ; Precompute centerangle_fine
    lda.l playerAngle
    and #$00FF
    asl a
    asl a
    asl a                ; * 8
    sta $70              ; centerangle_fine

    ; ScaleFromGlobalAngle for start column (angle a1)
    ; visangle = a1 + centershort (absolute)
    lda $4A              ; a1 (view-relative)
    clc
    adc $50              ; + centershort = absolute angle
    jsr ScaleFromGlobalAngle_asm
    sta $74              ; scale1

    ; ScaleFromGlobalAngle for stop column (angle a2)
    lda $4C              ; a2 (view-relative, non-inclusive)
    clc
    adc $50              ; + centershort
    jsr ScaleFromGlobalAngle_asm
    sta $76              ; scale2

    ; scale_step = (scale2 - scale1) / col_count
    lda $76
    sec
    sbc $74              ; scale_diff
    sta $78
    lda $54              ; rw_stopx
    sec
    sbc $52              ; - rw_x = col_count
    and #$00FF
    sta $7A
    bne @HasCols3
    jmp @Done
@HasCols3:
    ; Signed divide
    lda $78              ; scale_diff
    bpl @SdPos
    eor #$FFFF
    inc a
    sep #$20
.ACCU 8
    sta.l $4204
    xba
    sta.l $4205
    lda $7A              ; col_count
    sta.l $4206
    rep #$20
.ACCU 16
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    lda.l $4214
    eor #$FFFF
    inc a                ; negate
    sta $7C              ; scale_step (negative)
    bra @StepOk
@SdPos:
    sep #$20
.ACCU 8
    sta.l $4204
    xba
    sta.l $4205
    lda $7A
    sta.l $4206
    rep #$20
.ACCU 16
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    lda.l $4214
    sta $7C              ; scale_step
@StepOk:

    ; --- Step 6: Fill columns with per-column height ---
    lda $52              ; rw_x
    and #$00FF
    tax
    lda $54              ; rw_stopx
    and #$00FF
    sta $7E              ; stop
    lda $74              ; current_scale = scale1
    sta $7A              ; reuse $7A for current_scale
    sep #$20
.ACCU 8
@FillCol:
    lda.l colDrawn,x
    bne @SkipCol2
    lda #$01
    sta.l colDrawn,x
    ; Compute wallHeight from current_scale
    rep #$20
.ACCU 16
    lda $7A              ; current_scale
    xba                  ; >> 8
    and #$00FF
    cmp #80
    bcc @NcH3
    lda #80
@NcH3:
    lsr a                ; halfH
    sta $4E
    lda #40
    sec
    sbc $4E
    sep #$20
.ACCU 8
    sta.l colDrawStart,x
    lda #40
    clc
    adc $4E
    cmp #80
    bcc @NcE3
    lda #80
@NcE3:
    sta.l colDrawEnd,x
    lda $2A
    sta.l colWallColor,x
@SkipCol2:
    ; Advance scale
    rep #$20
.ACCU 16
    lda $7A
    clc
    adc $7C              ; + scale_step
    sta $7A
    sep #$20
.ACCU 8
    inx
    rep #$20
.ACCU 16
    txa
    cmp $7E
    sep #$20
.ACCU 8
    bcc @FillCol
@DoneFill:
@Done:
    plp
    rts                  ; called via JSR from renderAllWalls (same bank)

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

    ; === All 8 walls via jsr renderOneWall ===
.ACCU 16
.INDEX 16

    ; --- East wall (col=9, X=2304): player east (posX < 2304) ---
    lda.l posX
    cmp #2304
    bcs @SkipE
    lda #2304
    sec
    sbc.l posX
    sta $28
    lda #2304
    sta $20
    lda #256
    sta $22
    lda #2304
    sta $24
    lda #2304
    sta $26
    sep #$20
    lda #5
    sta $2A
    rep #$20
    lda #1024
    sta $2C
    jsr renderOneWall
@SkipE:

    ; --- West wall (col=1, X=256): player east (posX > 256) ---
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
    lda #0
    sta $2C
    jsr renderOneWall
@SkipW:

    ; --- South wall (row=1, Y=256): player south (posY > 256) ---
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
    lda #1536
    sta $2C
    jsr renderOneWall
@SkipS:

    ; --- North wall (row=9, Y=2304): player north (posY < 2304) ---
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
    lda #512
    sta $2C
    jsr renderOneWall
@SkipN:

    ; --- Pillar east (col=6, X=1536): player east (posX > 1536) ---
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
    lda #0
    sta $2C
    jsr renderOneWall
@SkipPE:

    ; --- Pillar west (col=4, X=1024): player west (posX < 1024) ---
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
    lda #1024
    sta $2C
    jsr renderOneWall
@SkipPW:

    ; --- Pillar south (row=6, Y=1536): player south (posY > 1536) ---
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
    lda #1536
    sta $2C
    jsr renderOneWall
@SkipPS:

    ; --- Pillar north (row=4, Y=1024): player north (posY < 1024) ---
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
    lda #512
    sta $2C
    jsr renderOneWall
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
