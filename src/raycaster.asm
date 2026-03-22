.include "hdr.asm"
.accu 16
.index 16
.16bit
.define __fp_mul_locals 12
.define __initPlayer_locals 0
.define __updateVectors_locals 0
.define __isWall_locals 2
.define __handleInput_locals 10
.define __main_locals 0
.SECTION ".fp_multext_0x0" SUPERFREE
fp_mul:
.ifgr __fp_mul_locals 0
tsa
sec
sbc #__fp_mul_locals
tas
.endif
lda.w #0
sep #$20
sta -1 + __fp_mul_locals + 1,s
rep #$20
lda 3 + __fp_mul_locals + 1,s
sta.b tcc__r0
sec
sbc.w #0
bvc +
eor #$8000
+
bmi +
brl __local_0
+
stz.b tcc__r0
lda 3 + __fp_mul_locals + 1,s
sta.b tcc__r1
sec
lda.b tcc__r0
sbc.b tcc__r1
sta 3 + __fp_mul_locals + 1,s
lda.w #1
sta.b tcc__r0
sep #$20
sta -1 + __fp_mul_locals + 1,s
rep #$20
__local_0:
lda 5 + __fp_mul_locals + 1,s
sta.b tcc__r0
sec
sbc.w #0
bvc +
eor #$8000
+
bmi +
brl __local_1
+
stz.b tcc__r0
lda 5 + __fp_mul_locals + 1,s
sta.b tcc__r1
sec
lda.b tcc__r0
sbc.b tcc__r1
sta 5 + __fp_mul_locals + 1,s
lda.w #0
sep #$20
lda -1 + __fp_mul_locals + 1,s
rep #$20
eor.w #1
sta.b tcc__r0
sep #$20
sta -1 + __fp_mul_locals + 1,s
rep #$20
__local_1:
lda 3 + __fp_mul_locals + 1,s
sta -8 + __fp_mul_locals + 1,s
lda 5 + __fp_mul_locals + 1,s
sta -10 + __fp_mul_locals + 1,s
lda -8 + __fp_mul_locals + 1,s
and.w #255
and.w #255
sep #$20
sta -2 + __fp_mul_locals + 1,s
rep #$20
lda -8 + __fp_mul_locals + 1,s
xba
and #$00ff
and.w #255
sep #$20
sta -3 + __fp_mul_locals + 1,s
rep #$20
lda -10 + __fp_mul_locals + 1,s
and.w #255
and.w #255
sep #$20
sta -4 + __fp_mul_locals + 1,s
rep #$20
lda -10 + __fp_mul_locals + 1,s
xba
and #$00ff
and.w #255
sep #$20
sta -5 + __fp_mul_locals + 1,s
rep #$20
lda.w #0
sep #$20
lda -3 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r0
lda.w #0
sep #$20
lda -5 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r1
sta.b tcc__r9
lda.b tcc__r0
sta.b tcc__r10
jsr.l tcc__mul
xba
and #$ff00
sta -12 + __fp_mul_locals + 1,s
lda.w #0
sep #$20
lda -3 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r0
lda.w #0
sep #$20
lda -4 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r1
sta.b tcc__r9
lda.b tcc__r0
sta.b tcc__r10
jsr.l tcc__mul
sta.b tcc__r0
lda -12 + __fp_mul_locals + 1,s
clc
adc.b tcc__r0
sta -12 + __fp_mul_locals + 1,s
lda.w #0
sep #$20
lda -2 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r0
lda.w #0
sep #$20
lda -5 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r1
sta.b tcc__r9
lda.b tcc__r0
sta.b tcc__r10
jsr.l tcc__mul
sta.b tcc__r0
lda -12 + __fp_mul_locals + 1,s
clc
adc.b tcc__r0
sta -12 + __fp_mul_locals + 1,s
lda.w #0
sep #$20
lda -2 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r0
lda.w #0
sep #$20
lda -4 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r1
sta.b tcc__r9
lda.b tcc__r0
sta.b tcc__r10
jsr.l tcc__mul
xba
and #$00ff
sta.b tcc__r0
lda -12 + __fp_mul_locals + 1,s
clc
adc.b tcc__r0
sta.b tcc__r1
sta -12 + __fp_mul_locals + 1,s
lda.w #0
sep #$20
lda -1 + __fp_mul_locals + 1,s
rep #$20
sta.b tcc__r0
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_2
+
stz.b tcc__r0
lda -12 + __fp_mul_locals + 1,s
sta.b tcc__r1
sec
lda.b tcc__r0
sbc.b tcc__r1
sta.b tcc__r0
bra __local_3
__local_2:
lda -12 + __fp_mul_locals + 1,s
sta.b tcc__r0
__local_3:
__local_4:
.ifgr __fp_mul_locals 0
tsa
clc
adc #__fp_mul_locals
tas
.endif
rtl
.ENDS
.SECTION ".initPlayertext_0x1" SUPERFREE
initPlayer:
.ifgr __initPlayer_locals 0
tsa
sec
sbc #__initPlayer_locals
tas
.endif
lda.w #640
sta.w posX + 0
lda.w #640
sta.w posY + 0
lda.w #0
sep #$20
sta.w playerAngle + 0
rep #$20
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
asl a
sta.b tcc__r0
lda.w #:cos_table
sta.b tcc__r1h
lda.w #cos_table + 0
clc
adc.b tcc__r0
sta.b tcc__r1
lda.b [tcc__r1]
sta.w dirX + 0
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
asl a
sta.b tcc__r0
lda.w #:sin_table
sta.b tcc__r1h
lda.w #sin_table + 0
clc
adc.b tcc__r0
sta.b tcc__r1
lda.b [tcc__r1]
sta.w dirY + 0
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
asl a
sta.b tcc__r0
lda.w #:sin_table
sta.b tcc__r1h
lda.w #sin_table + 0
clc
adc.b tcc__r0
sta.b tcc__r1
stz.b tcc__r0
lda.b [tcc__r1]
sta.b tcc__r2
sec
lda.b tcc__r0
sbc.b tcc__r2
sta.b tcc__r0
pea.w 169
pei (tcc__r0)
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta.w planeX + 0
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
asl a
sta.b tcc__r0
lda.w #:cos_table
sta.b tcc__r1h
lda.w #cos_table + 0
clc
adc.b tcc__r0
sta.b tcc__r1
pea.w 169
lda.b [tcc__r1]
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta.w planeY + 0
.ifgr __initPlayer_locals 0
tsa
clc
adc #__initPlayer_locals
tas
.endif
rtl
.ENDS
.SECTION ".updateVectorstext_0x2" SUPERFREE
updateVectors:
.ifgr __updateVectors_locals 0
tsa
sec
sbc #__updateVectors_locals
tas
.endif
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
asl a
sta.b tcc__r0
lda.w #:cos_table
sta.b tcc__r1h
lda.w #cos_table + 0
clc
adc.b tcc__r0
sta.b tcc__r1
lda.b [tcc__r1]
sta.w dirX + 0
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
asl a
sta.b tcc__r0
lda.w #:sin_table
sta.b tcc__r1h
lda.w #sin_table + 0
clc
adc.b tcc__r0
sta.b tcc__r1
lda.b [tcc__r1]
sta.w dirY + 0
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
asl a
sta.b tcc__r0
lda.w #:sin_table
sta.b tcc__r1h
lda.w #sin_table + 0
clc
adc.b tcc__r0
sta.b tcc__r1
stz.b tcc__r0
lda.b [tcc__r1]
sta.b tcc__r2
sec
lda.b tcc__r0
sbc.b tcc__r2
sta.b tcc__r0
pea.w 169
pei (tcc__r0)
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta.w planeX + 0
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
asl a
sta.b tcc__r0
lda.w #:cos_table
sta.b tcc__r1h
lda.w #cos_table + 0
clc
adc.b tcc__r0
sta.b tcc__r1
pea.w 169
lda.b [tcc__r1]
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta.w planeY + 0
.ifgr __updateVectors_locals 0
tsa
clc
adc #__updateVectors_locals
tas
.endif
rtl
.ENDS
.SECTION ".isWalltext_0x3" SUPERFREE
isWall:
.ifgr __isWall_locals 0
tsa
sec
sbc #__isWall_locals
tas
.endif
lda 3 + __isWall_locals + 1,s
sta.b tcc__r0
ldy.w #8
-
cmp #$8000
ror a
dey
bne -
+
and.w #255
sep #$20
sta -1 + __isWall_locals + 1,s
rep #$20
lda 5 + __isWall_locals + 1,s
sta.b tcc__r0
ldy.w #8
-
cmp #$8000
ror a
dey
bne -
+
and.w #255
sep #$20
sta -2 + __isWall_locals + 1,s
rep #$20
lda.w #0
sep #$20
lda -1 + __isWall_locals + 1,s
rep #$20
sta.b tcc__r0
ldx #1
sec
sbc.w #10
tay
bvc +
eor #$8000
+
bpl +++
++
dex
+++
stx.b tcc__r5
txa
beq +
brl __local_5
+
lda.w #0
sep #$20
lda -2 + __isWall_locals + 1,s
rep #$20
sta.b tcc__r0
ldx #1
sec
sbc.w #10
tay
bvc +
eor #$8000
+
bpl +++
++
dex
+++
stx.b tcc__r5
txa
beq +
__local_5:
brl __local_6
+
bra __local_7
__local_6:
lda.w #1
sta.b tcc__r0
jmp.w __local_8
__local_7:
lda.w #0
sep #$20
lda -2 + __isWall_locals + 1,s
rep #$20
sta.b tcc__r0
lda.w #10
sta.b tcc__r9
lda.b tcc__r0
sta.b tcc__r10
jsr.l tcc__mul
sta.b tcc__r0
lda.w #:world_map
sta.b tcc__r1h
lda.w #world_map + 0
clc
adc.b tcc__r0
sta.b tcc__r1
lda.w #0
sep #$20
lda -1 + __isWall_locals + 1,s
rep #$20
clc
adc.b tcc__r1
sta.b tcc__r1
lda.w #0
sep #$20
lda.b [tcc__r1]
rep #$20
sta.b tcc__r0
ldx #1
sec
sbc #0
tay
bne +
dex
+
stx.b tcc__r5
txa
bne +
brl __local_9
+
bra __local_10
__local_9:
lda.w #0
sta.b tcc__r0
bra __local_11
__local_10:
lda.w #1
sta.b tcc__r0
__local_11:
lda.b tcc__r0
and.w #255
sta.b tcc__r0
__local_8:
__local_12:
.ifgr __isWall_locals 0
tsa
clc
adc #__isWall_locals
tas
.endif
rtl
.ENDS
.SECTION ".handleInputtext_0x4" SUPERFREE
handleInput:
.ifgr __handleInput_locals 0
tsa
sec
sbc #__handleInput_locals
tas
.endif
jsr.l readJoypad
lda.b tcc__r0
sta -2 + __handleInput_locals + 1,s
and.w #512
sta.b tcc__r0
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_13
+
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
sec
sbc.w #4
sep #$20
sta.w playerAngle + 0
rep #$20
jsr.l updateVectors
__local_13:
lda -2 + __handleInput_locals + 1,s
and.w #256
sta.b tcc__r0
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_14
+
lda.w #0
sep #$20
lda.w playerAngle + 0
rep #$20
clc
adc.w #4
sep #$20
sta.w playerAngle + 0
rep #$20
jsr.l updateVectors
__local_14:
lda -2 + __handleInput_locals + 1,s
and.w #2048
sta.b tcc__r0
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_15
+
pea.w 20
lda.w dirX + 0
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta -8 + __handleInput_locals + 1,s
pea.w 20
lda.w dirY + 0
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta -10 + __handleInput_locals + 1,s
lda.w posX + 0
sta.b tcc__r0
lda -8 + __handleInput_locals + 1,s
clc
adc.b tcc__r0
sta -4 + __handleInput_locals + 1,s
lda.w posY + 0
sta.b tcc__r0
lda -10 + __handleInput_locals + 1,s
clc
adc.b tcc__r0
sta -6 + __handleInput_locals + 1,s
lda.w posY + 0
pha
lda -2 + __handleInput_locals + 1,s
pha
jsr.l isWall
tsa
clc
adc #4
tas
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_16
+
bra __local_17
__local_16:
lda -4 + __handleInput_locals + 1,s
sta.b tcc__r0
sta.w posX + 0
__local_17:
lda -6 + __handleInput_locals + 1,s
pha
lda.w posX + 0
pha
jsr.l isWall
tsa
clc
adc #4
tas
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_18
+
bra __local_19
__local_18:
lda -6 + __handleInput_locals + 1,s
sta.b tcc__r0
sta.w posY + 0
__local_19:
__local_15:
lda -2 + __handleInput_locals + 1,s
and.w #1024
sta.b tcc__r0
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_20
+
pea.w 20
lda.w dirX + 0
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta -8 + __handleInput_locals + 1,s
pea.w 20
lda.w dirY + 0
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta -10 + __handleInput_locals + 1,s
lda.w posX + 0
sta.b tcc__r0
lda -8 + __handleInput_locals + 1,s
sta.b tcc__r1
sec
lda.b tcc__r0
sbc.b tcc__r1
sta -4 + __handleInput_locals + 1,s
lda.w posY + 0
sta.b tcc__r0
lda -10 + __handleInput_locals + 1,s
sta.b tcc__r1
sec
lda.b tcc__r0
sbc.b tcc__r1
sta -6 + __handleInput_locals + 1,s
lda.w posY + 0
pha
lda -2 + __handleInput_locals + 1,s
pha
jsr.l isWall
tsa
clc
adc #4
tas
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_21
+
bra __local_22
__local_21:
lda -4 + __handleInput_locals + 1,s
sta.b tcc__r0
sta.w posX + 0
__local_22:
lda -6 + __handleInput_locals + 1,s
pha
lda.w posX + 0
pha
jsr.l isWall
tsa
clc
adc #4
tas
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_23
+
bra __local_24
__local_23:
lda -6 + __handleInput_locals + 1,s
sta.b tcc__r0
sta.w posY + 0
__local_24:
__local_20:
lda -2 + __handleInput_locals + 1,s
and.w #32768
sta.b tcc__r0
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_25
+
pea.w 20
lda.w planeX + 0
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta -8 + __handleInput_locals + 1,s
pea.w 20
lda.w planeY + 0
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta -10 + __handleInput_locals + 1,s
lda.w posX + 0
sta.b tcc__r0
lda -8 + __handleInput_locals + 1,s
sta.b tcc__r1
sec
lda.b tcc__r0
sbc.b tcc__r1
sta -4 + __handleInput_locals + 1,s
lda.w posY + 0
sta.b tcc__r0
lda -10 + __handleInput_locals + 1,s
sta.b tcc__r1
sec
lda.b tcc__r0
sbc.b tcc__r1
sta -6 + __handleInput_locals + 1,s
lda.w posY + 0
pha
lda -2 + __handleInput_locals + 1,s
pha
jsr.l isWall
tsa
clc
adc #4
tas
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_26
+
bra __local_27
__local_26:
lda -4 + __handleInput_locals + 1,s
sta.b tcc__r0
sta.w posX + 0
__local_27:
lda -6 + __handleInput_locals + 1,s
pha
lda.w posX + 0
pha
jsr.l isWall
tsa
clc
adc #4
tas
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_28
+
bra __local_29
__local_28:
lda -6 + __handleInput_locals + 1,s
sta.b tcc__r0
sta.w posY + 0
__local_29:
__local_25:
lda -2 + __handleInput_locals + 1,s
and.w #128
sta.b tcc__r0
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_30
+
pea.w 20
lda.w planeX + 0
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta -8 + __handleInput_locals + 1,s
pea.w 20
lda.w planeY + 0
pha
jsr.l fp_mul
tsa
clc
adc #4
tas
lda.b tcc__r0
sta -10 + __handleInput_locals + 1,s
lda.w posX + 0
sta.b tcc__r0
lda -8 + __handleInput_locals + 1,s
clc
adc.b tcc__r0
sta -4 + __handleInput_locals + 1,s
lda.w posY + 0
sta.b tcc__r0
lda -10 + __handleInput_locals + 1,s
clc
adc.b tcc__r0
sta -6 + __handleInput_locals + 1,s
lda.w posY + 0
pha
lda -2 + __handleInput_locals + 1,s
pha
jsr.l isWall
tsa
clc
adc #4
tas
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_31
+
bra __local_32
__local_31:
lda -4 + __handleInput_locals + 1,s
sta.b tcc__r0
sta.w posX + 0
__local_32:
lda -6 + __handleInput_locals + 1,s
pha
lda.w posX + 0
pha
jsr.l isWall
tsa
clc
adc #4
tas
lda.b tcc__r0 ; DON'T OPTIMIZE
bne +
brl __local_33
+
bra __local_34
__local_33:
lda -6 + __handleInput_locals + 1,s
sta.b tcc__r0
sta.w posY + 0
__local_34:
__local_30:
.ifgr __handleInput_locals 0
tsa
clc
adc #__handleInput_locals
tas
.endif
rtl
.ENDS
.SECTION ".maintext_0x5" SUPERFREE
main:
.ifgr __main_locals 0
tsa
sec
sbc #__main_locals
tas
.endif
jsr.l disableNMI
jsr.l initMode3Display
jsr.l initGSU
jsr.l initPlayer
__local_35:
jsr.l handleInput
jsr.l writePlayerState
jsr.l startGSU
jsr.l dmaFramebuffer
bra __local_35
lda.w #0
sta.b tcc__r0
__local_36:
.ifgr __main_locals 0
tsa
clc
adc #__main_locals
tas
.endif
rtl
.ENDS
.RAMSECTION "ram{WLA_FILENAME}.data" APPENDTO "globram.data"
world_map dsb 100
.ENDS
.SECTION "{WLA_FILENAME}.data" APPENDTO "glob.data"
.db $1,$1,$1,$1,$1,$1,$1,$1,$1,$1,$1,$0,$0,$0,$0,$0,$0,$0,$0,$1,$1,$0,$0,$0,$0,$0,$0,$0,$0,$1,$1,$0,$0,$0,$0,$0,$0,$0,$0,$1,$1,$0,$0,$0,$2,$2,$0,$0,$0,$1,$1,$0,$0,$0,$2,$2,$0,$0,$0,$1,$1,$0,$0,$0,$0,$0,$0,$0,$0,$1,$1,$0,$0,$0,$0,$0,$0,$0,$0,$1,$1,$0,$0,$0,$0,$0,$0,$0,$0,$1,$1,$1,$1,$1,$1,$1,$1,$1,$1,$1
.ENDS
.SECTION ".rodata" SUPERFREE
shared_palette: .db $0,$0,$4e,$19,$c,$11,$87,$0,$84,$10,$cb,$c,$e7,$1c,$ad,$35,$b2,$25,$c6,$18,$4a,$29,$63,$c,$a5,$14,$29,$25,$42,$8,$10,$42
extra_palette: .db $0,$7c,$a0,$2
sin_table: .db $0,$0,$6,$0,$d,$0,$13,$0,$19,$0,$1f,$0,$26,$0,$2c,$0,$32,$0,$38,$0,$3e,$0,$44,$0,$4a,$0,$50,$0,$56,$0,$5c,$0,$62,$0,$68,$0,$6d,$0,$73,$0,$79,$0,$7e,$0,$84,$0,$89,$0,$8e,$0,$93,$0,$98,$0,$9d,$0,$a2,$0,$a7,$0,$ac,$0,$b1,$0,$b5,$0,$b9,$0,$be,$0,$c2,$0,$c6,$0,$ca,$0,$ce,$0,$d1,$0,$d5,$0,$d8,$0,$dc,$0,$df,$0,$e2,$0,$e5,$0,$e7,$0,$ea,$0,$ed,$0,$ef,$0,$f1,$0,$f3,$0,$f5,$0,$f7,$0,$f8,$0,$fa,$0,$fb,$0,$fc,$0,$fd,$0,$fe,$0,$ff,$0,$ff,$0,$0,$1,$0,$1,$0,$1,$0,$1,$0,$1,$ff,$0,$ff,$0,$fe,$0,$fd,$0,$fc,$0,$fb,$0,$fa,$0,$f8,$0,$f7,$0,$f5,$0,$f3,$0,$f1,$0,$ef,$0,$ed,$0,$ea,$0,$e7,$0,$e5,$0,$e2,$0,$df,$0,$dc,$0,$d8,$0,$d5,$0,$d1,$0,$ce,$0,$ca,$0,$c6,$0,$c2,$0,$be,$0,$b9,$0,$b5,$0,$b1,$0,$ac,$0,$a7,$0,$a2,$0,$9d,$0,$98,$0,$93,$0,$8e,$0,$89,$0,$84,$0,$7e,$0,$79,$0,$73,$0,$6d,$0,$68,$0,$62,$0,$5c,$0,$56,$0,$50,$0,$4a,$0,$44,$0,$3e,$0,$38,$0,$32,$0,$2c,$0,$26,$0,$1f,$0,$19,$0,$13,$0,$d,$0,$6,$0,$0,$0,$fa,$ff,$f3,$ff,$ed,$ff,$e7,$ff,$e1,$ff,$da,$ff,$d4,$ff,$ce,$ff,$c8,$ff,$c2,$ff,$bc,$ff,$b6,$ff,$b0,$ff,$aa,$ff,$a4,$ff,$9e,$ff,$98,$ff,$93,$ff,$8d,$ff,$87,$ff,$82,$ff,$7c,$ff,$77,$ff,$72,$ff,$6d,$ff,$68,$ff,$63,$ff,$5e,$ff,$59,$ff,$54,$ff,$4f,$ff,$4b,$ff,$47,$ff,$42,$ff,$3e,$ff,$3a,$ff,$36,$ff,$32,$ff,$2f,$ff,$2b,$ff,$28,$ff,$24,$ff,$21,$ff,$1e,$ff,$1b,$ff,$19,$ff,$16,$ff,$13,$ff,$11,$ff,$f,$ff,$d,$ff,$b,$ff,$9,$ff,$8,$ff,$6,$ff,$5,$ff,$4,$ff,$3,$ff,$2,$ff,$1,$ff,$1,$ff,$0,$ff,$0,$ff,$0,$ff,$0,$ff,$0,$ff,$1,$ff,$1,$ff,$2,$ff,$3,$ff,$4,$ff,$5,$ff,$6,$ff,$8,$ff,$9,$ff,$b,$ff,$d,$ff,$f,$ff,$11,$ff,$13,$ff,$16,$ff,$19,$ff,$1b,$ff,$1e,$ff,$21,$ff,$24,$ff,$28,$ff,$2b,$ff,$2f,$ff,$32,$ff,$36,$ff,$3a,$ff,$3e,$ff,$42,$ff,$47,$ff,$4b,$ff,$4f,$ff,$54,$ff,$59,$ff,$5e,$ff,$63,$ff,$68,$ff,$6d,$ff,$72,$ff,$77,$ff,$7c,$ff,$82,$ff,$87,$ff,$8d,$ff,$93,$ff,$98,$ff,$9e,$ff,$a4,$ff,$aa,$ff,$b0,$ff,$b6,$ff,$bc,$ff,$c2,$ff,$c8,$ff,$ce,$ff,$d4,$ff,$da,$ff,$e1,$ff,$e7,$ff,$ed,$ff,$f3,$ff,$fa,$ff
cos_table: .db $0,$1,$0,$1,$0,$1,$ff,$0,$ff,$0,$fe,$0,$fd,$0,$fc,$0,$fb,$0,$fa,$0,$f8,$0,$f7,$0,$f5,$0,$f3,$0,$f1,$0,$ef,$0,$ed,$0,$ea,$0,$e7,$0,$e5,$0,$e2,$0,$df,$0,$dc,$0,$d8,$0,$d5,$0,$d1,$0,$ce,$0,$ca,$0,$c6,$0,$c2,$0,$be,$0,$b9,$0,$b5,$0,$b1,$0,$ac,$0,$a7,$0,$a2,$0,$9d,$0,$98,$0,$93,$0,$8e,$0,$89,$0,$84,$0,$7e,$0,$79,$0,$73,$0,$6d,$0,$68,$0,$62,$0,$5c,$0,$56,$0,$50,$0,$4a,$0,$44,$0,$3e,$0,$38,$0,$32,$0,$2c,$0,$26,$0,$1f,$0,$19,$0,$13,$0,$d,$0,$6,$0,$0,$0,$fa,$ff,$f3,$ff,$ed,$ff,$e7,$ff,$e1,$ff,$da,$ff,$d4,$ff,$ce,$ff,$c8,$ff,$c2,$ff,$bc,$ff,$b6,$ff,$b0,$ff,$aa,$ff,$a4,$ff,$9e,$ff,$98,$ff,$93,$ff,$8d,$ff,$87,$ff,$82,$ff,$7c,$ff,$77,$ff,$72,$ff,$6d,$ff,$68,$ff,$63,$ff,$5e,$ff,$59,$ff,$54,$ff,$4f,$ff,$4b,$ff,$47,$ff,$42,$ff,$3e,$ff,$3a,$ff,$36,$ff,$32,$ff,$2f,$ff,$2b,$ff,$28,$ff,$24,$ff,$21,$ff,$1e,$ff,$1b,$ff,$19,$ff,$16,$ff,$13,$ff,$11,$ff,$f,$ff,$d,$ff,$b,$ff,$9,$ff,$8,$ff,$6,$ff,$5,$ff,$4,$ff,$3,$ff,$2,$ff,$1,$ff,$1,$ff,$0,$ff,$0,$ff,$0,$ff,$0,$ff,$0,$ff,$1,$ff,$1,$ff,$2,$ff,$3,$ff,$4,$ff,$5,$ff,$6,$ff,$8,$ff,$9,$ff,$b,$ff,$d,$ff,$f,$ff,$11,$ff,$13,$ff,$16,$ff,$19,$ff,$1b,$ff,$1e,$ff,$21,$ff,$24,$ff,$28,$ff,$2b,$ff,$2f,$ff,$32,$ff,$36,$ff,$3a,$ff,$3e,$ff,$42,$ff,$47,$ff,$4b,$ff,$4f,$ff,$54,$ff,$59,$ff,$5e,$ff,$63,$ff,$68,$ff,$6d,$ff,$72,$ff,$77,$ff,$7c,$ff,$82,$ff,$87,$ff,$8d,$ff,$93,$ff,$98,$ff,$9e,$ff,$a4,$ff,$aa,$ff,$b0,$ff,$b6,$ff,$bc,$ff,$c2,$ff,$c8,$ff,$ce,$ff,$d4,$ff,$da,$ff,$e1,$ff,$e7,$ff,$ed,$ff,$f3,$ff,$fa,$ff,$0,$0,$6,$0,$d,$0,$13,$0,$19,$0,$1f,$0,$26,$0,$2c,$0,$32,$0,$38,$0,$3e,$0,$44,$0,$4a,$0,$50,$0,$56,$0,$5c,$0,$62,$0,$68,$0,$6d,$0,$73,$0,$79,$0,$7e,$0,$84,$0,$89,$0,$8e,$0,$93,$0,$98,$0,$9d,$0,$a2,$0,$a7,$0,$ac,$0,$b1,$0,$b5,$0,$b9,$0,$be,$0,$c2,$0,$c6,$0,$ca,$0,$ce,$0,$d1,$0,$d5,$0,$d8,$0,$dc,$0,$df,$0,$e2,$0,$e5,$0,$e7,$0,$ea,$0,$ed,$0,$ef,$0,$f1,$0,$f3,$0,$f5,$0,$f7,$0,$f8,$0,$fa,$0,$fb,$0,$fc,$0,$fd,$0,$fe,$0,$ff,$0,$ff,$0,$0,$1,$0,$1
.ENDS



.RAMSECTION ".bss" BANK $7e SLOT 2
posX dsb 2
posY dsb 2
dirX dsb 2
dirY dsb 2
planeX dsb 2
planeY dsb 2
playerAngle dsb 1
.ENDS
