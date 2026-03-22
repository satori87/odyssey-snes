;; data.asm -- Mode 3 display + SuperFX control + DMA
;;
;; Architecture:
;;   - Mode 3 (BG1 256-color 8bpp) matching Doom SNES display approach
;;   - Viewport: 160x96 pixels = 20x12 chars = 240 tiles
;;   - BG1 chars at VRAM $0000
;;   - BG1 map at VRAM $4000
;;   - SuperFX plot writes bitplane-format tiles to $70:0400
;;   - DMA transfers from $70:0400 to VRAM $0000 (tile char data)
;;
;; Memory map for WRAM scratch area:
;;   $7E:1F00-1F03  JML stub (4 bytes: $5C + 3-byte address)
;;   $7E:1F10       DMA_DONE flag (set by bottom IRQ after DMA completes)

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
;; Constants
;; -------------------------------------------------------
.define VIEWPORT_BOTTOM  176   ; bottom IRQ fires here -> forced blank
.define IRQ_BOTTOM       176

;; WRAM addresses for IRQ stub and sync flag
.define JML_STUB         $7E1F00   ; 4 bytes: JML opcode + 24-bit target
.define DMA_DONE         $7E1F10   ; 1 byte: frame sync flag

;; NMITIMEN value: V-count IRQ + auto-joypad, NO NMI
.define NMITIMEN_VAL     $21       ; V-count IRQ + auto-joypad (no H-count, no NMI)

;; Display brightness value (full brightness, no forced blank)
.define INIDISP_ON       $0F

;; Tile data constants
.define VIEW_COLS        32        ; viewport tile columns (256 pixels, full width)
.define VIEW_ROWS        15        ; viewport tile rows (120 pixels, max for 32KB)
.define NUM_TILES        480       ; 32x15 tiles
.define PAD_TILE         480       ; black padding tile index (all zeros)
.define TILE_BYTES       64        ; 8bpp tile = 64 bytes
.define TILE_DATA_SIZE   30784     ; (480+1) * 64 = 30784 bytes (includes padding tile)
.define TILE_DATA_WORDS  15392     ; 30784 / 2

;; -------------------------------------------------------
;; IRQTrampoline -- ROM entry point for IRQ vector
;; The native IRQ vector in hdr.asm points here.
;; This jumps to the JML stub in WRAM which bounces to
;; the current handler (bottom or top).
;; -------------------------------------------------------
IRQTrampoline:
    jml JML_STUB         ; -> $7E:1F00 which contains JML to actual handler

;; -------------------------------------------------------
;; _IRQBottom -- Bottom-of-viewport IRQ handler
;; Forced blank -> DMA framebuffer -> restore display
;; -------------------------------------------------------
_IRQBottom:
    rep #$30
    pha
    phx
    phy
    phb
    phd

    sep #$20
    rep #$10

    ; Acknowledge IRQ
    lda.l $4211

    ; Forced blank
    lda #$80
    sta.l $2100

    ; === Give SNES access to SuperFX RAM for DMA ===
    lda #$16
    sta.l $303A          ; SCMR: SNES has RAM (ROM=SuperFX, RAM=SNES)

    ; === Configure VRAM address and increment ===
    lda #$80
    sta.l $2115          ; VMAIN: increment after high byte write

    ; VRAM destination: word address $0000 (tile data starts here)
    rep #$20
    lda #$0000
    sta.l $2116          ; VMADDL/VMADDH
    sep #$20

    ; === DMA channel 0: transfer tile data from $70:0400 to VRAM ===
    ; Mode 3 8bpp: use word-mode DMA (2-register write to $2118/$2119)
    lda #$01
    sta.l $4300          ; DMAP: A->B, 2-register (write to $2118 then $2119)
    lda #$18
    sta.l $4301          ; BBAD: destination = $2118 (VMDATAL)

    ; Source address: $70:0400 (SuperFX framebuffer)
    rep #$20
    lda #$0400
    sta.l $4302          ; A1T0L/A1T0H: source offset
    sep #$20
    lda #$70
    sta.l $4304          ; A1B0: source bank

    ; Transfer size: 15360 bytes (240 tiles * 64 bytes)
    rep #$20
    lda #TILE_DATA_SIZE
    sta.l $4305          ; DAS0L/DAS0H
    sep #$20

    ; Fire DMA!
    lda #$01
    sta.l $420B          ; MDMAEN: enable channel 0

    ; === Give GSU back RAM access ===
    lda #$1E
    sta.l $303A          ; SCMR: GSU has ROM+RAM

    ; === Set DMA_DONE flag ===
    lda #$01
    sta.l DMA_DONE

    ; === Wait for VBlank to end, then wait for NEXT VBlank ===
