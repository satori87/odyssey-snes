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

    ; Palette: color 0=black, color 5=white
    lda #$00
    sta.l $2121          ; CGADD=0
    ; Color 0: black
    lda #$00
    sta.l $2122
    sta.l $2122
    ; Colors 1-4: black
    ldy #$0000
@PadPal:
    lda #$00
    sta.l $2122
    sta.l $2122
    iny
    cpy #4
    bne @PadPal
    ; Color 5: bright white ($7FFF)
    lda #$FF
    sta.l $2122
    lda #$7F
    sta.l $2122

    ; === TILEMAP: 14x10 viewport, tile = row*14+col+1 ===
    ; VMAIN=$00: increment after low byte write
    lda #$00
    sta.l $2115
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20

    ; Fill entire 128x128 tilemap sequentially
    stz $40              ; map row
@MR:
    stz $41              ; map col
@MC:
    lda $40
    cmp #10              ; viewport rows
    bcs @Blk
    lda $41
    cmp #14              ; viewport cols
    bcs @Blk
    ; tile = row*14+col+1
    lda $40
    asl a                ; *2
    sta $42
    asl a                ; *4
    asl a                ; *8
    asl a                ; *16
    sec
    sbc $42              ; *16-*2 = *14
    clc
    adc $41              ; +col
    inc a                ; +1
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

    ; === TILES 1-140: white (viewport test) ===
    ; VRAM address continues from tile 0 end = word 64 = tile 1
    ldy #$0000
@Pix:
    lda #$05             ; color 5 = white
    sta.l $2119
    iny
    cpy #8960            ; 140*64
    bne @Pix

    ; Screen on
    lda #$0F
    sta.l $2100

    plb
    plp
    rtl

disableNMI:
    php
    sep #$20
    lda #$01
    sta.l $4200
    plp
    rtl

IRQTrampoline:
    rti

.ends
