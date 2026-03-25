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
    ; DBR=$00 for absolute addressing to SA-1 registers
    sep #$20
    lda #$00
    pha
    plb                  ; DBR = $00

    ; Step 1: Hold SA-1 in reset (bit 5 = 1 = RESET)
    lda #$20
    sta $2200            ; CCNT: SA-1 held in reset

    ; Step 2: Clear pending interrupts
    lda #$80
    sta $2202            ; SIC: clear IRQ flags

    ; Step 3: ROM bank mapping
    lda #$00
    sta $2220            ; CXB: $00-$1F → ROM bank 0
    lda #$01
    sta $2221            ; DXB: $20-$3F → ROM bank 1
    lda #$02
    sta $2222            ; EXB: $80-$9F → ROM bank 2
    lda #$03
    sta $2223            ; FXB: $A0-$BF → ROM bank 3

    ; Step 4: BW-RAM configuration
    lda #$00
    sta $2224            ; BMAPS: SNES BW-RAM bank = 0
    sta $2228            ; BWPA: deprotect all BW-RAM (default $FF = protected!)
    lda #$80
    sta $2226            ; SBWE: enable SNES CPU BW-RAM writes
    sta $2227            ; CBWE: enable SA-1 CPU BW-RAM writes

    ; Step 5: Set SA-1 vectors
    lda #<sa1_entry
    sta $2203            ; reset vector low
    sta $2205            ; NMI vector low
    sta $2207            ; IRQ vector low
    lda #>sa1_entry
    sta $2204            ; reset vector high
    sta $2206            ; NMI vector high
    sta $2208            ; IRQ vector high

    ; Step 6: Initialize BW-RAM command/status bytes
    lda #$00
    sta.l $400000        ; command = 0 (idle)
    sta.l $400001        ; status = 0

    ; Step 7: Release SA-1 (bit 5 = 0 = RUN)
    sta $2200            ; CCNT = $00: SA-1 starts executing at sa1_entry
    nop
    nop
    nop
    nop

    ; Restore DBR=$7E for C runtime
    lda #$7E
    pha
    plb

    ; Copy floor_tex (1024 bytes) to BW-RAM $40:1800 for SA-1 access
    rep #$30
.ACCU 16
.INDEX 16
    ldx #$0000
@CpFloorTex:
    lda.l floor_tex,x
    sta.l $401800,x
    inx
    inx
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
;;
;; Communication via BW-RAM:
;;   $6000 = command (0=idle, 1=render floor)
;;   $6001 = status  (0=busy, 1=done)
;;   $6002-$600D = player state (posX/Y, dirX/Y, planeX/Y)
;;   $6100+ = floor pixel buffer (39 rows × 112 cols = 4368 bytes)
;;   $7800  = floor_tex (1024 bytes, copied from ROM at startup)
;;   $7C00  = rowDist_table (78 bytes, copied from ROM at startup)
;;
;; SA-1 math registers ($2250):
;;   bit 0: 0=multiply (unsigned 16×16→32), 1=divide (32÷16)
;;   Multiply: write $2251-$2252 (A), $2253-$2254 (B, triggers)
;;             result at $2306-$2309 (32-bit product)
;;   Divide:   write $2251-$2254 (32-bit dividend), $2258-$2259 (divisor, triggers)
;;             quotient at $2306-$2307, remainder at $2308-$2309
;; -------------------------------------------------------
sa1_entry:
    sei
    clc
    xce                  ; native mode
    rep #$30
    lda #$07FF
    tcs                  ; SA-1 stack in I-RAM
    sep #$20

    ; Continuous floor rendering — no command/status handshake
    ; SA-1 reads player state directly from BW-RAM, renders continuously
sa1_loop:
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
    lda $40
    asl a
    tax
    lda $7C00,x
    sta $8C              ; rowDist

    ; floorX = posX + sa1_mul(rowDist, leftRayDirX)
    lda $80
    jsr sa1_mul_8c
    clc
    adc $6002            ; + posX
    sta $90

    ; floorY = posY + sa1_mul(rowDist, leftRayDirY)
    lda $82
    jsr sa1_mul_8c
    clc
    adc $6004            ; + posY
    sta $92

    ; floorStepX = sa1_mul(rowDist, 2*planeX) / 112
    lda $84
    jsr sa1_mul_8c
    jsr sa1_div_112
    sta $94

    ; floorStepY = sa1_mul(rowDist, 2*planeY) / 112
    lda $86
    jsr sa1_mul_8c
    jsr sa1_div_112
    sta $96

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
;; sa1_mul_8c — SA-1 unsigned multiply with manual sign handling
;; Computes: ($8C * A) >> 8, treating A as signed, $8C as unsigned
;; Input:  A = signed 16-bit value, $8C = unsigned 16-bit (rowDist)
;; Output: A = signed 16-bit result
;; Clobbers: $A0, $A2
;; -------------------------------------------------------
sa1_mul_8c:
    rep #$20
.ACCU 16
    stz $A2              ; neg flag = 0
    cmp #$8000
    bcc @MPos            ; branch if A positive (< $8000)
    eor #$FFFF
    inc a                ; negate A
    inc $A2              ; neg = 1
@MPos:
    sta $A0              ; |value|
    sep #$20
.ACCU 8
    lda #$00
    sta $2250            ; $00 = unsigned multiply mode
    ; Write multiplicand A byte-by-byte (rowDist at $8C-$8D)
    lda $8C              ; rowDist low byte
    sta $2251
    lda $8D              ; rowDist high byte
    sta $2252
    ; Write multiplicand B byte-by-byte (|value| at $A0-$A1)
    lda $A0              ; |value| low byte
    sta $2253
    lda $A1              ; |value| high byte — TRIGGERS multiply
    sta $2254
    nop
    nop
    nop
    nop
    nop                  ; 5 NOPs = 10 cycles (multiply takes 5)
    rep #$20
.ACCU 16
    lda $2307            ; bits 8-23 of 32-bit product = >>8
    ldx $A2
    beq @MNoNeg
    eor #$FFFF
    inc a                ; negate result
@MNoNeg:
    rts

;; -------------------------------------------------------
;; sa1_div_112 — SA-1 signed divide by 112
;; Input:  A = signed 16-bit dividend
;; Output: A = signed 16-bit quotient
;; Clobbers: $A2, $A4
;; -------------------------------------------------------
sa1_div_112:
    ; Divide by 112 using multiply-by-reciprocal (avoids buggy SA-1 divide)
    ; a / 112 ≈ (|a| * 585) >> 16,  where 585 = 65536/112 = $0249
    rep #$20
.ACCU 16
    stz $A2              ; neg flag = 0
    cmp #$8000
    bcc @DPos
    eor #$FFFF
    inc a
    inc $A2
@DPos:
    sta $A4              ; |dividend|
    sep #$20
.ACCU 8
    lda #$00
    sta $2250            ; multiply mode
    lda $A4              ; |dividend| low byte
    sta $2251
    lda $A5              ; |dividend| high byte
    sta $2252
    lda #$49             ; 585 low byte ($0249)
    sta $2253
    lda #$02             ; 585 high byte — triggers multiply
    sta $2254
    nop
    nop
    nop
    nop
    nop
    rep #$20
.ACCU 16
    lda $2308            ; bits 16-31 of product = >>16 result
    ldx $A2
    beq @DNoNeg
    eor #$FFFF
    inc a
@DNoNeg:
    rts


.ENDS