@WNV:
    lda.l $4212
    and #$80
    bne @WNV
@WVB:
    lda.l $4212
    and #$80
    beq @WVB

    ; === Re-enable display at VBlank start ===
    lda #$03
    sta.l $2105          ; Mode 3
    lda #$01
    sta.l $212C          ; TM = BG1
    lda #INIDISP_ON
    sta.l $2100          ; display ON

    ; === Keep V-count IRQ at scanline 176 for next frame ===
    lda #IRQ_BOTTOM
    sta.l $4209
    lda #$00
    sta.l $420A

    ; === Re-enable IRQs ===
    lda #NMITIMEN_VAL
    sta.l $4200
    lda.l $4211          ; clear pending

    pld
    plb
    ply
    plx

    rep #$20
    pla
    sep #$20

    rti

;; -------------------------------------------------------
;; setupIRQ -- Initialize the Doom-style IRQ system
;; Called once at startup after display init.
;; -------------------------------------------------------
setupIRQ:
    php
    sep #$20
    rep #$10

    ; === Write JML stub to WRAM at $7E:1F00 ===
    ; Byte 0: $5C = JML opcode
    lda #$5C
    sta.l JML_STUB

    ; Bytes 1-3: target = _IRQBottom
    rep #$20
    lda #_IRQBottom & $FFFF
    sta.l JML_STUB + 1
    sep #$20
    lda #:_IRQBottom
    sta.l JML_STUB + 3

    ; === Clear DMA_DONE flag ===
    lda #$00
    sta.l DMA_DONE

    ; === Set initial V-count IRQ to bottom scanline ===
    lda #IRQ_BOTTOM
    sta.l $4209          ; VTIMEL
    lda #$00
    sta.l $420A          ; VTIMEH

    ; === Set H-count IRQ position ===
    lda #96
    sta.l $4207          ; HTIMEL = 96
    lda #$00
    sta.l $4208          ; HTIMEH = 0

    ; === Enable V-count IRQ + auto-joypad in NMITIMEN ===
    lda #NMITIMEN_VAL
    sta.l $4200          ; NMITIMEN

    ; Clear TIMEUP to dismiss any pending IRQ
    lda.l $4211

    plp

    ; Enable IRQ on the 65816 CPU AFTER plp (so plp doesn't re-disable)
    cli

    rtl

;; -------------------------------------------------------
;; waitDMADone -- Spin until bottom IRQ completes DMA
;; Called by main loop for frame synchronization.
;; Returns after DMA_DONE flag is set, then clears it.
;; -------------------------------------------------------
waitDMADone:
    php
    sep #$20
    cli                  ; ensure IRQs are enabled during spin
@Wait:
    lda.l DMA_DONE
    beq @Wait            ; spin until IRQ sets the flag
    ; Clear the flag for next frame
    lda #$00
    sta.l DMA_DONE
    plp
    rtl

;; -------------------------------------------------------
;; initMode3Display -- Mode 3 (BG1 256-color 8bpp) setup
;;
;; Viewport: 160x96 pixels = 20x12 chars = 240 tiles
;; BG1 chars at VRAM $0000
;; BG1 map at VRAM $4000 (word addr $4000, 32x32)
;; -------------------------------------------------------
initMode3Display:
    php
    phb
    sep #$20
    rep #$10

    ; Force blank during setup
    lda #$80
    sta.l $2100

    ; Mode 3 (BG1=8bpp, BG2=4bpp)
    lda #$03
    sta.l $2105          ; BGMODE = $03

    ; BG1 tilemap at VRAM $7000, 32x32
    ; (moved from $4000 to avoid overlap with 896 tiles of char data)
    ; BG1SC = (base >> 8) | size = ($7000 >> 8) | 0 = $70
    lda #$70
    sta.l $2107          ; BG1SC

    ; BG1 character base at VRAM $0000
    ; BG12NBA: bits 0-3 = BG1 base (in 8K word units), bits 4-7 = BG2 base
    ; $0000 / $2000 = 0
    lda #$00
    sta.l $210B          ; BG12NBA

    ; TM = BG1 only
    lda #$01
    sta.l $212C          ; TM

    ; VMAIN: increment after high byte write
    lda #$80
    sta.l $2115

    ; === Load palette (256-color mode) ===
    ; Colors 0-15: texture palette
    lda #$00
    sta.l $2121          ; CGADD = 0
    ldx #$0000
@PalLoop:
    lda.l shared_palette,x
    sta.l $2122
    inx
    cpx #$0020           ; 16 colors * 2 bytes = 32 bytes
    bne @PalLoop

    ; Colors 16-17: ceiling and floor
    lda #16
    sta.l $2121          ; CGADD = 16
    ldx #$0000
@ExPalLoop:
    lda.l extra_palette,x
    sta.l $2122
    inx
    cpx #$0004           ; 2 colors * 2 bytes = 4 bytes
    bne @ExPalLoop

    ; === Build BG1 tilemap at VRAM $4000 ===
    ; Mode 3 tilemap entries are 16-bit:
    ;   bits 0-9: tile number (0-1023)
    ;   bits 10-12: palette number
    ;   bit 13: priority
    ;   bit 14: H-flip
    ;   bit 15: V-flip
    ; We use: tile N at row/col, all other bits = 0
    ;
    ; Layout: 20 columns x 12 rows of viewport tiles (indices 0-239)
    ; Remaining tiles in the 32x32 map are 0 (transparent/black)

    ; Set VRAM address to tilemap base
    ; VMAIN already set to $80 (increment after high write)
    rep #$20
    lda #$4000
    sta.l $2116          ; VMADDL/VMADDH = $4000
    sep #$20

    ; === Write 32x32 tilemap: sequential 0-895, then pad 896-1023 ===
    rep #$20
    lda #$7000
    sta.l $2116          ; VRAM address = tilemap base
    ; 896 sequential tiles (32×28 = full screen)
    ldx #$0000
@TM_View:
    txa
    sta.l $2118
    inx
    cpx #$0380           ; 896
    bne @TM_View
    ; 128 padding entries (tile 0, for the extra 4 tilemap rows)
    lda #$0000
    ldx #$0080           ; 128
@TM_Pad:
    sta.l $2118
    dex
    bne @TM_Pad
    sep #$20

    ; === Clear tile character data at VRAM $0000 ===
    ; === Write 3-band tile data to VRAM (full screen: 32x28 = 896 tiles) ===
    ; Band 1 (rows 0-8, 288 tiles): color 16 = BP4 set
    ; Band 2 (rows 9-18, 320 tiles): color 1 = BP0 set
    ; Band 3 (rows 19-27, 288 tiles): color 17 = BP0+BP4 set
    ; Each tile = 64 bytes. For uniform color:
    ;   BP group with bit set: 8 rows of ($FF, $00) = 16 bytes
    ;   BP group without: 8 rows of ($00, $00) = 16 bytes
    lda #$80
    sta.l $2115          ; VMAIN: word increment
    rep #$20
    lda #$0000
    sta.l $2116          ; VRAM addr = $0000
    sep #$20

    ; --- Band 1: 288 tiles, color 16 (00010000) ---
    ; BP0/1=$00/$00, BP2/3=$00/$00, BP4/5=$FF/$00, BP6/7=$00/$00
    rep #$10
    ldx #$0000           ; tile counter
@B1_Tile:
    ; BP0/1 group (16 bytes of $00)
    ldy #$0008
@B1_01:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B1_01
    ; BP2/3 group (16 bytes of $00)
    ldy #$0008
@B1_23:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B1_23
    ; BP4/5 group ($FF, $00 × 8)
    ldy #$0008
@B1_45:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @B1_45
    ; BP6/7 group (16 bytes of $00)
    ldy #$0008
@B1_67:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B1_67
    inx
    cpx #$0120           ; 288 tiles
    bne @B1_Tile

    ; --- Band 2: 320 tiles, color 1 (00000001) ---
    ; BP0/1=$FF/$00, rest $00
@B2_Tile:
    ; BP0/1 group ($FF, $00 × 8)
    ldy #$0008
@B2_01:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @B2_01
    ; BP2-7 (48 bytes of $00)
    ldy #$0018           ; 24 words = 48 bytes
@B2_rest:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B2_rest
    inx
    cpx #$0120 + $0140   ; 288 + 320 = 608
    bne @B2_Tile

    ; --- Band 3: 288 tiles, color 17 (00010001) ---
    ; BP0/1=$FF/$00, BP2/3=$00, BP4/5=$FF/$00, BP6/7=$00
@B3_Tile:
    ; BP0/1 ($FF, $00 × 8)
    ldy #$0008
@B3_01:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @B3_01
    ; BP2/3 ($00 × 16)
    ldy #$0008
@B3_23:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B3_23
    ; BP4/5 ($FF, $00 × 8)
    ldy #$0008
@B3_45:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @B3_45
    ; BP6/7 ($00 × 16)
    ldy #$0008
@B3_67:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B3_67
    inx
    cpx #$0380           ; 896 total tiles
    bne @B3_Tile

    ; Screen on (will be controlled by IRQ after setupIRQ)
    lda #INIDISP_ON
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
    lda #$1E
    sta.l $303A          ; SCMR: 160px wide, 256-color, GSU has ROM+RAM
    lda #$01
    sta.l $3038          ; SCBR: screen base = $70:0400 (bank 1 * $400)
    lda #$00
    sta.l $3034          ; PBR
    plp
    rtl

;; -------------------------------------------------------
;; startGSU -- Start GSU from WRAM stub
;; Sets SFR to start GSU execution at gsu_fill_screen
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
;; writePlayerState -- Copy 12 bytes of player state to $70:0000
;;
;; Player state layout in $70:0000 (all 8.8 fixed point):
;;   $0000: posX    (2 bytes)
;;   $0002: posY    (2 bytes)
;;   $0004: dirX    (2 bytes)
;;   $0006: dirY    (2 bytes)
;;   $0008: planeX  (2 bytes)
;;   $000A: planeY  (2 bytes)
;;
;; Reads from C globals: posX, posY, dirX, dirY, planeX, planeY
;; -------------------------------------------------------
writePlayerState:
    php
    sep #$20
    rep #$10

    ; === Give SNES access to SuperFX RAM ===
    lda #$16
    sta.l $303A          ; SCMR: SNES has RAM

    rep #$20

    ; posX -> $70:0000
    lda.l posX
    sta.l $700000

    ; posY -> $70:0002
    lda.l posY
    sta.l $700002

    ; dirX -> $70:0004
    lda.l dirX
    sta.l $700004

    ; dirY -> $70:0006
    lda.l dirY
    sta.l $700006

    ; planeX -> $70:0008
    lda.l planeX
    sta.l $700008

    ; planeY -> $70:000A
    lda.l planeY
    sta.l $70000A

    sep #$20

    ; === Give GSU back RAM access ===
    lda #$1E
    sta.l $303A          ; SCMR: GSU has ROM+RAM

    plp
    rtl

;; -------------------------------------------------------
;; disableNMI -- Disable NMI, keep auto-joypad
;; -------------------------------------------------------
disableNMI:
    php
    sep #$20
    lda #$01             ; NMI off, auto-joypad ON
    sta.l $4200
    plp
    rtl

;; -------------------------------------------------------
;; readJoypad -- Read auto-joypad result
;; -------------------------------------------------------
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

;; -------------------------------------------------------
;; Legacy stubs (kept for linkage compatibility)
;; -------------------------------------------------------
dmaFramebuffer:
    php
    sep #$20
    rep #$10
    ; Force blank
    lda #$80
    sta.l $2100
    ; Give SNES RAM access
    lda #$16
    sta.l $303A
    ; VMAIN: word increment
    lda #$80
    sta.l $2115
    ; VRAM addr = $0000
    rep #$20
    lda #$0000
    sta.l $2116
    sep #$20
    ; DMA setup: word-mode to $2118/$2119
    lda #$01
    sta.l $4300          ; DMAP: 2-register word write
    lda #$18
    sta.l $4301          ; BBAD: $2118 (VMDATAL)
    rep #$20
    lda #$0400
    sta.l $4302
    sep #$20
    lda #$70
    sta.l $4304
    rep #$20
    lda #TILE_DATA_SIZE  ; 15360 bytes
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B
    ; Give GSU back RAM
    lda #$1E
    sta.l $303A
    ; Screen on with Mode 3
    lda #$03
    sta.l $2105          ; Mode 3
    lda #$01
    sta.l $212C          ; BG1
    lda #$0F
    sta.l $2100
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

restoreDisplayRegs:
    rtl

.ends
