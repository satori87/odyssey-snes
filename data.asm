;; data.asm -- Mode 7 display + SuperFX control + Doom-exact IRQ-driven DMA
;;
;; Architecture (matching Doom SNES source):
;;   - JML stub at $7E:1F00 in WRAM (4 bytes: JML opcode + 3-byte target)
;;   - IRQ vector in ROM -> IRQTrampoline -> JML $7E1F00 -> handler
;;   - Bottom IRQ (scanline 176): forced blank + DMA 12800 bytes
;;   - NMITIMEN = $21: V-count IRQ + auto-joypad, NO NMI
;;   - DMA runs during VBlank
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

.section ".mode7_sfx_code" superfree

;; -------------------------------------------------------
;; Constants
;; -------------------------------------------------------
.define VIEWPORT_TOP     48    ; first visible scanline of viewport
.define VIEWPORT_BOTTOM  176   ; last visible scanline of viewport
.define IRQ_BOTTOM       176   ; bottom IRQ fires here -> forced blank

;; WRAM addresses for IRQ stub and sync flag
.define JML_STUB         $7E1F00   ; 4 bytes: JML opcode + 24-bit target
.define DMA_DONE         $7E1F10   ; 1 byte: frame sync flag

;; NMITIMEN value: V-count IRQ + auto-joypad, NO NMI
.define NMITIMEN_VAL     $21       ; V-count IRQ + auto-joypad (no H-count, no NMI)

;; Display brightness value (full brightness, no forced blank)
.define INIDISP_ON       $0F

;; -------------------------------------------------------
;; IRQTrampoline -- ROM entry point for IRQ vector
;; The native IRQ vector in hdr.asm points here.
;; This jumps to the JML stub in WRAM which bounces to
;; the current handler (bottom or top).
;; -------------------------------------------------------
IRQTrampoline:
    jml JML_STUB         ; -> $7E:1F00 which contains JML to actual handler

;; -------------------------------------------------------
;; _IRQBottom -- Bottom-of-viewport IRQ handler (scanline 176)
;; Like Doom: forced blank -> DMA framebuffer -> set next IRQ to top
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

    ; Forced blank (we're at scanline 176, viewport already displayed)
    lda #$80
    sta.l $2100

    ; === Give SNES access to SuperFX RAM for DMA ===
    lda #$17
    sta.l $303A          ; SCMR: SNES has RAM (ROM=SuperFX, RAM=SNES)

    ; === Configure VRAM address and increment ===
    lda #$80
    sta.l $2115          ; VMAIN: increment after high byte write ($2119)

    ; VRAM destination: word address $0040 (tile 1 starts at byte $80 = word $40)
    ; Tiles 1-200 in VRAM, each 64 bytes, starting at word $0040
    rep #$20
    lda #$0040
    sta.l $2116          ; VMADDL/VMADDH
    sep #$20

    ; === DMA channel 0: transfer 12800 bytes from $70:0400 to VRAM ===
    lda #$00
    sta.l $4300          ; DMA control: A->B, 1 register, no increment mode byte
    lda #$19
    sta.l $4301          ; destination: $2119 (VRAM data high byte)

    ; Source address: $70:0400 (SuperFX framebuffer)
    rep #$20
    lda #$0400
    sta.l $4302          ; A1T0L/A1T0H: source offset
    sep #$20
    lda #$70
    sta.l $4304          ; A1B0: source bank

    ; Transfer size: 12800 bytes (200 tiles * 64 bytes)
    rep #$20
    lda #12800
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
    ; DMA finished during VBlank. Wait for active display to start...
@WNV:
    lda.l $4212
    and #$80
    bne @WNV
    ; ...then wait for next VBlank (ensures full frame before display on)
@WVB:
    lda.l $4212
    and #$80
    beq @WVB

    ; === Re-enable display at VBlank start ===
    lda #$07
    sta.l $2105          ; Mode 7
    lda #$01
    sta.l $212C          ; BG1
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
;; initMode7Display -- Mode 7 display setup
;; -------------------------------------------------------
initMode7Display:
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

    ; Scroll: VOFS/HOFS = 0 and Mode 7 center = 0
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
    sta.l $303A          ; SCMR
    lda #$01
    sta.l $3038          ; SCBR
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
;; Legacy stubs (kept for linkage, should not be called)
;; -------------------------------------------------------
dmaFramebuffer:
    php
    sep #$20
    rep #$10
    ; Force blank
    lda #$80
    sta.l $2100
    ; Give SNES RAM access
    lda #$17
    sta.l $303A
    ; VMAIN
    lda #$80
    sta.l $2115
    ; VRAM addr
    rep #$20
    lda #$0040
    sta.l $2116
    sep #$20
    ; DMA setup
    lda #$00
    sta.l $4300
    lda #$19
    sta.l $4301
    rep #$20
    lda #$0400
    sta.l $4302
    sep #$20
    lda #$70
    sta.l $4304
    rep #$20
    lda #12800
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B
    ; Give GSU back RAM
    lda #$1F
    sta.l $303A
    ; Screen on
    lda #$07
    sta.l $2105
    lda #$01
    sta.l $212C
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
