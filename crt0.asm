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

    ; Release SA-1 from reset + send IRQ ($A0 = bit7 + bit5)
    lda #$A0
    sta.l $2200

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
    lda #$37FF
    tcs                  ; SA-1 stack in I-RAM
    sep #$20
    lda #$80
    sta $2226            ; enable BW-RAM writes from SA-1

    ; Communication via BW-RAM:
    ; $6000 = command (0=idle, 1=render)
    ; $6001 = status (0=busy, 1=done)
    ; $6002-$600D = player state (12 bytes)
    ; $600E-$607D = colDrawEnd (112 bytes)
    ; $6100+ = floor pixel buffer (39*112 = 4368 bytes)
    rep #$10
sa1_wait:
    sep #$20
    lda $6000            ; command byte in BW-RAM
    cmp #$01
    bne sa1_wait
    lda #$00
    sta $6000            ; acknowledge
    sta $6001            ; status = busy
    rep #$20
    jsl sa1_renderFloor  ; render floor into BW-RAM $6100+
    sep #$20
    lda #$01
    sta $6001            ; status = done
    bra sa1_wait

.ENDS
