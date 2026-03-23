;; data.asm -- 65816-only raycaster: display, DMA, column renderer
;;
;; No SuperFX. Mode 7 viewport (14x10 tiles, 2x zoom = 112x80 pixels).
;; Framebuffer: tile-organized at $7F:2000 (140 tiles x 64 bytes = 8960 bytes).
;; DMA: single forced-blank transfer to VRAM during VBlank.

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

;; Constants
.define SCREEN_H        80
.define HALF_H          40
.define TILE_COLS       14
.define TILE_ROWS       10
.define NUM_TILES       140
.define FB_SIZE         8960      ; 140*64
.define FB_BASE         $2000     ; in bank $7F
.define FB_BANK         $7F
.define CEIL_COLOR      16
.define FLOOR_COLOR     17
.define HUD_COLOR       18
.define INIDISP_ON      $0F

;; -------------------------------------------------------
;; initMode7Display -- Mode 7, 2x zoom, 14x10 viewport
;; -------------------------------------------------------
initMode7Display:
    php
    phb
    sep #$20
    rep #$10

    lda #$80
    sta.l $2100          ; force blank

    lda #$07
    sta.l $2105          ; Mode 7
    lda #$01
    sta.l $212C          ; TM = BG1

    ; 2x zoom
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

    ; === Palette ===
    lda #$00
    sta.l $2121
    ldx #$0000
@PalLoop:
    lda.l shared_palette,x
    sta.l $2122
    inx
    cpx #$0020
    bne @PalLoop

    lda #16
    sta.l $2121
    ldx #$0000
@ExPalLoop:
    lda.l extra_palette,x
    sta.l $2122
    inx
    cpx #$0004
    bne @ExPalLoop

    lda #18
    sta.l $2121
    lda #$FF
    sta.l $2122
    lda #$03
    sta.l $2122

    lda #32
    sta.l $2121
    ldx #$0000
@DarkPal:
    lda.l dark_palette,x
    sta.l $2122
    inx
    cpx #$0020
    bne @DarkPal

    ; === Tilemap (14x10 viewport + HUD + black borders) ===
    lda #$00
    sta.l $2115          ; VMAIN: low byte write
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20

    ; Fill entire 128x128 tilemap with tile 0 (black)
    rep #$10
    ldy #$0000
@ClearMap:
    lda #$00
    sta.l $2118          ; tilemap low byte = tile 0
    lda #$00
    sta.l $2119          ; pixel high byte = 0
    iny
    cpy #$4000           ; 16384 words
    bne @ClearMap

    ; Now write viewport tiles (14x10) and HUD (14x2)
    ; Tile number = row*14 + col + 1 (1-based)
    ; HUD tile = 141
    ldy #$0000           ; row
@TM_Row:
    ldx #$0000           ; col
@TM_Col:
    ; Compute VRAM word address = row*128 + col
    rep #$20
    tya
    and #$00FF
    xba                  ; row * 256
    lsr a                ; row * 128
    sta $50
    txa
    and #$00FF
    clc
    adc $50              ; VRAM addr = row*128 + col
    sta.l $2116
    sep #$20

    ; Check bounds
    cpy #TILE_ROWS
    bcs @TM_HUD
    cpx #TILE_COLS
    bcs @TM_NextCol

    ; Viewport tile: row*14 + col + 1
    ; row*14 = row*16 - row*2
    tya
    asl a
    asl a
    asl a
    asl a                ; row*16
    sta $52
    tya
    asl a                ; row*2
    sta $54
    lda $52
    sec
    sbc $54              ; row*14
    clc
    adc $56              ; oops $56 not set. Use:
    ; Just compute directly:
    tya
    asl a
    asl a
    asl a
    asl a                ; *16
    sec
    sbc $54              ; subtract row*2 stored at $54... but $54 has row*2
    ; Actually let me just hardcode: A = row*16, subtract row*2
    ; $54 already has row*2 from above
    ; So A = row*16 - row*2 = row*14
    sta $52              ; row*14
    txa
    clc
    adc $52
    inc a                ; tile = row*14+col+1
    sta.l $2118          ; write tilemap entry
    bra @TM_NextCol

