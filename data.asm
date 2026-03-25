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
    ; Load dark palette at entries 32-47 (for N/S wall darkening)
    lda #32
    sta.l $2121
    ldx #$0000
@DkPal:
    lda.l dark_palette,x
    sta.l $2122
    inx
    cpx #$0020           ; 16 colors × 2 bytes
    bne @DkPal

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

    ; Two-phase wait: guarantee DMA starts at scanline 208 exactly.
    ; Phase 1: if we're past 208, wait until V counter wraps to < 208
    ; Phase 2: then wait until scanline reaches 208
    ; This ensures consistent timing regardless of when game loop finishes.
@WPre:
    lda.l $2137          ; latch H/V counters
    lda.l $213D          ; V counter low byte
    sta $10
    lda.l $213D          ; high byte (reset flip-flop)
    lda $10
    cmp #208
    bcs @WPre            ; loop while scan >= 208 (wait for next frame)
@WScan:
    lda.l $2137          ; latch
    lda.l $213D          ; V counter low byte
    sta $10
    lda.l $213D          ; high byte (reset flip-flop)
    lda $10
    cmp #208             ; bottom border (tile row 13 = black)
    bcc @WScan           ; wait until scan >= 208

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
;; renderColumns -- textured wall rendering
;; Reads colDrawStart/End, colTexCol, colFullH, colWallColor (texID)
;; For each column: copies 32-byte texture column to DP $B0-$CF,
;; then vertically scales texture pixels to wall height.
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
    bne @HasWall
    jmp @Next            ; no wall pixels
@HasWall:
    sta $18              ; wallPixels = drawEnd - drawStart
    stx $16              ; save col index

    ; Read parameters
    lda.l colDrawStart,x
    sta $10              ; drawStart
    lda.l colFullH,x
    sta $13              ; fullH (unclamped, 0-255)
    bne @HasFullH
    jmp @NextR           ; fullH == 0 → skip
@HasFullH:
    lda.l colTexCol,x
    sta $19              ; texCol (0-31)
    lda.l colWallColor,x
    sta $1A              ; texID (1 or 2, with possible $80 dark flag)

    ; --- Copy 32-byte texture column to DP $B0-$CF ---
    ; texOffset = tex_ptrs[texID & $7F] + texCol * 32
    rep #$20
.ACCU 16
    lda $1A
    and #$007F           ; mask off dark flag
    asl a                ; *2 for word index
    tax
    lda.l tex_ptrs,x     ; texture base offset within tex_base
    sta $1C
    lda $19
    and #$00FF
    asl a
    asl a
    asl a
    asl a
    asl a                ; texCol * 32
    clc
    adc $1C              ; + texture base offset
    tax                  ; X = byte offset into tex_base
    sep #$20
.ACCU 8
    ldy #$0000
@CopyTex:
    lda.l tex_base,x
    sta $B0,y            ; DP buffer $B0-$CF
    inx
    iny
    cpy #32
    bne @CopyTex

    ; Dark side: add 32 to each pixel (shift to dark palette 32-47)
    ldx $16              ; restore col index
    lda.l colWallColor,x
    and #$80             ; dark flag?
    beq @NoDarken
    ldy #$0000
@DarkenLoop:
    lda $B0,y
    beq @SkipDk          ; don't darken color 0 (black)
    clc
    adc #32              ; shift to dark palette
@SkipDk:
    sta $B0,y
    iny
    cpy #32
    bne @DarkenLoop
@NoDarken:

    ; --- Set WMADD = columnstart[col] + drawStart ---
    ldx $16              ; restore col index
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
    adc $10              ; + drawStart
    sta.l $2181          ; WMADDL
    lda $15
    adc #$00
    sta.l $2182          ; WMADDM

    ; --- Choose rendering path ---
    ; If fullH <= 80: use compiled scaler (fast, no per-pixel loop)
    ; If fullH > 80: fall back to per-pixel loop (wall taller than screen)
    lda $13              ; fullH
    cmp #81
    bcs @SlowPath

    ; --- FAST PATH: Compiled scaler (fullH 1-80) ---
    ; No clamping needed — fullH == visibleH
    ; DP $B0-$CF has texture column, scaler reads from it directly
    rep #$30
.ACCU 16
.INDEX 16
    lda $13
    and #$00FF
    asl a                ; *2 for word table index
    tax
    jsl _call_scaler     ; trampoline in scaler bank (reads X for ptr)
    sep #$20
    rep #$10
.ACCU 8
.INDEX 16
    jmp @NextR

@SlowPath:
    ; --- SLOW PATH: Per-pixel loop for walls taller than screen ---
    ; Compute texStep = 8192 / fullH
    rep #$20
.ACCU 16
    lda #$2000           ; 8192
    sep #$20
