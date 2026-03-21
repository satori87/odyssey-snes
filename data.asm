;; data.asm -- Mode 7 display + SuperFX control + IRQ-driven DMA (Doom-style)
;; IRQ at bottom of viewport triggers forced blank + DMA
;; IRQ at top of next frame re-enables display

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

.section ".mode7_sfx_code" superfree

;; Viewport: 160x80 pixels at ~1.6x scale = ~128 scanlines
;; Viewport starts at scanline 48 (centered: (224-128)/2 = 48)
;; Bottom IRQ at scanline 176 (48+128)
;; Top IRQ at scanline 47 (just before viewport)
.define VIEWPORT_TOP    48
.define VIEWPORT_BOTTOM 176

;; DMA state flag in WRAM
.define DMA_READY $7E1F00

;; -------------------------------------------------------
;; initMode3Display -- Mode 7 + IRQ setup (Doom-style)
;; -------------------------------------------------------
initMode3Display:
    php
    phb
    sep #$20
    rep #$10

    ; Force blank during setup
    lda #$80
    sta.l $2100

    ; Mode 7
    lda #$07
    sta.l $2105
    lda #$01
    sta.l $212C

    ; Mode 7 matrix: ~1.6x scale (A=D=$00A0)
    lda #$A0
    sta.l $211B
    lda #$00
    sta.l $211B
    lda #$00
    sta.l $211C
    sta.l $211C
    sta.l $211D
    sta.l $211D
    lda #$A0
    sta.l $211E
    lda #$00
    sta.l $211E

    ; Scroll to center viewport vertically
    ; M7VOFS: offset so viewport starts at scanline VIEWPORT_TOP
    ; With 1.6x scale, bg pixel 0 maps to screen pixel 0
    ; We want bg to start displaying at screen scanline 48
    ; M7VOFS = -(48 / 1.6) ≈ -30 = 256-30 = 226 (wraps in 13-bit)
    ; Actually, M7VOFS shifts the bg up. To push viewport down:
    ; Set M7VOFS negative so bg starts later on screen
    ; For simplicity, set VOFS = 0 (viewport at top)
    lda #$00
    sta.l $210D
    sta.l $210D
    sta.l $210E
    sta.l $210E
    sta.l $211F
    sta.l $211F
    sta.l $2120
    sta.l $2120

    ; Load palette
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

    ; Tilemap: 20x10, tile = row*20+col+1
    lda #$00
    sta.l $2115
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20
    ldy #$0000
@TM_RowLoop:
    cpy #$000A
    bcs @TM_BlankRow
    ldx #$0000
@TM_ColLoop:
    cpx #$0014
    bcs @TM_PadCol
    tya
    asl a
    asl a
    sta $50
    tya
    asl a
    asl a
    asl a
    asl a
    clc
    adc $50
    sta $50
    txa
    clc
    adc $50
    inc a
    sta.l $2118
    lda #$00
    sta.l $2119
    inx
    bra @TM_ColLoop
@TM_PadCol:
    lda #$00
    sta.l $2118
    sta.l $2119
    inx
    cpx #$0080
    bne @TM_PadCol
    iny
    bra @TM_RowLoop
@TM_BlankRow:
    ldx #$0000
@TM_BlankCol:
    lda #$00
    sta.l $2118
    sta.l $2119
    inx
    cpx #$0080
    bne @TM_BlankCol
    iny
    cpy #$0080
    bne @TM_RowLoop

    ; Clear tile pixel data
    lda #$80
    sta.l $2115
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20
    rep #$10
    ldy #$0000
@ClearTiles:
    lda #$00
    sta.l $2119
    iny
    cpy #12864
    bne @ClearTiles

    ; Initialize DMA_READY flag
    lda #$00
    sta.l DMA_READY

    ; Screen on
    lda #$0F
    sta.l $2100

    plb
    plp
    rtl

;; -------------------------------------------------------
;; initGSU -- Initialize SuperFX registers
;; -------------------------------------------------------
initGSU:
    php
    sep #$20
    lda #$01
    sta.l $3039          ; CLSR = 21 MHz
    lda #$A0
    sta.l $3037          ; CFGR
    lda #$1F
    sta.l $303A          ; SCMR
    lda #$01
    sta.l $3038          ; SCBR
    lda #$00
    sta.l $3034          ; PBR
    plp
    rtl

;; -------------------------------------------------------
;; startGSU -- Start GSU from WRAM stub
;; -------------------------------------------------------
startGSU:
    php
    phb
    sep #$20
    rep #$10

    ldx #$0000
