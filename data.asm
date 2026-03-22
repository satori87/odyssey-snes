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
.define VIEWPORT_BOTTOM  184   ; bottom IRQ fires here -> forced blank (after 144px viewport + 5 rows border)
.define IRQ_BOTTOM       184

;; WRAM addresses for IRQ stub and sync flag
.define JML_STUB         $7E1F00   ; 4 bytes: JML opcode + 24-bit target
.define DMA_DONE         $7E1F10   ; 1 byte: frame sync flag

;; NMITIMEN value: V-count IRQ + auto-joypad, NO NMI
.define NMITIMEN_VAL     $21       ; V-count IRQ + auto-joypad (no H-count, no NMI)

;; Display brightness value (full brightness, no forced blank)
.define INIDISP_ON       $0F

;; Tile data constants
.define VIEW_COLS        27        ; viewport tile columns (216 pixels, matching Doom)
.define VIEW_ROWS        18        ; viewport tile rows (144 pixels, matching Doom)
.define NUM_TILES        486       ; 27x18 viewport tiles
.define TILE_BYTES       64        ; 8bpp tile = 64 bytes
.define TILE_DATA_SIZE   31104     ; 486 * 64 bytes (GSU framebuffer, DMA'd each frame)
.define TILE_DATA_WORDS  15552     ; 31104 / 2
; Border tiles (static, written to VRAM during init, not DMA'd)
.define BORDER_CEIL      486       ; ceiling blue tile
.define BORDER_FLOOR     487       ; floor green tile
.define BORDER_BLACK     488       ; black tile
.define BORDER_WALL      489       ; wall brown tile
.define BORDER_HUD       490       ; HUD yellow tile
.define HUD_ROWS         4         ; 4 tile rows for status bar (32px, like Doom)
; Doom layout: viewport at top, HUD space below
; Hardware window masks display to 216px centered (pixels 20-235)
; BG scroll positions viewport tiles to align with window
.define VP_LEFT          0         ; viewport tiles at tilemap column 0
.define VP_TOP           0         ; viewport at top of screen
; Window edges (same as Doom: (256-216)/2 = 20)
.define WIN_LEFT         20        ; window left edge pixel
.define WIN_RIGHT        235       ; window right edge pixel (256-1-20)

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

    ; === Doom-style hardware window (masks display to 216px centered) ===
    ; Window 1 edges: left=20, right=235 (shows only pixels 20-235)
    lda #WIN_LEFT
    sta.l $2126          ; WH0 = window 1 left edge
    lda #WIN_RIGHT
    sta.l $2127          ; WH1 = window 1 right edge

    ; Enable Window 1 for BG1, inverted
    ; TMW disables BG1 where mask=1. Inverted: mask=1 OUTSIDE window.
    ; Result: BG1 disabled outside window, visible inside (pixels 20-235)
    lda #$03
    sta.l $2123          ; W12SEL: BG1 Window 1 enabled + inverted

    ; Apply window masking to BG1 on main screen
    lda #$01
    sta.l $212E          ; TMW: BG1 uses window

    ; Window logic = OR (default)
    lda #$00
    sta.l $212A          ; WBGLOG
    sta.l $212B          ; WOBJLOG

    ; BG1 horizontal scroll: position tilemap so column 0 appears at pixel 20
    ; Formula: screen_x = tilemap_x - BG_HOFS → BG_HOFS = -(WIN_LEFT) = 1004
    lda #$EC
    sta.l $210D          ; BG1HOFS low byte (1004 & $FF = $EC)
    lda #$03
    sta.l $210D          ; BG1HOFS high byte (1004 >> 8 = $03)

    ; BG1 vertical scroll: center 176px (viewport+HUD) in 224px screen
    ; Total = 18 viewport + 4 HUD = 22 rows = 176px (same as Doom)
    ; Top border = (224-176)/2 = 24px. BG_VOFS = -(24) = 1024-24 = 1000 ($03E8)
    lda #$E8
    sta.l $210E          ; BG1VOFS low byte (1000 & $FF)
    lda #$03
    sta.l $210E          ; BG1VOFS high byte (1000 >> 8)

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

    ; === Write 32x32 tilemap: centered 27x18 viewport with colored borders ===
    ; Viewport at cols 3-29, rows 5-22. Borders: blue top, green bottom, black sides
    rep #$20
    lda #$7000
    sta.l $2116          ; VRAM address = tilemap base
    ldx #$0000           ; X = viewport tile index (0-485)
    ldy #$0000           ; Y = row counter
    stz.b $00            ; column = 0
@TM_Entry:
    ; Check if inside viewport area (rows 0-17, cols 0-26)
    cpy #VP_TOP + VIEW_ROWS  ; row >= 18?
    bcs @TM_CheckHUD
    ; Viewport row. Check column.
    lda.b $00
    cmp #VP_LEFT + VIEW_COLS  ; col >= 27?
    bcs @TM_Black
    ; Viewport tile
    txa
    sta.l $2118
    inx
    bra @TM_Advance
@TM_CheckHUD:
    ; Check if inside HUD area (rows 18-21, cols 0-26)
    cpy #VP_TOP + VIEW_ROWS + HUD_ROWS  ; row >= 22?
    bcs @TM_Black
    lda.b $00
    cmp #VP_LEFT + VIEW_COLS  ; col >= 27?
    bcs @TM_Black
    ; HUD tile (yellow)
    lda #BORDER_HUD
    sta.l $2118
    bra @TM_Advance
@TM_Black:
    ; All borders are black (invisible)
    lda #BORDER_BLACK
    sta.l $2118
@TM_Advance:
    lda.b $00
    inc a
    cmp #$0020           ; 32 columns?
    bne @TM_Store
    lda #$0000           ; reset column
    iny                  ; next row
@TM_Store:
    sta.b $00
    cpy #$0020           ; 32 rows done?
    bne @TM_Entry
    sep #$20

    ; === Clear tile character data at VRAM $0000 ===
    ; === Write tile data: 486 viewport tiles + 3 border tiles ===
    ; Viewport: 3 bands of 6 rows (162 tiles each)
    ; Border tiles: 486=ceil blue, 487=floor green, 488=black
    lda #$80
    sta.l $2115          ; VMAIN: word increment
    rep #$20
    lda #$0000
    sta.l $2116          ; VRAM addr = $0000
    sep #$20

    ; --- Band 1: 162 tiles, color 16 (BP4=$FF) ---
    rep #$10
    ldx #$0000
@B1_Tile:
    ldy #$0008
@B1_01:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B1_01
    ldy #$0008
@B1_23:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B1_23
    ldy #$0008
@B1_45:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @B1_45
    ldy #$0008
@B1_67:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B1_67
    inx
    cpx #$00A2           ; 162
    bne @B1_Tile

    ; --- Band 2: 162 tiles, color 1 (BP0=$FF) ---
@B2_Tile:
    ldy #$0008
@B2_01:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @B2_01
    ldy #$0018
@B2_rest:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B2_rest
    inx
    cpx #$0144           ; 324
    bne @B2_Tile

    ; --- Band 3: 162 tiles, color 17 (BP0+BP4=$FF) ---
@B3_Tile:
    ldy #$0008
@B3_01:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @B3_01
    ldy #$0008
@B3_23:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B3_23
    ldy #$0008
@B3_45:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @B3_45
    ldy #$0008
@B3_67:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @B3_67
    inx
    cpx #$01E6           ; 486
    bne @B3_Tile

    ; --- Tile 486: ceiling blue (color 16, BP4=$FF) ---
    ; VRAM continues sequentially after tile 485
    ldy #$0008
@BC_01:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BC_01
    ldy #$0008
@BC_23:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BC_23
    ldy #$0008
@BC_45:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @BC_45
    ldy #$0008
@BC_67:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BC_67

    ; --- Tile 487: floor green (color 17, BP0+BP4=$FF) ---
    ldy #$0008
@BF_01:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @BF_01
    ldy #$0008
@BF_23:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BF_23
    ldy #$0008
@BF_45:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @BF_45
    ldy #$0008
@BF_67:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BF_67

    ; --- Tile 488: black (all $00) ---
    ldy #$0020
@BK:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BK

    ; --- Tile 489: wall brown (color 1, BP0=$FF) ---
    ldy #$0008
@BW_01:
    lda #$FF
    sta.l $2118
    lda #$00
    sta.l $2119
    dey
    bne @BW_01
    ldy #$0018
@BW_rest:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BW_rest

    ; --- Tile 490: HUD yellow (color 18, BP1+BP4=$FF) ---
    ; Color 18 = %00010010 → BP1=$FF, BP4=$FF, rest $00
    ldy #$0008
@BH_01:
    lda #$00             ; BP0
    sta.l $2118
    lda #$FF             ; BP1
    sta.l $2119
    dey
    bne @BH_01
    ldy #$0008
@BH_23:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BH_23
    ldy #$0008
@BH_45:
    lda #$FF             ; BP4
    sta.l $2118
    lda #$00             ; BP5
    sta.l $2119
    dey
    bne @BH_45
    ldy #$0008
@BH_67:
    lda #$00
    sta.l $2118
    sta.l $2119
    dey
    bne @BH_67

    ; === Add yellow to palette at color 18 ===
    sep #$20
    lda #18
    sta.l $2121          ; CGADD = 18
    ; Yellow in BGR555: R=31, G=31, B=0 → %0000011111_11111 = $03FF
    lda #$FF             ; low byte
    sta.l $2122
    lda #$03             ; high byte
    sta.l $2122

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
;; writePlayerState -- Copy player state to $70:0000
;;
;; BSP player state layout:
;;   $0000: ViewX       (2 bytes, world coordinates)
;;   $0002: ViewY       (2 bytes, world coordinates)
;;   $0004: ViewAngle   (2 bytes, low byte = angle 0-255)
;;
;; Reads from C globals: posX, posY, playerAngle
;; -------------------------------------------------------
writePlayerState:
    php
    sep #$20
    rep #$10

    ; === Give SNES access to SuperFX RAM ===
    lda #$16
    sta.l $303A          ; SCMR: SNES has RAM

    rep #$20

    ; posX -> $70:0000 (ViewX)
    lda.l posX
    sta.l $700000

    ; posY -> $70:0002 (ViewY)
    lda.l posY
    sta.l $700002

    sep #$20

    ; playerAngle -> $70:0004 (ViewAngle)
    lda.l playerAngle
    sta.l $700004
    lda #$00
    sta.l $700005        ; high byte = 0

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

    ; Give SNES RAM access
    lda #$16
    sta.l $303A

    ; DMA setup (constant across all batches)
    lda #$01
    sta.l $4300          ; DMAP: 2-register word write
    lda #$18
    sta.l $4301          ; BBAD: $2118 (VMDATAL)
    lda #$70
    sta.l $4304          ; source bank $70
    lda #$80
    sta.l $2115          ; VMAIN: word increment

    ; === 6-batch VBlank DMA: 6 × 5184 = 31104 bytes ===
    ; No forced blank — DMA only during VBlank, no flicker

    ; Batch 1: VRAM $0000, source $0400, 5184 bytes
@WNV1:
    lda.l $4212
    and #$80
    bne @WNV1
@WV1:
    lda.l $4212
    and #$80
    beq @WV1
    rep #$20
    lda #$0000
    sta.l $2116
    lda #$0400
    sta.l $4302
    lda #5184
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Batch 2: VRAM $0A20, source $1844, 5184 bytes
@WNV2:
    lda.l $4212
    and #$80
    bne @WNV2
@WV2:
    lda.l $4212
    and #$80
    beq @WV2
    rep #$20
    lda #$0A20           ; 5184/2 = 2592 words
    sta.l $2116
    lda #$0400 + 5184
    sta.l $4302
    lda #5184
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Batch 3: VRAM $1440, source $2C88, 5184 bytes
@WNV3:
    lda.l $4212
    and #$80
    bne @WNV3
@WV3:
    lda.l $4212
    and #$80
    beq @WV3
    rep #$20
    lda #$1440           ; 2 × 2592
    sta.l $2116
    lda #$0400 + 10368
    sta.l $4302
    lda #5184
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Batch 4: VRAM $1E60, source $40CC, 5184 bytes
@WNV4:
    lda.l $4212
    and #$80
    bne @WNV4
@WV4:
    lda.l $4212
    and #$80
    beq @WV4
    rep #$20
    lda #$1E60           ; 3 × 2592
    sta.l $2116
    lda #$0400 + 15552
    sta.l $4302
    lda #5184
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Batch 5: VRAM $2880, source $5510, 5184 bytes
@WNV5:
    lda.l $4212
    and #$80
    bne @WNV5
@WV5:
    lda.l $4212
    and #$80
    beq @WV5
    rep #$20
    lda #$2880           ; 4 × 2592
    sta.l $2116
    lda #$0400 + 20736
    sta.l $4302
    lda #5184
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Batch 6: VRAM $32A0, source $6954, 5184 bytes
@WNV6:
    lda.l $4212
    and #$80
    bne @WNV6
@WV6:
    lda.l $4212
    and #$80
    beq @WV6
    rep #$20
    lda #$32A0           ; 5 × 2592
    sta.l $2116
    lda #$0400 + 25920
    sta.l $4302
    lda #5184
    sta.l $4305
    sep #$20
    lda #$01
    sta.l $420B

    ; Give GSU back RAM
    lda #$1E
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