.ACCU 8
    sta.l $4204
    xba
    sta.l $4205
    lda $13              ; fullH
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
    lda.l $4214          ; texStep
    sta $1E

    ; texOfs = skippedRows * texStep
    lda $13
    and #$00FF
    lsr a                ; fullH/2
    sta $4E
    lda #40
    sec
    sbc $4E              ; idealStart
    sta $4E
    lda $10
    and #$00FF
    sec
    sbc $4E              ; skippedRows
    and #$00FF
    xba                  ; << 8
    tay
    lda $1E
    jsr fp_mul_hw        ; texOfs = skippedRows * texStep
    sta $20

    ; Per-pixel texture scaling loop
    sep #$30
.ACCU 8
.INDEX 8
    ldy $18              ; pixel count
@Pix:
    ldx $21              ; texRow = texOfs high byte
    lda $B0,x            ; texture pixel from DP buffer
    sta.l $2180          ; write to screenbuffer
    lda $20
    clc
    adc $1E
    sta $20
    lda $21
    adc $1F
    and #$1F             ; wrap to 0-31
    sta $21
    dey
    bne @Pix

    rep #$10
.INDEX 16
@NextR:
    ldx $16              ; restore col index
@Next:
    inx
    cpx #112
    beq @AllDone
    jmp @Col
@AllDone:
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
    ; num was negative: screenX = 56 + quotient
    clc
    adc #56
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
    ; num positive: screenX = 56 - quotient
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
    jsr @SlopeCalcRev    ; AngleFromSlope(ax, ay) — $64/$66 already correct
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
    ; y in A, x in X. Need: y < 128 AND x < 256 for hardware math.
    sta $68              ; save y
    stx $6A              ; save x
@ReduceBoth:
    ; Check if y >= 128 OR x >= 256 → need to reduce both
    lda $68
    cmp #128
    bcs @DoReduce
    lda $6A
    cmp #256
    bcc @BothOk          ; y < 128 AND x < 256 → done
@DoReduce:
    lsr $68              ; halve y
    lsr $6A              ; halve x
    bra @ReduceBoth