@TM_HUD:
    cpy #(TILE_ROWS + 2)
    bcs @TM_NextCol
    cpx #TILE_COLS
    bcs @TM_NextCol
    lda #141             ; HUD tile
    sta.l $2118
    ; fall through

@TM_NextCol:
    inx
    cpx #TILE_COLS
    bcc @TM_Col          ; more viewport/HUD cols
    ; Done with this row's content cols
    iny
    cpy #(TILE_ROWS + 2)
    bcc @TM_Row          ; more rows

    ; === Clear tile pixel data ===
    lda #$80
    sta.l $2115          ; VMAIN: high byte write
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20
    rep #$10
    ldy #$0000
@ClearPix:
    lda #$00
    sta.l $2119
    iny
    cpy #(142 * 64)
    bne @ClearPix

    ; HUD tile 141: fill with yellow
    rep #$20
    lda #(141 * 64)
    sta.l $2116
    sep #$20
    ldy #$0000
@HUDFill:
    lda #HUD_COLOR
    sta.l $2119
    iny
    cpy #64
    bne @HUDFill

    lda #INIDISP_ON
    sta.l $2100

    plb
    plp
    rtl

;; -------------------------------------------------------
;; renderColumns -- Fill tile framebuffer from C column arrays
;; Reads: colDrawStart[], colDrawEnd[], colWallColor[]
;; Writes: $7F:2000 (tile-organized framebuffer)
;; -------------------------------------------------------
renderColumns:
    php
    phb
    phd
    sep #$20
    rep #$10

    ; Set DBR=$7F for framebuffer writes
    lda #FB_BANK
    pha
    plb

    ldx #$0000           ; X = column (0-111)

@ColLoop:
    ; Load column data
    lda.l colDrawStart,x
    sta $10              ; drawStart
    lda.l colDrawEnd,x
    sta $11              ; drawEnd
    lda.l colWallColor,x
    sta $12              ; wallColor

    ; Compute colBase = (col/8)*64 + (col&7)
    txa
    and #$F8             ; col & ~7 = tileCol*8
    asl a                ; tileCol*16
    asl a                ; tileCol*32
    asl a                ; tileCol*64
    sta $14              ; low byte of tileCol*64
    stz $15              ; high byte
    ; Handle overflow for tileCol >= 4 (64*4=256)
    txa
    lsr a
    lsr a
    lsr a                ; tileCol (0-13)
    cmp #$04
    bcc @NoOvf
    ; tileCol*64 needs 16-bit
    rep #$20
    txa
    and #$00F8
    asl a
    asl a
    asl a                ; tileCol*64 (16-bit)
    sta $14
    sep #$20
    bra @AddPx
@NoOvf:
    rep #$20
    lda $14
    and #$00FF
    sta $14
    sep #$20
@AddPx:
    txa
    and #$07             ; pixelX
    rep #$20
    and #$00FF
    clc
    adc $14
    sta $14              ; colBase = tileCol*64 + pixelX (16-bit)
    sep #$20

    ; Render 80 rows
    ldy #$0000           ; Y = row

@RowLoop:
    ; Determine color
    tya
    cmp $10
    bcc @IsCeil
    cmp $11
    beq @IsWall
    bcc @IsWall
    lda #FLOOR_COLOR
    bra @DoWrite
@IsCeil:
    lda #CEIL_COLOR
    bra @DoWrite
@IsWall:
    lda $12              ; wallColor

