;; crt0.asm -- Custom SNES startup (replaces PVSnesLib's crt0_snes)
;;
;; Modeled on Doom SNES architecture:
;;   - Minimal startup: native mode, stack, DP, data bank
;;   - Clear WRAM for direct page and stack area
;;   - Disable display and interrupts
;;   - Call C main() entry point
;;   - Provide VBlank (NMI) and EmptyHandler for vectors
;;
;; Required labels for 816-tcc and hdr.asm:
;;   tcc__start    - RESET vector entry point
;;   VBlank        - NMI vector handler
;;   EmptyHandler  - unused vector handler
;;   tcc__r0..r10  - direct page register variables

.include "hdr.asm"

.accu 16
.index 16
.16bit

;; -------------------------------------------------------
;; Direct page register variables for 816-tcc
;; These MUST be at fixed DP offsets starting at $00
;; The compiler generates code like: lda.b tcc__r0
;; where .b means direct page addressing.
;; -------------------------------------------------------
.RAMSECTION ".tcc_regs" BANK 0 SLOT 1 ORG $00
tcc__r0     dsb 1     ; $00
tcc__r0h    dsb 1     ; $01
tcc__r1     dsb 1     ; $02
tcc__r1h    dsb 1     ; $03
tcc__r2     dsb 2     ; $04-$05
tcc__r3     dsb 2     ; $06-$07
tcc__r4     dsb 2     ; $08-$09
tcc__r5     dsb 2     ; $0A-$0B
tcc__r6     dsb 2     ; $0C-$0D
tcc__r7     dsb 2     ; $0E-$0F
tcc__r8     dsb 2     ; $10-$11
tcc__r9     dsb 2     ; $12-$13
tcc__r10    dsb 2     ; $14-$15
tcc__r11    dsb 2     ; $16-$17 (spare)
tcc__r12    dsb 2     ; $18-$19 (spare)
tcc__r13    dsb 2     ; $1A-$1B (spare)
tcc__r14    dsb 2     ; $1C-$1D (spare)
tcc__r15    dsb 2     ; $1E-$1F (spare)
.ENDS

;; -------------------------------------------------------
;; Global data section anchor (816-tcc APPENDTO target)
;; The compiled C code uses: .SECTION "xxx" APPENDTO "glob.data"
;; We must define the base section for it to append to.
;; This section holds const initialization data for C globals.
;; -------------------------------------------------------
.SECTION "glob.data" SUPERFREE
__glob_data_anchor:
  .db $00               ; anchor byte (required for APPENDTO linkage)
.ENDS

;; -------------------------------------------------------
;; Global RAM section anchor (816-tcc APPENDTO target)
;; The compiled C code uses: .RAMSECTION "xxx" APPENDTO "globram.data"
;; We must define the base RAM section for it to append to.
;; This section allocates WRAM for C global variables.
;; -------------------------------------------------------
.RAMSECTION "globram.data" BANK $7E SLOT 2
__globram_data_anchor dsb 1    ; anchor byte (required for APPENDTO linkage)
.ENDS

;; -------------------------------------------------------
;; Startup code section
;; -------------------------------------------------------
.SECTION ".crt0_startup" SEMIFREE BANK 0 SLOT 0

tcc__start:
    ; Enter native mode (65816)
    clc
    xce

    ; Set 16-bit accumulator and index
    rep #$30

    ; Set stack pointer to $1FFF
    lda #$1FFF
    tcs

    ; Set direct page to $0000
    lda #$0000
    tcd

    ; Set data bank to $7E (WRAM)
    sep #$20
    lda #$7E
    pha
    plb
    rep #$20

    ; === Disable display (forced blank) ===
    sep #$20
    lda #$80
    sta.l $2100          ; INIDISP = forced blank

    ; === Disable NMI, IRQ, auto-joypad ===
    lda #$00
    sta.l $4200          ; NMITIMEN = all off

    ; === Clear PPU registers ===
    ; Zero out $2101-$2133 to reset all PPU state
    ldx #$2101
    rep #$20
@ClearPPU:
    sep #$20
    lda #$00
    sta.l $0000,x        ; absolute long write to $00:21xx
    rep #$20
    inx
    cpx #$2134
    bne @ClearPPU

    ; === Clear WRAM direct page area ($0000-$001F) ===
    sep #$20
    ldx #$0000
@ClearDP:
    lda #$00
    sta.l $7E0000,x
    inx
    cpx #$0020
    bne @ClearDP

    ; === Set 16-bit mode for C code ===
    rep #$30

    ; === Acknowledge any pending NMI/IRQ ===
    sep #$20
    lda.l $4210          ; read RDNMI to acknowledge
    lda.l $4211          ; read TIMEUP to acknowledge

    ; === SA-1 Initialization ===
    sep #$20

    ; Hold SA-1 in reset
    lda #$00
    sta.l $2200

    ; Clear I-RAM command/status bytes
    sta.l $300C          ; IRAM_CMD = 0
    sta.l $300D          ; IRAM_STATUS = 0

    ; Set ROM bank mapping (SA-1 Super MMC)
    lda #$00
    sta.l $2220          ; CXB: banks $00-$0F → ROM bank 0
    lda #$01
    sta.l $2221          ; DXB: banks $10-$1F → ROM bank 1
    lda #$02
    sta.l $2222          ; EXB: banks $20-$2F → ROM bank 2
    lda #$03
    sta.l $2223          ; FXB: banks $30-$3F → ROM bank 3

    ; BW-RAM write enable for main CPU
    lda #$80
    sta.l $2225

    ; Set SA-1 reset vector AND IRQ vector to sa1_entry
    lda #<sa1_entry
    sta.l $2203          ; reset vector low
    sta.l $2207          ; IRQ vector low
    lda #>sa1_entry
    sta.l $2204          ; reset vector high
    sta.l $2208          ; IRQ vector high

    ; Copy floor_tex (1024 bytes) to BW-RAM $40:1800 for SA-1 access
    rep #$30
.ACCU 16
.INDEX 16
    ldx #$0000
@CpFloorTex:
    lda.l floor_tex,x   ; main CPU reads from correct ROM bank
    sta.l $401800,x      ; store to BW-RAM offset $1800
    inx
    inx                  ; 16-bit copies, advance by 2
    cpx #1024
    bcc @CpFloorTex

    ; Copy rowDist_table (78 bytes) to BW-RAM $40:1C00
    ldx #$0000
@CpRowDist:
    lda.l rowDist_table,x
    sta.l $401C00,x
    inx
    inx
    cpx #78
    bcc @CpRowDist

    sep #$20

    ; Release SA-1 from reset (bit 5 only, NO IRQ)
    lda #$20
    sta.l $2200
    ; Small delay to let SA-1 start
    nop
    nop
    nop
    nop

    rep #$20

    ; === Call C main() ===
    ; 816-tcc compiles main() as a far subroutine (rtl)
    jsr.l main

    ; === If main returns, infinite loop ===
@Halt:
    wai
    bra @Halt

;; -------------------------------------------------------
;; VBlank -- Minimal NMI handler
;; Just acknowledge the NMI and return.
;; Our IRQ system does NOT use NMI (Doom-style: V-count IRQ only).
;; -------------------------------------------------------
VBlank:
    rep #$30
    pha
    sep #$20
    lda.l $4210          ; read RDNMI to acknowledge NMI
    rep #$20
    pla
    rti

;; -------------------------------------------------------
;; EmptyHandler -- Stub for unused vectors (COP, BRK, ABORT)
;; -------------------------------------------------------
EmptyHandler:
    rti

;; -------------------------------------------------------
;; SA-1 entry point — MUST be in bank 0 (SA-1 resets to bank $00)
;; -------------------------------------------------------
sa1_entry:
    sei                  ; disable IRQs
    clc
    xce                  ; native mode
    rep #$30
    lda #$07FF
    tcs                  ; SA-1 stack in direct I-RAM ($0000-$07FF)
    sep #$20
    lda #$80
    sta $2226            ; enable BW-RAM writes from SA-1

    ; Communication via BW-RAM:
    ; $6000 = command (0=idle, 1=render)
    ; $6001 = status (0=busy, 1=done)
    ; $6002-$600D = player state (12 bytes)
    ; $600E-$607D = colDrawEnd (112 bytes)
    ; $6100+ = floor pixel buffer (39*112 = 4368 bytes)
    ; SA-1 continuously renders floor INLINE (no JSR)
sa1_loop:
    rep #$30
.ACCU 16
.INDEX 16

    ; DEBUG: write dirX high byte to first 112 floor pixels
    ; If floor shows a non-zero color that changes when you rotate, SA-1 reads BW-RAM correctly
    lda $6006            ; dirX from BW-RAM
    xba                  ; high byte → low byte (8.8 integer part)
    and #$000F           ; clamp to palette range 0-15
    ora #$0001           ; ensure non-zero
    sep #$20
.ACCU 8
    ldx #$0000
@dbg:
    sta $6100,x
    inx
    cpx #112
    bne @dbg
    rep #$20
.ACCU 16

    ; Precompute ray directions from BW-RAM player state
    lda $6006
    sec
    sbc $600A
    sta $80
    lda $6008
    sec
    sbc $600C
    sta $82
    lda $600A
    asl a
    sta $84
    lda $600C
    asl a
    sta $86

    lda #$0000
    sta $40
    sta $88

@Row:
    lda $40
    asl a
    tax
    lda $7C00,x
    sta $8C

    sep #$20
    lda #$01
    sta $2250
    rep #$20

    lda $8C
    sta $2251
    lda $80
    sta $2253
    nop
    nop
    nop
    lda $2307
    clc
    adc $6002
    sta $90

    lda $8C
    sta $2251
    lda $82
    sta $2253
    nop
    nop
    nop
    lda $2307
    clc
    adc $6004
    sta $92

    lda $8C
    sta $2251
    lda $84
    sta $2253
    nop
    nop
    nop
    lda $2307
    sta $94
    bpl @SXP
    eor #$FFFF
    inc a
    sta $94
    sep #$20
    lda #$02
    sta $2250
    rep #$20
    lda $94
    sta $2251
    lda #$0000
    sta $2253
    lda #112
    sta $2258
    nop
    nop
    nop
    nop
    nop
    lda $2306
    eor #$FFFF
    inc a
    sta $94
    bra @SXD
@SXP:
    sep #$20
    lda #$02
    sta $2250
    rep #$20
    lda $94
    sta $2251
    lda #$0000
    sta $2253
    lda #112
    sta $2258
    nop
    nop
    nop
    nop
    nop
    lda $2306
    sta $94
@SXD:

    sep #$20
    lda #$01
    sta $2250
    rep #$20
    lda $8C
    sta $2251
    lda $86
    sta $2253
    nop
    nop
    nop
    lda $2307
    sta $96
    bpl @SYP
    eor #$FFFF
    inc a
    sta $96
    sep #$20
    lda #$02
    sta $2250
    rep #$20
    lda $96
    sta $2251
    lda #$0000
    sta $2253
    lda #112
    sta $2258
    nop
    nop
    nop
    nop
    nop
    lda $2306
    eor #$FFFF
    inc a
    sta $96
    bra @SYD
@SYP:
    sep #$20
    lda #$02
    sta $2250
    rep #$20
    lda $96
    sta $2251
    lda #$0000
    sta $2253
    lda #112
    sta $2258
    nop
    nop
    nop
    nop
    nop
    lda $2306
    sta $96
@SYD:

    lda #$0000
    sta $44

@Col:
    lda $90
    lsr a
    lsr a
    lsr a
    and #$001F
    sta $9C
    lda $92
    lsr a
    lsr a
    lsr a
    and #$001F
    sta $9E
    lda $9C
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc $9E
    tax
    sep #$20
.ACCU 8
    lda $7800,x
    ldx $88
    sta $6100,x
    rep #$20
.ACCU 16

    lda $88
    inc a
    sta $88
    lda $90
    clc
    adc $94
    sta $90
    lda $92
    clc
    adc $96
    sta $92
    lda $44
    inc a
    sta $44
    cmp #112
    bcc @Col

    lda $40
    inc a
    sta $40
    cmp #39
    bcs @LoopBack
    jmp @Row
@LoopBack:
    jmp sa1_loop

;; -------------------------------------------------------
;; sa1_renderFloor -- SA-1 floor raycasting (row-major, Lodev style)
;; Reads player state from BW-RAM ($6002-$600D)
;; Reads floor_tex from BW-RAM ($7800, copied from ROM at startup)
;; Writes floor pixels to BW-RAM ($6100+) row-major
;; Uses SA-1 hardware multiply ($2250/$2251-$2254, result $2306-$2309)
;; -------------------------------------------------------
sa1_renderFloor:
    rep #$30
.ACCU 16
.INDEX 16

    ; Precompute ray directions from BW-RAM player state
    lda $6006            ; dirX
    sec
    sbc $600A            ; - planeX
    sta $80              ; leftRayDirX
    lda $6008            ; dirY
    sec
    sbc $600C            ; - planeY
    sta $82              ; leftRayDirY
    lda $600A            ; planeX
    asl a
    sta $84              ; 2*planeX
    lda $600C            ; planeY
    asl a
    sta $86              ; 2*planeY

    lda #$0000
    sta $40              ; row index
    sta $88              ; BW-RAM output offset

@Row:
    ; rowDist = rowDist_table[row] (in BW-RAM at $7C00)
    lda $40
    asl a
    tax
    lda $7C00,x
    sta $8C              ; rowDist

    ; Set SA-1 signed multiply mode
    sep #$20
    lda #$01
    sta $2250
    rep #$20

    ; floorX = posX + fp_mul(rowDist, leftRayDirX)
    lda $8C
    sta $2251
    lda $80
    sta $2253
    nop
    nop
    nop
    lda $2307            ; bits 8-23 of 32-bit product
    clc
    adc $6002            ; + posX
    sta $90              ; floorX

    ; floorY = posY + fp_mul(rowDist, leftRayDirY)
    lda $8C
    sta $2251
    lda $82
    sta $2253
    nop
    nop
    nop
    lda $2307
    clc
    adc $6004            ; + posY
    sta $92              ; floorY

    ; floorStepX = fp_mul(rowDist, 2*planeX) / 112
    lda $8C
    sta $2251
    lda $84
    sta $2253
    nop
    nop
    nop
    lda $2307
    sta $94
    ; Signed divide by 112
    bpl @SXP
    eor #$FFFF
    inc a
    sta $94
    sep #$20
    lda #$02
    sta $2250            ; unsigned divide mode
    rep #$20
    lda $94
    sta $2251
    lda #$0000
    sta $2253
    lda #112
    sta $2258
    nop
    nop
    nop
    nop
    nop
    lda $2306
    eor #$FFFF
    inc a
    sta $94
    bra @SXD
@SXP:
    sep #$20
    lda #$02
    sta $2250
    rep #$20
    lda $94
    sta $2251
    lda #$0000
    sta $2253
    lda #112
    sta $2258
    nop
    nop
    nop
    nop
    nop
    lda $2306
    sta $94
@SXD:

    ; floorStepY = fp_mul(rowDist, 2*planeY) / 112
    sep #$20
    lda #$01
    sta $2250            ; signed multiply
    rep #$20
    lda $8C
    sta $2251
    lda $86
    sta $2253
    nop
    nop
    nop
    lda $2307
    sta $96
    bpl @SYP
    eor #$FFFF
    inc a
    sta $96
    sep #$20
    lda #$02
    sta $2250
    rep #$20
    lda $96
    sta $2251
    lda #$0000
    sta $2253
    lda #112
    sta $2258
    nop
    nop
    nop
    nop
    nop
    lda $2306
    eor #$FFFF
    inc a
    sta $96
    bra @SYD
@SYP:
    sep #$20
    lda #$02
    sta $2250
    rep #$20
    lda $96
    sta $2251
    lda #$0000
    sta $2253
    lda #112
    sta $2258
    nop
    nop
    nop
    nop
    nop
    lda $2306
    sta $96
@SYD:

    ; Column loop: step floorX/Y across 112 columns
    lda #$0000
    sta $44

@Col:
    ; texU = (floorX >> 3) & 31
    lda $90
    lsr a
    lsr a
    lsr a
    and #$001F
    sta $9C
    ; texV = (floorY >> 3) & 31
    lda $92
    lsr a
    lsr a
    lsr a
    and #$001F
    ; texAddr = texU * 32 + texV
    sta $9E
    lda $9C
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc $9E
    tax
    ; Read floor texture from BW-RAM ($7800)
    sep #$20
.ACCU 8
    lda $7800,x
    ; Write to BW-RAM floor buffer ($6100 + offset)
    ldx $88
    sta $6100,x
    rep #$20
.ACCU 16

    ; Advance
    lda $88
    inc a
    sta $88
    lda $90
    clc
    adc $94              ; floorX += stepX
    sta $90
    lda $92
    clc
    adc $96              ; floorY += stepY
    sta $92
    lda $44
    inc a
    sta $44
    cmp #112
    bcc @Col

    ; Next row
    lda $40
    inc a
    sta $40
    cmp #39
    bcs @Done
    jmp @Row
@Done:
    rts


.ENDS