@BothOk:
    lda $6A
    beq @MaxAngle        ; x = 0 → 90°
    tax                  ; X = x (< 256)
    lda $68              ; A = y (< 128)
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
    sta $56              ; visangle_fine (NOT $7E — that's used for stop column!)

    ; anglea = (512 + (visangle_fine - centerangle_fine)) & 1023
    sec
    sbc $70              ; - centerangle_fine
    clc
    adc #512
    and #$03FF           ; & (FINEANGLES/2 - 1)
    asl a                ; *2 for word index
    tax
    lda.l finesine,x
    and #$00FF           ; sinea (1-255)
    sta $58              ; sinea (internal scratch — NOT $74!)

    ; angleb = (512 + (visangle_fine - normalangle_fine)) & 1023
    lda $56              ; visangle_fine
    sec
    sbc $2C              ; - normalangle_fine
    clc
    adc #512
    and #$03FF
    asl a
    tax
    lda.l finesine,x
    and #$00FF           ; sineb
    sta $5A              ; sineb (internal scratch — NOT $76!)
    beq @MaxScale

    ; tz = perpDist * sinea / sineb (Noah's exact formula)
    ; Step 1: ratio = (sinea << 8) / sineb (8.8 fixed-point ratio)
    lda $58              ; sinea (internal scratch)
    and #$00FF
    xba                  ; sinea << 8
    sep #$20
.ACCU 8
    sta.l $4204          ; dividend low
    xba
    sta.l $4205          ; dividend high
    lda $5A              ; sineb (internal scratch)
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
    sbc $50              ; a2 = angle2 - centershort
    inc a                ; angle2++ (non-inclusive, matching Noah P_DrawSeg)
    sta $4C

    ; Simple clip to [-clipshortangle, +clipshortangle]
    lda $4A
    clc
    adc #CLIPSHORTANGLE
    cmp #CLIPSHORTANGLE*2
    bcc @NoClipL
    sec
    sbc #CLIPSHORTANGLE*2
    cmp $4E
    bcc @ClipL
    jmp @Done
@ClipL:
    lda #CLIPSHORTANGLE
    sta $4A
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
    jmp @Done
@ClipR:
    lda #$0000
    sec
    sbc #CLIPSHORTANGLE
    sta $4C
@NoClipR:

    ; --- Step 3b: Check solidsegs — skip if fully covered ---
    ; Convert view-relative angles to unsigned (+ ANGLE180)
    lda $4A
    clc
    adc #$8000           ; angle1 + ANGLE180 = "top" (left, larger)
    sta $A8
    lda $4C
    clc
    adc #$8000           ; angle2 + ANGLE180 = "bottom" (right, smaller)
    sta $AA
    jsr checkSolidSegs
    beq @NotCovered      ; zero = visible → continue
    jmp @Done            ; nonzero = fully covered → skip
@NotCovered:

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

    ; --- Step 5: ScaleFromGlobalAngle at both columns ---
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
    ; texU_current = texU_start (in $B8)
    sep #$20
.ACCU 8
@FillCol:
    lda.l colDrawn,x
    beq @NotDrawn
    jmp @SkipCol2
@NotDrawn:
    lda #$01
    sta.l colDrawn,x
    rep #$20
.ACCU 16
    lda.l colsFilled
    inc a
    sta.l colsFilled
    sep #$20
.ACCU 8
    ; Compute wallHeight from current_scale
    rep #$20
.ACCU 16
    lda $7A              ; current_scale
    xba                  ; >> 8
    and #$00FF
    ; Store unclamped full height for texture scaling
    sep #$20
.ACCU 8
    sta.l colFullH,x
    rep #$20
.ACCU 16
    and #$00FF           ; re-extend
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
    sta.l colWallColor,x ; stores texture ID (1 or 2)

    ; --- Compute texture U column (Noah's tangent formula, per column) ---
    ; angle = rw_centerangle + xtoviewangle[x]
    ; texU_world = fp_mul(finetangent[angle], perpDist)
    ; Adjust by midpoint ± texU_world depending on downside
    ; texCol = (texU_world >> 3) & 31
    rep #$20
.ACCU 16
    phx                  ; save column index
    txa
    and #$00FF
    asl a                ; *2 for word index into xtoviewangle
    tax
    lda.l xtoviewangle,x ; signed fine angle offset for this column
    clc
    adc $A0              ; + rw_centerangle
    and #$03FF           ; mask to 1024 entries (finetangent range)
    asl a                ; *2 for word index
    tax
    lda.l finetangent,x  ; signed 8.8 tangent value
    tay                  ; Y = tangent
    lda $28              ; A = perpDist
    jsr fp_mul_hw        ; result = tangent * perpDist
    sta $A6              ; texU_offset
    lda $A4              ; downside
    bne @TexDown
    lda $A2              ; midpoint
    clc
    adc $A6              ; + texU_offset
    bra @TexDone2
@TexDown:
    lda $A2              ; midpoint
    sec
    sbc $A6              ; - texU_offset
@TexDone2:
    ; texCol = (texU_world >> 3) & 31
    lsr a
    lsr a
    lsr a                ; >> 3
    and #$001F           ; & 31
    plx                  ; restore column index
    sep #$20
.ACCU 8
    sta.l colTexCol,x    ; store texture column
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
    bcs @DoneFill
    jmp @FillCol
@DoneFill:
    ; Add rendered range to solidsegs
    rep #$20
.ACCU 16
    jsr addSolidSeg
@Done:
    plp
    rts                  ; called via JSR from renderAllWalls (same bank)

;; -------------------------------------------------------
;; checkSolidSegs — is angular range [$A8(top),$AA(bottom)] fully covered?
;; Returns A: nonzero = covered (skip), zero = visible (render)
;; -------------------------------------------------------
checkSolidSegs:
.ACCU 16
.INDEX 16
    lda.l ss_count
    beq @SSVisible        ; no entries → visible
    sta $AC               ; loop counter
    ldx #$0000
@SSLoop:
    ; Covered if: entry.top >= our top AND entry.bottom <= our bottom
    lda.l ss_top,x
    cmp $A8               ; entry.top vs our top
    bcc @SSNext           ; entry.top < our top → doesn't fully cover left
    lda $AA               ; our bottom
    cmp.l ss_bot,x        ; our bottom vs entry.bottom
    bcc @SSNext           ; our bottom < entry.bottom → doesn't cover right
    ; Fully covered!
    lda #$0001
    rts
@SSNext:
    inx
    inx                   ; +2 bytes per word entry
    dec $AC
    bne @SSLoop
@SSVisible:
    lda #$0000
    rts

;; -------------------------------------------------------
;; addSolidSeg — add range [$A8(top),$AA(bottom)] to solidsegs
;; -------------------------------------------------------
addSolidSeg:
.ACCU 16
.INDEX 16
    lda.l ss_count
    cmp #16
    bcs @SSFull           ; list full, can't add
    asl a                 ; *2 for word index
    tax
    lda $A8               ; top
    sta.l ss_top,x
    lda $AA               ; bottom
    sta.l ss_bot,x
    lda.l ss_count
    inc a
    sta.l ss_count
@SSFull:
    rts

;; colDrawn: 112 bytes in RAM (allocated in .ramsection at end of file)

;; ===============================================================
;; BSP ROM data (44 entries × 6 bytes = 264 bytes)
;; Node: plane(1), dir(1), child0_lo(1), child0_hi(1), child1_lo(1), child1_hi(1)
;; Seg:  plane(1), dir(1), min(1), max(1), texture(1), area(1)
;; Coordinates in half-tiles: world = value << 7
;; ===============================================================
bsp_rom_data:
    .db 8, 1, 1, 0, 30, 0       ; [0] node: plane=8, vert, children=[1,30]
    .db 12, 1, 2, 0, 16, 0      ; [1] node: plane=12, vert, children=[2,16]
    .db 8, 0, 3, 0, 12, 0       ; [2] node: plane=8, horiz, children=[3,12]
    .db 12, 0, 4, 0, 8, 0       ; [3] node: plane=12, horiz, children=[4,8]
    .db 18, 131, 2, 18, 1, 0    ; [4] seg: W, span=2-18, tex=1
    .db 12, 129, 8, 12, 2, 0    ; [5] seg: E, span=8-12, tex=2
    .db 12, 130, 8, 12, 2, 0    ; [6] seg: S, span=8-12, tex=2
    .db 18, 192, 2, 18, 1, 0    ; [7] seg: N+last, span=2-18, tex=1
    .db 18, 131, 2, 18, 1, 0    ; [8] seg: W, span=2-18, tex=1
    .db 8, 128, 8, 12, 2, 0     ; [9] seg: N, span=8-12, tex=2
    .db 12, 129, 8, 12, 2, 0    ; [10] seg: E, span=8-12, tex=2
    .db 12, 194, 8, 12, 2, 0    ; [11] seg: S+last, span=8-12, tex=2
    .db 2, 130, 2, 18, 1, 0     ; [12] seg: S, span=2-18, tex=1
    .db 18, 131, 2, 18, 1, 0    ; [13] seg: W, span=2-18, tex=1
    .db 8, 128, 8, 12, 2, 0     ; [14] seg: N, span=8-12, tex=2
    .db 12, 193, 8, 12, 2, 0    ; [15] seg: E+last, span=8-12, tex=2
    .db 8, 0, 17, 0, 26, 0      ; [16] node: plane=8, horiz, children=[17,26]
    .db 12, 0, 18, 0, 22, 0     ; [17] node: plane=12, horiz, children=[18,22]
    .db 8, 131, 8, 12, 2, 0     ; [18] seg: W, span=8-12, tex=2
    .db 12, 129, 8, 12, 2, 0    ; [19] seg: E, span=8-12, tex=2
    .db 12, 130, 8, 12, 2, 0    ; [20] seg: S, span=8-12, tex=2
    .db 18, 192, 2, 18, 1, 0    ; [21] seg: N+last, span=2-18, tex=1
    .db 8, 128, 8, 12, 2, 0     ; [22] seg: N, span=8-12, tex=2
    .db 8, 131, 8, 12, 2, 0     ; [23] seg: W, span=8-12, tex=2
    .db 12, 129, 8, 12, 2, 0    ; [24] seg: E, span=8-12, tex=2
    .db 12, 194, 8, 12, 2, 0    ; [25] seg: S+last, span=8-12, tex=2
    .db 2, 130, 2, 18, 1, 0     ; [26] seg: S, span=2-18, tex=1
    .db 8, 128, 8, 12, 2, 0     ; [27] seg: N, span=8-12, tex=2
    .db 8, 131, 8, 12, 2, 0     ; [28] seg: W, span=8-12, tex=2
    .db 12, 193, 8, 12, 2, 0    ; [29] seg: E+last, span=8-12, tex=2
    .db 8, 0, 31, 0, 40, 0      ; [30] node: plane=8, horiz, children=[31,40]
    .db 12, 0, 32, 0, 36, 0     ; [31] node: plane=12, horiz, children=[32,36]
    .db 2, 129, 2, 18, 1, 0     ; [32] seg: E, span=2-18, tex=1
    .db 8, 131, 8, 12, 2, 0     ; [33] seg: W, span=8-12, tex=2
    .db 12, 130, 8, 12, 2, 0    ; [34] seg: S, span=8-12, tex=2
    .db 18, 192, 2, 18, 1, 0    ; [35] seg: N+last, span=2-18, tex=1
    .db 2, 129, 2, 18, 1, 0     ; [36] seg: E, span=2-18, tex=1
    .db 8, 128, 8, 12, 2, 0     ; [37] seg: N, span=8-12, tex=2
    .db 8, 131, 8, 12, 2, 0     ; [38] seg: W, span=8-12, tex=2
    .db 12, 194, 8, 12, 2, 0    ; [39] seg: S+last, span=8-12, tex=2
    .db 2, 130, 2, 18, 1, 0     ; [40] seg: S, span=2-18, tex=1
    .db 2, 129, 2, 18, 1, 0     ; [41] seg: E, span=2-18, tex=1
    .db 8, 128, 8, 12, 2, 0     ; [42] seg: N, span=8-12, tex=2
    .db 8, 195, 8, 12, 2, 0     ; [43] seg: W+last, span=8-12, tex=2

;; Texture pointer table: tex_ptrs[texID] = offset from tex_base
;; texID 1 = outer wall, texID 2 = inner wall
tex_ptrs:
    .dw 0                                    ; texture 0 (unused)
    .dw 0                                    ; texture 1 = outer (at tex_base+0)
    .dw 1024                                 ; texture 2 = inner (at tex_base+1024)

;; Texture pixel data: 32x32, column-major, 1 byte per pixel (palette index)
;; Each texture column = 32 consecutive bytes. texCol N starts at offset N*32.
;; Texture 1 (outer wall, tile 1) at offset 0, Texture 2 (inner wall, tile 23) at offset 1024
tex_base:
.include "data/wall_textures.asm"

;; computeCenterAngle — compute rw_centerangle from $70 and $2C, store in $A0
;; Must be called after $2C (normalangle) is set, and $70 (centerangle_fine) exists
computeCenterAngle:
.ACCU 16
    lda $70              ; centerangle_fine
    sec
    sbc $2C              ; - normalangle_fine
    and #$07FF           ; & FINEMASK (2047)
    cmp #1024            ; > FINEANGLES/2?
    bcc @NoWrapCA
    sec
    sbc #2048            ; -= FINEANGLES
@NoWrapCA:
    clc
    adc #512             ; += FINEANGLES/4
    sta $A0              ; rw_centerangle
    rts

;; -------------------------------------------------------
;; drawOneSeg -- translate BSP segment into renderOneWall call
;; Input: X = byte offset into bsp_rom_data (entry_index * 6)
;; BSP directions: 0=N face(fixedY,player north), 1=E(fixedX,player east),
;;                 2=S(fixedY,player south), 3=W(fixedX,player west)
;; -------------------------------------------------------
drawOneSeg:
    rep #$30
.ACCU 16
.INDEX 16
    ; Extract segment fields
    ; segplane = plane << 7  (halftile to world coords)
    lda.l bsp_rom_data+0,x
    and #$00FF
    xba
    lsr a
    sta $80              ; segplane

    ; direction = dir & 3
    lda.l bsp_rom_data+1,x
    and #$0003
    sta $82              ; direction (0-3)

    ; mintex = min << 7
    lda.l bsp_rom_data+2,x
    and #$00FF
    xba
    lsr a
    sta $84              ; mintex

    ; maxtex = max << 7
    lda.l bsp_rom_data+3,x
    and #$00FF
    xba
    lsr a
    sta $86              ; maxtex

    ; texture ID → $2A (used by renderOneWall to store in colWallColor)
    lda.l bsp_rom_data+4,x
    and #$00FF
    sta $88              ; texture (1 or 2)
    ; Set dark flag for N/S faces (BSP dir 0 and 2 = even = bit0 clear)
    ; Dark: texID | $80. Bright: texID.
    sep #$20
.ACCU 8
    sta $2A              ; texture ID
    lda $82              ; direction (low byte)
    and #$01             ; bit 0: 0=N/S(dark), 1=E/W(bright)
    bne @BrightSide
    lda $2A
    ora #$80             ; set dark flag
    sta $2A
@BrightSide:
    rep #$20
.ACCU 16

    ; Compute rw_centerangle for texture mapping
    ; rw_centerangle = (centerangle_fine - normalangle_fine) & FINEMASK
    ; Then adjust: if > FINEANGLES/2, subtract FINEANGLES; add FINEANGLES/4
    ; NOTE: $70 = centerangle_fine, $2C = normalangle_fine (set per direction below)

    ; Set midpoint and downside based on direction
    ; BSP 0(N)=di_west: midpoint=posX, downside=0
    ; BSP 1(E)=di_north: midpoint=posY, downside=0
    ; BSP 2(S)=di_east: midpoint=posX, downside=1
    ; BSP 3(W)=di_south: midpoint=posY, downside=1
    lda $82              ; direction
    cmp #2
    bcs @DownSide        ; dir >= 2 → downside = 1
    lda #0
    sta $A4              ; downside = 0
    bra @SetMid
@DownSide:
    lda #1
    sta $A4              ; downside = 1
@SetMid:
    lda $82
    and #$0001           ; bit 0: 0=N/S(fixedY, mid=posX), 1=E/W(fixedX, mid=posY)
    bne @MidY
    lda.l posX
    sta $A2              ; midpoint = posX (for N/S faces)
    bra @MidDone
@MidY:
    lda.l posY
    sta $A2              ; midpoint = posY (for E/W faces)
@MidDone:

    ; Switch on direction
    lda $82
    beq @DirN
    cmp #1
    beq @DirE
    cmp #2
    beq @DirS
    ; fall through = dir 3 (West)

@DirW:  ; W face: fixed X, player west (posX < segplane)
    lda $80
    sec
    sbc.l posX
    beq @SkipW
    bpl @VisW
@SkipW: rts
@VisW:
    sta $28              ; perpDist = segplane - posX
    lda $80
    sta $20    ; x1 = segplane
    lda $84
    sta $22    ; y1 = mintex (di_south: mintex first)
    lda $80
    sta $24    ; x2 = segplane
    lda $86
    sta $26    ; y2 = maxtex
    lda #0
    sta $2C   ; normalangle = 0
    jsr computeCenterAngle
    jsr renderOneWall
    rts

@DirN:  ; N face: fixed Y, player north (posY < segplane)
    lda $80
    sec
    sbc.l posY
    beq @SkipN
    bpl @VisN
@SkipN: rts
@VisN:
    sta $28              ; perpDist = segplane - posY
    lda $86
    sta $20    ; x1 = maxtex (di_west: maxtex first)
    lda $80
    sta $22    ; y1 = segplane
    lda $84
    sta $24    ; x2 = mintex
    lda $80
    sta $26    ; y2 = segplane
    lda #1536
    sta $2C  ; normalangle = 3*512
    jsr computeCenterAngle
    jsr renderOneWall
    rts

@DirE:  ; E face: fixed X, player east (posX > segplane)
    lda.l posX
    sec
    sbc $80
    beq @SkipE
    bpl @VisE
@SkipE: rts
@VisE:
    sta $28              ; perpDist = posX - segplane
    lda $80
    sta $20    ; x1 = segplane
    lda $86
    sta $22    ; y1 = maxtex (di_north: maxtex first)
    lda $80
    sta $24    ; x2 = segplane
    lda $84
    sta $26    ; y2 = mintex
    lda #1024
    sta $2C  ; normalangle = 2*512
    jsr computeCenterAngle
    jsr renderOneWall
    rts

@DirS:  ; S face: fixed Y, player south (posY > segplane)
    lda.l posY
    sec
    sbc $80
    beq @SkipS
    bpl @VisS
@SkipS: rts
@VisS:
    sta $28              ; perpDist = posY - segplane
    lda $84
    sta $20    ; x1 = mintex (di_east: mintex first)
    lda $80
    sta $22    ; y1 = segplane
    lda $86
    sta $24    ; x2 = maxtex
    lda $80
    sta $26    ; y2 = segplane
    lda #512
    sta $2C   ; normalangle = 1*512
    jsr computeCenterAngle
    jsr renderOneWall
    rts

@Done:
    rts

;; -------------------------------------------------------
;; terminalNode -- iterate segment chain, call drawOneSeg for each
;; Input: X = byte offset of first segment in bsp_rom_data
;; -------------------------------------------------------
terminalNode:
    rep #$30
.ACCU 16
.INDEX 16
@SegLoop:
    phx                  ; save offset (drawOneSeg clobbers X)
    jsr drawOneSeg
    plx                  ; restore offset
    ; Check DIR_LASTSEGFLAG ($40) in dir byte
    sep #$20
.ACCU 8
    lda.l bsp_rom_data+1,x
    and #$40
    bne @SegDone
    rep #$20
.ACCU 16
    ; Advance to next entry: X += 6
    txa
    clc
    adc #6
    tax
    bra @SegLoop
@SegDone:
    rep #$20
.ACCU 16
    rts

;; -------------------------------------------------------
;; renderBSPNode -- recursive BSP traversal (JSR-based, max depth ~5)
;; Input: X = byte offset into bsp_rom_data
;; Front-to-back order: render near child first, far child second
;; -------------------------------------------------------
renderBSPNode:
    rep #$30
.ACCU 16
.INDEX 16
    ; Early-out: all 112 columns filled → stop traversal
    lda.l colsFilled
    cmp #112
    bcc @NotFull
    rts
@NotFull:
    ; Check if segment (DIR_SEGFLAG = $80 in dir byte)
    sep #$20
.ACCU 8
    lda.l bsp_rom_data+1,x
    bmi @IsSeg           ; bit 7 set → segment chain
    rep #$20
.ACCU 16

    ; It's a node — read split plane coordinate
    lda.l bsp_rom_data+0,x
    and #$00FF
    xba
    lsr a                ; coordinate = plane << 7
    sta $90              ; split coordinate (world)

    ; Read children (16-bit indices)
    lda.l bsp_rom_data+2,x
    and #$00FF           ; child0 index (front in BSP builder = greater side)
    sta $92
    lda.l bsp_rom_data+4,x
    and #$00FF           ; child1 index (back in BSP builder = lesser side)
    sta $94

    ; Determine near/far based on player position vs split
    sep #$20
.ACCU 8
    lda.l bsp_rom_data+1,x  ; dir: 0=horiz(Y split), 1=vert(X split)
    rep #$20
.ACCU 16
    and #$0001
    bne @VertSplit

@HorizSplit:
    ; Horizontal split: compare posY vs coordinate
    ; child0 = greater Y side, child1 = lesser Y side
    lda.l posY
    cmp $90
    bcc @NearChild1      ; posY < coordinate → player on lesser side → near=child1
    beq @NearChild1
    ; posY > coordinate → near=child0, far=child1
    lda $92
    sta $96    ; near = child0
    lda $94              ; far = child1
    bra @DoTraverse

@VertSplit:
    ; Vertical split: compare posX vs coordinate
    ; child0 = greater X side, child1 = lesser X side
    lda.l posX
    cmp $90
    bcc @NearChild1      ; posX < coordinate → near=child1
    beq @NearChild1
    lda $92
    sta $96    ; near = child0
    lda $94              ; far = child1
    bra @DoTraverse

@NearChild1:
    lda $94
    sta $96    ; near = child1
    lda $92              ; far = child0

@DoTraverse:
    ; A = far child index, $96 = near child index
    ; Push far child index for later
    pha

    ; Convert near index to byte offset (index * 6)
    lda $96
    asl a                ; *2
    sta $98
    asl a                ; *4
    clc
    adc $98              ; *6
    tax
    ; Recurse into near child
    jsr renderBSPNode

    ; Pop far child index, convert to byte offset
    pla
    asl a
    sta $98
    asl a
    clc
    adc $98
    tax
    ; Recurse into far child
    jsr renderBSPNode
    rts

@IsSeg:
    rep #$20
.ACCU 16
    jsr terminalNode
    rts

;; -------------------------------------------------------
;; renderAllWalls -- BSP-driven wall rendering
;; Traverses BSP tree front-to-back, calls renderOneWall for each segment
;; -------------------------------------------------------
renderAllWalls:
    php
    rep #$30
.ACCU 16
.INDEX 16
    ; Init column arrays
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
    lda #$0000
    sta.l colsFilled     ; 0 columns filled
    sta.l ss_count       ; 0 solidsegs entries

    ; BSP traversal from root (entry 0, byte offset 0)
    ldx #0
    jsr renderBSPNode

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

;; Floor texture data (32x32, column-major)
.include "data/floor_texture.asm"

;; Row distance table: rowDist[r] = 10240 / (r+1) for r=0..38
;; 8.8 fixed point. r=0 is first floor row (screen row 41).
rowDist_table:
.dw 10240, 5120, 3413, 2560, 2048, 1706, 1462, 1280
.dw 1137, 1024, 930, 853, 787, 731, 682, 640
.dw 602, 568, 538, 512, 487, 465, 445, 426
.dw 409, 393, 378, 365, 353, 341, 330, 320
.dw 311, 302, 293, 284, 277, 269, 263, 256

;; -------------------------------------------------------
;; renderFloor -- software floor raycasting (row-major)
;; For each floor row, steps across columns with linear texture interpolation.
;; Uses: posX, posY, dirX, dirY, planeX, planeY, colDrawEnd[]
;; Writes directly to WRAM screenbuffer via WMADD
;; -------------------------------------------------------
renderFloor:
    php
    rep #$30
.ACCU 16
.INDEX 16

    ; Precompute leftRayDir = dir - plane
    lda.l dirX
    sec
    sbc.l planeX
    sta $B8              ; leftRayDirX
    lda.l dirY
    sec
    sbc.l planeY
    sta $BA              ; leftRayDirY

    ; Precompute 2*planeX and 2*planeY (right - left ray difference)
    lda.l planeX
    asl a
    sta $BC              ; 2*planeX
    lda.l planeY
    asl a
    sta $BE              ; 2*planeY

    ; Row loop: r = 0..38 (screen rows 41..79)
    ldy #$0000           ; Y = row index (0-38)

@RowLoop:
    sty $C4              ; save row index

    ; rowDist = rowDist_table[r]
    tya
    asl a                ; *2 for word index
    tax
    lda.l rowDist_table,x
    sta $C0              ; rowDist

    ; floorX = posX + fp_mul(rowDist, leftRayDirX)
    tay                  ; Y = rowDist
    lda $B8              ; A = leftRayDirX
    jsr fp_mul_hw
    clc
    adc.l posX
    sta $B0              ; floorX

    ; floorY = posY + fp_mul(rowDist, leftRayDirY)
    lda $C0
    tay                  ; Y = rowDist
    lda $BA              ; A = leftRayDirY
    jsr fp_mul_hw
    clc
    adc.l posY
    sta $B2              ; floorY

    ; floorStepX = fp_mul(rowDist, 2*planeX) / 56
    ; Actually: step = rowDist * 2*planeX / SCREEN_W
    ; Approximate: fp_mul gives rowDist*2*planeX >> 8, then divide by 112
    ; Simpler: fp_mul(rowDist, 2*planeX/112) but 2*planeX/112 might be 0
    ; Better: compute fp_mul(rowDist, 2*planeX), then divide result by 112
    lda $C0
    tay
    lda $BC              ; 2*planeX
    jsr fp_mul_hw        ; = rowDist * 2*planeX (8.8 result)
    ; Divide by 112 using hardware
    sta $C6              ; save numerator
    bpl @StepXPos
    eor #$FFFF
    inc a
    sep #$20
.ACCU 8
    sta.l $4204
    xba
    sta.l $4205
    lda #112
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
    inc a
    sta $B4              ; floorStepX (negative)
    bra @StepXDone
@StepXPos:
    sep #$20
.ACCU 8
    sta.l $4204
    xba
    sta.l $4205
    lda #112
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
    sta $B4              ; floorStepX
@StepXDone:

    ; floorStepY = fp_mul(rowDist, 2*planeY) / 112
    lda $C0
    tay
    lda $BE              ; 2*planeY
    jsr fp_mul_hw
    sta $C6
    bpl @StepYPos
    eor #$FFFF
    inc a
    sep #$20
.ACCU 8
    sta.l $4204
    xba
    sta.l $4205
    lda #112
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
    inc a
    sta $B6              ; floorStepY (negative)
    bra @StepYDone
@StepYPos:
    sep #$20
.ACCU 8
    sta.l $4204
    xba
    sta.l $4205
    lda #112
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
    sta $B6              ; floorStepY
@StepYDone:

    ; Column loop: half-resolution (every other column)
    ; screenRow = 41 + rowIndex
    lda $C4
    clc
    adc #41
    sta $C2              ; screenRow

    lda #$0000
    sta $CA              ; column index
@ColLoop:
    ; Load column index into X for colDrawEnd check
    ldx $CA

    ; Check if this floor pixel is visible (below wall)
    sep #$20
.ACCU 8
    lda $C2              ; screenRow
    cmp.l colDrawEnd,x   ; floor visible if screenRow >= drawEnd
    rep #$20
.ACCU 16
    bcc @SkipFloorPix    ; wall covers this pixel

    ; Compute texture coordinates
    lda $B0              ; floorX
    lsr a
    lsr a
    lsr a
    and #$001F
    sta $C6              ; texU
    lda $B2              ; floorY
    lsr a
    lsr a
    lsr a
    and #$001F
    sta $C8              ; texV
    ; texture offset = texU * 32 + texV
    lda $C6
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc $C8
    tax

    sep #$20
.ACCU 8
    lda.l floor_tex,x   ; read floor pixel
    sta $C9

    ; Set WMADD = columnstart[col] + screenRow
    rep #$20
.ACCU 16
    lda $CA              ; column index
    and #$00FF
    asl a                ; *2 for word table
    tax
    lda.l columnstart,x
    sta $C6              ; save column base
    sep #$20
.ACCU 8
    lda $C6
    clc
    adc $C2              ; + screenRow
    sta.l $2181          ; WMADDL
    lda $C7
    adc #$00
    sta.l $2182          ; WMADDM

    ; Write floor pixel
    lda $C9
    sta.l $2180

    ; Also write to col+1 (half-res: duplicate pixel to neighbor)
    lda $C6
    clc
    adc #80              ; columnstart[col+1] = columnstart[col] + 80
    sta.l $2181
    lda $C7
    adc #$00
    sta.l $2182
    lda $C9
    sta.l $2180

    rep #$20
.ACCU 16

@SkipFloorPix:
    ; Advance floor position by 2 columns (half-res)
    lda $B0
    clc
    adc $B4
    clc
    adc $B4              ; floorX += 2 * floorStepX
    sta $B0
    lda $B2
    clc
    adc $B6
    clc
    adc $B6              ; floorY += 2 * floorStepY
    sta $B2

    ; Next column (step by 2)
    lda $CA
    clc
    adc #2
    sta $CA
    cmp #112
    bcs @ColsDone
    jmp @ColLoop
@ColsDone:

    ; Next row (step by 2 for half-res vertical)
    ldy $C4              ; row index
    iny
    iny                  ; skip every other row
    cpy #40
    bcs @FloorDone
    jmp @RowLoop
@FloorDone:
    plp
    rtl
;; -------------------------------------------------------
;; Playback background: solid ceiling + solid floor (renderFloor adds texture)
;; -------------------------------------------------------
playback_bg:
.REPT 112
.REPT 40
.db CEIL_COLOR
.ENDR
.REPT 40
.db FLOOR_COLOR
.ENDR
.ENDR

.ends

;; Compiled wall scalers (heights 1-80) in ROM bank 2
.include "data/compiled_scalers.asm"

.ramsection ".coldrawn" slot 2 bank 126
colDrawn dsb 112
colsFilled dsb 2
colTexCol dsb 112
colFullH dsb 112
ss_top dsb 32            ; solidsegs top angles (16 entries × 2 bytes)
ss_bot dsb 32            ; solidsegs bottom angles (16 entries × 2 bytes)
ss_count dsb 2           ; number of solidsegs entries
.ends

