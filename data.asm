;; data.asm -- Mode 7 display setup + SuperFX control + helper functions
;; Mode 7 for display (1 byte per pixel tiles), SuperFX for pixel plotting
;;
;; Display: 160x80 pixels = 20 columns x 10 rows of 8x8 tiles
;; Mode 7 scaling: ~1.6x zoom so 160 tile pixels fill 256 screen pixels
;; Tile data: 200 tiles (1-200) at VRAM high bytes, tile 0 = black
;; Tilemap: Mode 7 128x128 at VRAM low bytes
;; GSU writes tile-format framebuffer at $70:0400, DMA'd to VRAM high bytes

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

.section ".mode3_sfx_code" superfree

;; -------------------------------------------------------
;; initMode3Display -- Mode 7 setup for 160x80 tile display
;;   Matrix: A=D=$00A0 (1/1.6 scale), B=C=$0000
;;   Tilemap: 128x128 entries, first 20x10 have tile 1-200
;;   Palette: shared_palette (0-15) + extra_palette (16-17)
;; -------------------------------------------------------
initMode3Display:
    php
    phb
    sep #$20
    rep #$10

    ; Force blank ON
    lda #$80
    sta.l $2100

    ; BGMODE = $07 (Mode 7)
    lda #$07
    sta.l $2105

    ; Enable BG1 on main screen
    lda #$01
    sta.l $212C

    ; ----- Mode 7 matrix -----
    ; A parameter = $00A0 = 160 (0.625 in 8.8 = 1/1.6)
    ; 256 screen pixels show 160 tile pixels
    lda #$A0
    sta.l $211B          ; M7A low byte
    lda #$00
    sta.l $211B          ; M7A high byte

    ; B = $0000 (no rotation)
    lda #$00
    sta.l $211C
    sta.l $211C

    ; C = $0000 (no rotation)
    lda #$00
    sta.l $211D
    sta.l $211D

    ; D = $00A0 (same vertical scale)
    lda #$A0
    sta.l $211E
    lda #$00
    sta.l $211E

    ; Scroll offsets = 0
    lda #$00
    sta.l $210D
    sta.l $210D
    sta.l $210E
    sta.l $210E

    ; Center point = (0, 0)
    lda #$00
    sta.l $211F
    sta.l $211F
    sta.l $2120
    sta.l $2120

    ; ----- Load palette -----
    lda #$00
    sta.l $2121          ; CGADD = 0
    ldx #$0000
@PalLoop:
    lda.l shared_palette,x
    sta.l $2122
    inx
    cpx #$0020           ; 16 colors x 2 bytes = 32 bytes
    bne @PalLoop

    ; Colors 16-17: ceiling and floor
    lda #16
    sta.l $2121
    ldx #$0000
@ExPalLoop:
    lda.l extra_palette,x
    sta.l $2122
    inx
    cpx #$0004           ; 2 colors x 2 bytes
    bne @ExPalLoop

    ; ----- Build Mode 7 tilemap (VRAM low bytes) -----
    ; Set increment after $2118 write (low byte)
    lda #$00
    sta.l $2115

    ; VRAM address = $0000
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20

    ; Write 128x128 tilemap entries
    ; Active area: rows 0-9, cols 0-19 = tile numbers 1-200
    ; Everything else: tile 0 (black)
    ldy #$0000           ; row counter (0..127)

@TM_RowLoop:
    cpy #$000A           ; 10 active rows
    bcs @TM_BlankRow

    ; Active row: 20 tiles then 108 blanks
    ldx #$0000           ; col counter
@TM_ColLoop:
    cpx #$0014           ; 20 active columns
    bcs @TM_PadCol

    ; Tile # = row*20 + col + 1
    tya
    asl a                ; *2
    asl a                ; *4
    sta $50              ; $50 = row*4
    asl a                ; *8
    asl a                ; *16
    clc
    adc $50              ; A = row*20
    sta $50
    txa                  ; A = col
    clc
    adc $50              ; A = row*20 + col
    inc a                ; +1 (1-based tile number)
    sta.l $2118          ; write tilemap entry (low byte), addr increments

    inx
    bra @TM_ColLoop

@TM_PadCol:
    lda #$00
    sta.l $2118          ; tile 0 = black
    inx
    cpx #$0080           ; 128 columns per row
    bne @TM_PadCol
    iny
    bra @TM_RowLoop

@TM_BlankRow:
    ldx #$0000
@TM_BlankCol:
    lda #$00
    sta.l $2118
    inx
    cpx #$0080           ; 128 entries per row
    bne @TM_BlankCol
    iny
    cpy #$0080           ; 128 rows
    bne @TM_RowLoop

    ; ----- Clear all tile pixel data (VRAM high bytes) -----
    ; Switch to increment after $2119 write
    lda #$80
    sta.l $2115

    ; Start at VRAM address $0000
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20

    ; Clear 201 tiles worth of pixel data (tile 0 + tiles 1-200)
    ; Each tile = 64 bytes, 201*64 = 12864 bytes
    rep #$10
    ldy #$0000