@CopyLoop:
    lda.l @GSUStub,x
    sta.l $7E1E00,x
    inx
    cpx #(@GSUStubEnd - @GSUStub)
    bne @CopyLoop

    rep #$20
    lda #gsu_fill_screen - $8000
    sta.l $7E1E00 + (@GSUAddr - @GSUStub) + 1

    jml $7E1E00

@GSUStub:
    sep #$20
    lda #$00
    sta.l $3030
    rep #$20
@GSUAddr:
    lda #$0000
    sta.l $301E
    sep #$20
@WaitGSU:
    lda.l $3030
    and #$20
    bne @WaitGSU
    plb
    plp
    rtl
@GSUStubEnd:

;; -------------------------------------------------------
;; writeColumnData -- Copy 60 bytes from C global to $70:0000
;; -------------------------------------------------------
writeColumnData:
    php
    sep #$20
    rep #$10
    ldx #$0000
@WCD:
    lda.l columnData,x
    sta.l $700000,x
    inx
    cpx #$003C
    bne @WCD
    plp
    rtl

;; writePlayerState removed -- column data approach used instead

;; -------------------------------------------------------
;; dmaFramebuffer -- Split across 2 VBlanks (no forced blank during display)
;; VBlank 1: transfer strips 0-4 (6400 bytes, fits in VBlank)
;; VBlank 2: transfer strips 5-9 (6400 bytes, fits in VBlank)
;; Display stays ON the entire time — zero flicker
;; -------------------------------------------------------
dmaFramebuffer:
    php
    phb
    sep #$20
    rep #$10

    ; Give SNES access to SuperFX RAM for DMA
    lda #$17
    sta.l $303A          ; SCMR: SNES has RAM

    ; Configure DMA channel 0 (single channel, simple)
    lda #$00
    sta.l $4300          ; A->B, 1 register
    lda #$19
    sta.l $4301          ; destination: $2119 (VRAM high byte)
    lda #$70
    sta.l $4304          ; source bank: $70

    ; VMAIN: increment after high byte write
    lda #$80
    sta.l $2115

    ; Split into 3 batches that safely fit in VBlank (~5000 bytes each)
    ; Batch 1: strips 0-3 (4 × 1280 = 5120 bytes)
    ; Batch 2: strips 4-6 (3 × 1280 = 3840 bytes)
    ; Batch 3: strips 7-9 (3 × 1280 = 3840 bytes)

    ; === VBlank 1: strips 0-3 ===
@WaitVB1:
    lda.l $4212
    and #$80
    beq @WaitVB1
    rep #$20
    lda #$0040
    sta.l $2116
    lda #$0400
    sta.l $4302
    lda #5120
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; === VBlank 2: strips 4-6 ===
@WNV2:
    lda.l $4212
    and #$80
    bne @WNV2
@WVB2:
    lda.l $4212
    and #$80
    beq @WVB2
    rep #$20
    lda #$0040 + 5120
    sta.l $2116
    lda #$0400 + 5120
    sta.l $4302
    lda #3840
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; === VBlank 3: strips 7-9 ===
@WNV3:
    lda.l $4212
    and #$80
    bne @WNV3
@WVB3:
    lda.l $4212
    and #$80
    beq @WVB3
    rep #$20
    lda #$0040 + 5120 + 3840
    sta.l $2116
    lda #$0400 + 5120 + 3840
    sta.l $4302
    lda #3840
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Give GSU back RAM access
    lda #$1F
    sta.l $303A          ; SCMR: GSU has ROM/RAM

    ; Ensure display registers are correct
    lda #$07
    sta.l $2105
    lda #$01
    sta.l $212C
    lda #$0F
    sta.l $2100

    plb
    plp
    rtl

;; -------------------------------------------------------
restoreDisplayRegs:
    rtl

disableNMI:
    php
    sep #$20
    lda #$01             ; NMI off, auto-joypad ON (needed for readJoypad)
    sta.l $4200
    plp
    rtl

waitVBlankSimple:
    php
    sep #$20
@WNV:
    lda.l $4212
    and #$80
    bne @WNV
@WV:
    lda.l $4212
    and #$80
    beq @WV
    plp
    rtl

readJoypad:
    php
    sep #$20
@WA:
    lda.l $4212
    and #$01
    bne @WA              ; wait for auto-read complete
    rep #$20
    lda.l $4218
    sta.l tcc__r0
    plp
    rtl

.ends