@DoWrite:
    sta $16              ; save color

    ; Compute FB address = FB_BASE + colBase + rowOfs[row]
    rep #$20
    tya
    and #$00FF
    asl a                ; row*2 (word index)
    phx
    tax
    lda.l rowOfs_tbl,x
    plx
    clc
    adc $14              ; + colBase
    clc
    adc #FB_BASE
    sta $18              ; FB address (16-bit in bank $7F)
    sep #$20

    ; Write pixel (DBR=$7F, use absolute)
    lda $16
    sta ($18)            ; indirect write... wait, need [dp] for bank override
    ; Actually DBR=$7F so absolute addr $18 value is the address in bank $7F
    ; Use: sta ($18) for DP indirect... but that uses DBR for the bank.
    ; With DBR=$7F, sta ($18) reads the pointer from DP ($18), then writes to bank $7F + pointer.
    ; But $18 is in DP (bank $00), and the pointer value is the FB address.
    ; Hmm, sta ($18) is indirect, which uses the 16-bit value at DP+$18 as the address,
    ; with the bank from DBR. Since DBR=$7F, this writes to $7F:value_at_$18. Correct!
    ; But wait, DP is $0000 in bank $00, and $18 is the DP offset.
    ; sta ($18) reads bytes at $0018/$0019 as the address, applies DBR=$7F as bank.
    ; We stored the address in $18/$19 via `sta $18`. So this should work!

    iny
    cpy #SCREEN_H
    beq @RowsDone
    jmp @RowLoop
@RowsDone:

    inx
    cpx #112
    beq @ColsDone
    jmp @ColLoop
@ColsDone:

    pld
    plb
    plp
    rtl

;; -------------------------------------------------------
;; Row offset table: rowOfs[R] = (R/8)*14*64 + (R&7)*8
;; -------------------------------------------------------
rowOfs_tbl:
    .dw 0, 8, 16, 24, 32, 40, 48, 56
    .dw 896, 904, 912, 920, 928, 936, 944, 952
    .dw 1792, 1800, 1808, 1816, 1824, 1832, 1840, 1848
    .dw 2688, 2696, 2704, 2712, 2720, 2728, 2736, 2744
    .dw 3584, 3592, 3600, 3608, 3616, 3624, 3632, 3640
    .dw 4480, 4488, 4496, 4504, 4512, 4520, 4528, 4536
    .dw 5376, 5384, 5392, 5400, 5408, 5416, 5424, 5432
    .dw 6272, 6280, 6288, 6296, 6304, 6312, 6320, 6328
    .dw 7168, 7176, 7184, 7192, 7200, 7208, 7216, 7224
    .dw 8064, 8072, 8080, 8088, 8096, 8104, 8112, 8120

;; -------------------------------------------------------
;; dmaFramebuffer -- Single VBlank DMA to VRAM
;; -------------------------------------------------------
dmaFramebuffer:
    php
    sep #$20
    rep #$10

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

    ; VMAIN: high byte write, +1 increment
    lda #$80
    sta.l $2115

    ; VRAM addr 0
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20

    ; DMA ch0: $7F:2000 → $2119, 8960 bytes
    lda #$00
    sta.l $4300
    lda #$19
    sta.l $4301
    rep #$20
    lda #FB_BASE
    sta.l $4302
    sep #$20
    lda #FB_BANK
    sta.l $4304
    rep #$20
    lda #FB_SIZE
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Display on
    lda #$07
    sta.l $2105
    lda #$01
    sta.l $212C
    lda #INIDISP_ON
    sta.l $2100

    plp
    rtl

;; -------------------------------------------------------
;; disableNMI
;; -------------------------------------------------------
disableNMI:
    php
    sep #$20
    lda #$01
    sta.l $4200
    plp
    rtl

;; -------------------------------------------------------
;; readJoypad
;; -------------------------------------------------------
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

;; -------------------------------------------------------
;; clearFramebuffer -- fill $7F:2000 with ceiling color
;; -------------------------------------------------------
clearFramebuffer:
    php
    sep #$20
    rep #$10

    lda #FB_BANK
    sta.l $2183
    rep #$20
    lda #FB_BASE
    sta.l $2181
    sep #$20

    ldy #$0000
@Fill:
    lda #CEIL_COLOR
    sta.l $2180
    iny
    cpy #FB_SIZE
    bne @Fill

    plp
    rtl

;; -------------------------------------------------------
;; IRQ stub (for vector table compatibility)
;; -------------------------------------------------------
IRQTrampoline:
    rti

.ends