@ClearPixels:
    lda #$00
    sta.l $2119          ; write high byte (pixel data), addr increments
    iny
    cpy #12864
    bne @ClearPixels

    ; Screen on, full brightness
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
    ; 21MHz clock speed
    lda #$01
    sta.l $3039          ; CLSR
    ; IRQ disable
    lda #$A0
    sta.l $3037          ; CFGR
    ; Screen mode: RON=1, RAN=1, 256-color, OBJ mode
    lda #$1F
    sta.l $303A          ; SCMR
    ; Screen base: SCBR=1 -> base at $70:0400
    lda #$01
    sta.l $3038          ; SCBR
    ; Program bank
    lda #$00
    sta.l $3034          ; PBR
    plp
    rtl

;; -------------------------------------------------------
;; startGSU -- Start GSU from WRAM stub (avoids ROM bus conflict)
;; -------------------------------------------------------
startGSU:
    php
    phb
    sep #$20
    rep #$10

    ; Copy stub to WRAM $7E:1E00
    ldx #$0000
@CopyLoop:
    lda.l @GSUStub,x
    sta.l $7E1E00,x
    inx
    cpx #(@GSUStubEnd - @GSUStub)
    bne @CopyLoop

    ; Patch GSU entry address (LoROM: label - $8000)
    rep #$20
    lda #gsu_fill_screen - $8000
    sta.l $7E1E00 + (@GSUAddr - @GSUStub) + 1

    ; Execute from WRAM
    jml $7E1E00

@GSUStub:
    sep #$20
    lda #$00
    sta.l $3030          ; clear SFR
    rep #$20
@GSUAddr:
    lda #$0000           ; patched with gsu_fill_screen - $8000
    sta.l $301E          ; R15 = program counter -> starts GSU
    sep #$20
@WaitGSU:
    lda.l $3030
    and #$20             ; bit 5 = running
    bne @WaitGSU
    plb
    plp
    rtl
@GSUStubEnd:

;; -------------------------------------------------------
;; writeColumnData -- Copy columnData[60] from C global to $70:0000
;; -------------------------------------------------------
writeColumnData:
    php
    phb
    sep #$20
    rep #$10

    ldx #$0000
@WCD_Loop:
    lda.l columnData,x
    sta.l $700000,x
    inx
    cpx #$003C           ; 60 bytes (20 cols x 3 bytes)
    bne @WCD_Loop

    plb
    plp
    rtl

;; -------------------------------------------------------
;; dmaFramebuffer -- DMA tile pixel data from $70:0400 to VRAM
;;   Mode 7 tile pixels are in VRAM high bytes
;;   200 tiles (1-200) x 64 bytes = 12800 bytes
;;   Tile 1 at VRAM word addr $0040 (tile 0 = 64 words @ $0000-$003F)
;;   DMA to $2119 only (high byte), increment after $2119
;; -------------------------------------------------------
dmaFramebuffer:
    php
    phb
    sep #$20
    rep #$10

    ; Force blank ON
    lda #$80
    sta.l $2100

    ; Increment after $2119 write (high byte)
    lda #$80
    sta.l $2115

    ; VRAM address = tile 1 start = $0040
    rep #$20
    lda #$0040
    sta.l $2116
    sep #$20

    ; DMA channel 0: A-bus -> B-bus ($2119), 1 register
    lda #$00
    sta.l $4300          ; DMA control: A->B, 1 register, no increment mode
    lda #$19             ; destination: VRAM high byte
    sta.l $4301

    ; Source: $70:0400
    rep #$20
    lda #$0400
    sta.l $4302
    sep #$20
    lda #$70
    sta.l $4304

    ; Size: 12800 bytes
    rep #$20
    lda #12800
    sta.l $4305
    sep #$20

    ; Execute DMA
    lda #$01
    sta.l $420B

    plb
    plp
    rtl

;; -------------------------------------------------------
;; restoreDisplayRegs -- Restore display after DMA
;; -------------------------------------------------------
restoreDisplayRegs:
    php
    sep #$20
    lda #$07
    sta.l $2105          ; Mode 7
    lda #$01
    sta.l $212C          ; BG1 on main screen
    lda #$0F
    sta.l $2100          ; full brightness
    plp
    rtl

;; -------------------------------------------------------
;; disableNMI -- Disable NMI, keep joypad auto-read
;; -------------------------------------------------------
disableNMI:
    php
    sep #$20
    lda #$01
    sta.l $4200
    plp
    rtl

;; -------------------------------------------------------
;; waitVBlankSimple -- Spin-wait for VBlank
;; -------------------------------------------------------
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

;; -------------------------------------------------------
;; readJoypad -- Read controller 1, return in tcc__r0
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

.ends
