;; tcclib.asm -- Minimal 816-tcc runtime library
;;
;; Replaces PVSnesLib's libtcc.obj
;; Provides the runtime functions that 816-tcc generates calls to:
;;   tcc__mul  - unsigned 16x16 multiply
;;   tcc__udiv - unsigned 16/16 divide
;;
;; Calling conventions (determined from compiled output):
;;
;; tcc__mul:
;;   Input:  tcc__r9  = operand A (16-bit)
;;           tcc__r10 = operand B (16-bit)
;;   Output: A = low 16 bits of (operand A * operand B)
;;   Preserves: DP registers not used as scratch
;;
;; tcc__udiv:
;;   Input:  X (= tcc__r0) = dividend (16-bit unsigned)
;;           tcc__r1        = divisor  (16-bit unsigned)
;;   Output: tcc__r9 = quotient
;;           A = quotient (for convenience)
;;   Note: tcc__r0 may be clobbered

.include "hdr.asm"

.accu 16
.index 16
.16bit

.SECTION ".tcclib_code" SUPERFREE

;; -------------------------------------------------------
;; tcc__mul -- Unsigned 16x16 -> 16-bit multiply
;;
;; Input:  tcc__r9  = multiplicand
;;         tcc__r10 = multiplier
;; Output: A = (tcc__r9 * tcc__r10) & $FFFF
;;
;; Uses the SNES hardware unsigned multiplier at $4202/$4203
;; for 8x8->16 partial products, then combines them:
;;   result = (Ahi*Bhi)<<16 + (Ahi*Blo)<<8 + (Alo*Bhi)<<8 + Alo*Blo
;;   (only keep low 16 bits)
;;
;; Scratch: uses stack for temporaries
;; -------------------------------------------------------
tcc__mul:
    php
    rep #$30

    ; Save operands to stack
    lda.b tcc__r9
    pha                      ; [1,s] = operand A
    lda.b tcc__r10
    pha                      ; [3,s] = operand B  (stack: B_lo, B_hi, A_lo, A_hi, ...)

    ; --- Partial product 1: A_lo * B_lo (full 16-bit result) ---
    sep #$20
    lda 3,s                  ; A_lo (low byte of A on stack)
    sta.l $4202              ; WRMPYA
    lda 1,s                  ; B_lo
    sta.l $4203              ; WRMPYB -- starts multiply

    ; 8 cycles needed for result; do useful work
    rep #$20
    nop                      ; burn cycles while hardware multiplies
    nop
    nop

    lda.l $4216              ; RDMPYL/H = A_lo * B_lo (16-bit)
    sta $50            ; accumulate result in tcc__r0

    ; --- Partial product 2: A_hi * B_lo ---
    sep #$20
    lda 4,s                  ; A_hi
    sta.l $4202              ; WRMPYA
    lda 1,s                  ; B_lo
    sta.l $4203              ; WRMPYB

    rep #$20
    nop
    nop
    nop

    lda.l $4216              ; A_hi * B_lo (16-bit)
    ; Shift left 8 and add to result (only low 16 bits matter)
    xba                      ; swap bytes = <<8 (low byte becomes high, high byte wraps out)
    and #$FF00               ; keep only the shifted-in byte in high position
    clc
    adc $50
    sta $50

    ; --- Partial product 3: A_lo * B_hi ---
    sep #$20
    lda 3,s                  ; A_lo
    sta.l $4202              ; WRMPYA
    lda 2,s                  ; B_hi
    sta.l $4203              ; WRMPYB

    rep #$20
    nop
    nop
    nop

    lda.l $4216              ; A_lo * B_hi (16-bit)
    xba
    and #$FF00
    clc
    adc $50
    ; Result now in A

    ; (A_hi * B_hi) << 16 would overflow 16 bits, so skip it

    ; Clean up stack
    ply                      ; remove B
    ply                      ; remove A

    plp
    rtl

;; -------------------------------------------------------
;; tcc__udiv -- Unsigned 16/16 divide
;;
;; Input:  X (= tcc__r0) = dividend (16-bit unsigned)
;;         tcc__r1       = divisor  (16-bit unsigned)
;; Output: tcc__r9 = quotient
;;         (tcc__r0 may be modified)
;;
;; Uses software long division (shift-and-subtract).
;; The SNES hardware divider only does 16/8, which isn't
;; sufficient for general 16/16 division.
;; -------------------------------------------------------
tcc__udiv:
    php
    rep #$30

    ; Load dividend from X, divisor from tcc__r1
    ; X = dividend
    lda.b tcc__r1            ; divisor
    bne @NonZeroDivisor

    ; Division by zero: return $FFFF
    lda #$FFFF
    sta.b tcc__r9
    plp
    rtl

@NonZeroDivisor:
    sta.b tcc__r2            ; tcc__r2 = divisor (scratch)
    stx.b tcc__r0            ; tcc__r0 = dividend

    ; 16-bit shift-and-subtract division
    ; quotient in tcc__r9, remainder in tcc__r10 (scratch)
    stz.b tcc__r9            ; quotient = 0
    stz.b tcc__r10           ; remainder = 0

    ; We loop 16 times (one per bit)
    ldx #16

@DivLoop:
    ; Shift dividend left through remainder
    asl.b tcc__r0            ; shift dividend left, MSB -> carry
    rol.b tcc__r10           ; shift carry into remainder

    ; Shift quotient left
    asl.b tcc__r9

    ; Compare remainder >= divisor?
    lda.b tcc__r10
    cmp.b tcc__r2
    bcc @DivSkip             ; remainder < divisor, skip

    ; Subtract divisor from remainder, set quotient bit
    sec
    sbc.b tcc__r2
    sta.b tcc__r10
    inc.b tcc__r9            ; set low bit of quotient

@DivSkip:
    dex
    bne @DivLoop

    ; Result: tcc__r9 = quotient
    lda.b tcc__r9

    plp
    rtl

.ENDS
