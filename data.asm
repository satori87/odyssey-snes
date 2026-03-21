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
.define NUM_TILES        240       ; 20x12 tiles
.define TILE_BYTES       64        ; 8bpp tile = 64 bytes
.define TILE_DATA_SIZE   15360     ; 240 * 64 = 15360 bytes
.define TILE_DATA_WORDS  7680      ; 15360 / 2

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
    lda #$17
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
    lda #$1F
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

    ; BG1 tilemap at VRAM $4000, 32x32
    ; BG1SC = (base >> 8) | size
    ; VRAM word addr $4000 -> base = $40, size = 0 (32x32)
    lda #$40
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

    ; Tile index counter
    ldx #$0000           ; tile index (0-239)
    ldy #$0000           ; row counter (0-31)
@TM_RowLoop:
    cpy #$000C           ; 12 tile rows for viewport
    bcs @TM_BlankRow

    ; Columns 0-19: viewport tiles
    phx                  ; save tile index on stack
    ldx #$0000           ; column counter
@TM_ColLoop:
    cpx #$0014           ; 20 columns
    bcs @TM_PadCol

    ; Write tile index (16-bit: lo then hi via $2118/$2119)
    ; Pull current tile index from stack, write, push incremented
    ply                  ; Y = current tile index
    rep #$20
    tya
    sta.l $2118          ; VMDATAL/VMDATAH (writes both bytes, auto-increments VRAM addr)
    sep #$20
    iny                  ; next tile index
    phy                  ; save it back
    inx
    bra @TM_ColLoop

@TM_PadCol:
    ; Columns 20-31: blank tiles (tile 0 = black)
    rep #$20
    lda #$0000
    sta.l $2118
    sep #$20
    inx
    cpx #$0020           ; 32 columns total
    bne @TM_PadCol

    plx                  ; restore tile index (was on stack from phy)
    iny                  ; next row
    bra @TM_RowLoop

@TM_BlankRow:
    ; Rows 12-31: all blank tiles
    ldx #$0000
@TM_BlankCol:
    rep #$20
    lda #$0000
    sta.l $2118
    sep #$20
    inx
    cpx #$0020           ; 32 columns
    bne @TM_BlankCol
    iny
    cpy #$0020           ; 32 rows total
    bne @TM_RowLoop

    ; === Clear tile character data at VRAM $0000 ===
    ; 240 tiles * 32 words each = 7680 words
    lda #$80
    sta.l $2115          ; VMAIN: word increment
    rep #$20
    lda #$0000
    sta.l $2116          ; VRAM addr = $0000
    sep #$20
    rep #$10
    ldy #$0000
@ClearTiles:
    lda #$00
    sta.l $2118          ; VMDATAL
    sta.l $2119          ; VMDATAH (triggers increment)
    iny
    iny                  ; count by 2 (we wrote 2 bytes = 1 word)
    cpy #TILE_DATA_SIZE
    bne @ClearTiles

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
    lda #$1F
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
    lda #$17
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
    lda #$1F
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

    ; Give SNES RAM access for DMA
    lda #$17
    sta.l $303A

    ; DMA setup: word-mode to $2118/$2119 (same for all 3 batches)
    lda #$01
    sta.l $4300          ; DMAP: 2-register word write
    lda #$18
    sta.l $4301          ; BBAD: $2118 (VMDATAL)
    lda #$70
    sta.l $4304          ; source bank $70
    lda #$80
    sta.l $2115          ; VMAIN: word increment

    ; === Batch 1: rows 0-3 (5120 bytes) during VBlank ===
@WV1:
    lda.l $4212
    and #$80
    beq @WV1
    rep #$20
    lda #$0000
    sta.l $2116          ; VRAM addr
    lda #$0400
    sta.l $4302          ; source: $70:0400
    lda #5120
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; === Batch 2: rows 4-7 (5120 bytes) during next VBlank ===
@WNV2:
    lda.l $4212
    and #$80
    bne @WNV2
@WV2:
    lda.l $4212
    and #$80
    beq @WV2
    rep #$20
    lda #$0000 + 2560    ; VRAM word addr after batch 1
    sta.l $2116
    lda #$0400 + 5120    ; source offset after batch 1
    sta.l $4302
    lda #5120
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; === Batch 3: rows 8-11 (5120 bytes) during next VBlank ===
@WNV3:
    lda.l $4212
    and #$80
    bne @WNV3
@WV3:
    lda.l $4212
    and #$80
    beq @WV3
    rep #$20
    lda #$0000 + 5120    ; VRAM word addr after batch 2
    sta.l $2116
    lda #$0400 + 10240   ; source offset after batch 2
    sta.l $4302
    lda #5120
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Give GSU back RAM
    lda #$1F
    sta.l $303A

    ; Ensure display regs correct
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
