;; Minimal Mode 7 test: fill screen with a solid color

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

    ; Palette: colors 0-15 from shared_palette, 16-17 from extra_palette
    lda #$00
    sta.l $2121
    ldx #$0000
@Pal:
    lda.l shared_palette,x
    sta.l $2122
    inx
    cpx #$0020           ; 16 colors * 2 bytes
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
    ; Color 18: yellow HUD ($03FF = R31 G31 B0)
    lda #18
    sta.l $2121
    lda #$FF
    sta.l $2122
    lda #$03
    sta.l $2122

    ; === TILEMAP: 14x10 viewport, tile = row*14+col+1 ===
    ; VMAIN=$00: increment after low byte write
    lda #$00
    sta.l $2115
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20

    ; Centered 16x14 layout (fills 256x224 screen exactly at 2x zoom)
    ; Row 0 = top border, Rows 1-10 = viewport, Rows 11-12 = HUD, Row 13 = bottom border
    ; Col 0 = left border, Cols 1-14 = content, Col 15 = right border
    stz $40              ; map row (0-127)
@MR:
    stz $41              ; map col (0-127)
@MC:
    ; Check if in the 16x14 active area
    lda $40
    cmp #14
    bcs @Blk             ; row >= 14 = all black
    lda $41
    cmp #16
    bcs @Blk             ; col >= 16 = all black

    ; Border rows/cols
    lda $40
    beq @Blk             ; row 0 = top border
    cmp #13
    beq @Blk             ; row 13 = bottom border
    lda $41
    beq @Blk             ; col 0 = left border
    cmp #15
    beq @Blk             ; col 15 = right border

    ; Content area: rows 1-12, cols 1-14
    lda $40
    cmp #11
    bcs @HUD             ; rows 11-12 = HUD

    ; Viewport: tile = (mapRow-1)*14 + (mapCol-1) + 1
    lda $40
    dec a                ; row-1 (0-9)
    asl a                ; *2
    sta $42
    asl a                ; *4
    asl a                ; *8
    asl a                ; *16
    sec
    sbc $42              ; *14
    sta $42
    lda $41
    dec a                ; col-1 (0-13)
    clc
    adc $42
    inc a                ; +1 (1-based)
    sta.l $2118
    bra @Nxt

@HUD:
    lda #141             ; HUD tile (yellow)
    sta.l $2118
    bra @Nxt

@Blk:
    lda #$00
    sta.l $2118
@Nxt:
    inc $41
    lda $41
    cmp #$80
    bne @MC
    inc $40
    lda $40
    cmp #$80
    bne @MR

    ; === TILE 0: black (border) ===
    lda #$80
    sta.l $2115
    rep #$20
    lda #$0000           ; tile 0 = word 0
    sta.l $2116
    sep #$20
    rep #$10
    ldy #$0000
@T0:
    lda #$00             ; color 0 = black
    sta.l $2119
    iny
    cpy #64
    bne @T0

    ; === TILES 1-140: 3-band test (ceiling/wall/floor) ===
    ; Row 0-2 = ceiling (42 tiles), row 3-6 = wall (56 tiles), row 7-9 = floor (42 tiles)
    ; Each tile = 64 bytes of the same color
    ; Ceiling: tiles 1-42 (3 rows * 14 cols)
    ldy #$0000
@Band1:
    lda #16              ; ceiling color
    sta.l $2119
    iny
    cpy #2688            ; 42*64
    bne @Band1
    ; Wall: tiles 43-98 (4 rows * 14 cols = 56 tiles)
    ldy #$0000
@Band2:
    lda #5               ; wall color
    sta.l $2119
    iny
    cpy #3584            ; 56*64
    bne @Band2
    ; Floor: tiles 99-140 (3 rows * 14 cols = 42 tiles)
    ldy #$0000
@Band3:
    lda #17              ; floor color
    sta.l $2119
    iny
    cpy #2688            ; 42*64
    bne @Band3

    ; HUD tile 141: yellow (color 18)
    ; VRAM continues sequentially (tile 141 = word 141*64 = 9024)
    ; But we've only written 140 tiles so far from tile 1, so VRAM pointer is at
    ; word 64 + 8960 = 9024 = exactly tile 141. Perfect.
    ldy #$0000
@HUDPix:
    lda #18              ; yellow
    sta.l $2119
    iny
    cpy #64
    bne @HUDPix

    ; Screen on
    lda #$0F
    sta.l $2100

    plb
    plp
    rtl

;; -------------------------------------------------------
;; renderColumns -- write raycaster output to $7F:2000
;; Tile-organized, row-major (row*14+col+1), 14 tiles wide
;; Uses WMADD ($2180/$2181) for fast writes
;; -------------------------------------------------------
renderColumns:
    php
    sep #$20
    rep #$10

    ldx #$0000           ; column 0-111

@CL:
    lda.l colDrawStart,x
    sta $10
    lda.l colDrawEnd,x
    sta $11
    lda.l colWallColor,x
    sta $12

    ; colBase = tileCol*64 + pixelX (row-major, 14 tiles wide)
    rep #$20
    txa
    and #$00FF
    and #$FFF8           ; tileCol*8
    asl a
    asl a
    asl a                ; tileCol*64
    sta $14
    txa
    and #$0007
    clc
    adc $14
    sta $14              ; colBase
    sep #$20

    ldy #$0000           ; row 0-79
@RL:
    tya
    cmp $10
    bcc @Ce
    cmp $11
    beq @Wa
    bcc @Wa
    lda #FLOOR_COLOR
    bra @Wr
@Ce:
    lda #CEIL_COLOR
    bra @Wr
@Wa:
    lda $12
@Wr:
    pha                  ; save color
    ; FB addr = $2000 + colBase + rowOfs[row]
    rep #$20
    tya
    and #$00FF
    asl a
    phx
    tax
    lda.l rowOfs_tbl,x
    plx
    clc
    adc $14
    clc
    adc #FB_BASE
    sta.l $2181          ; WMADDL/M
    sep #$20
    lda #FB_BANK
    sta.l $2183          ; WMADDH=$7F
    pla
    sta.l $2180          ; write pixel

    iny
    cpy #SCREEN_H
    beq @RD
    jmp @RL
@RD:
    inx
    cpx #SCREEN_W
    beq @CD
    jmp @CL
@CD:
    plp
    rtl

;; rowOfs[R] = (R/8)*14*64 + (R&7)*8 = (R/8)*896 + (R&7)*8
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
;; dmaFramebuffer -- bulk DMA $7F:2000 → VRAM tile 1
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
    ; VMAIN=$80: high byte write, step 1
    lda #$80
    sta.l $2115
    ; VRAM word $0040 (tile 1)
    rep #$20
    lda #$0040
    sta.l $2116
    sep #$20
    ; DMA ch0
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
    lda #$0F
    sta.l $2100
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
@F:
    lda #CEIL_COLOR
    sta.l $2180
    iny
    cpy #FB_SIZE
    bne @F
    plp
    rtl

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

;; HDMA table: BGMODE values per scanline group
;; 176 scanlines Mode 7 (border + viewport), 48 scanlines Mode 1 (HUD + border)
hdma_bgmode:
    .db $FF, $07         ; repeat 127 lines: Mode 7
    .db $E1, $07         ; repeat 97 lines: Mode 7 (total 224, all Mode 7)
    .db 0                ; end

.ends
