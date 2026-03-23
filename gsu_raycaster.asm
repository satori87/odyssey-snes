; ============================================
; SuperFX DDA Raycaster (complete -- all math on GSU)
;
; Modeled on Doom SNES: the 65816 only handles joypad input and
; writes player state (posX/posY/dirX/dirY/planeX/planeY) to
; $70:0000.  ALL raycasting math runs here on the SuperFX.
;
; Memory layout ($70:xxxx):
;   $0000-$000A  Player state (6 words, 8.8 fixed point)
;   $0010-$003F  Scratch variables
;   $0400-$37FF  Tile framebuffer (200 tiles x 64 bytes = 12800)
;
; GSU instruction notes:
;   - AND rN: R0 = R0 & rN (no immediate form!)
;   - LOB: dest = src & 0xFF (low byte, zero extended)
;   - HIB: dest = (src >> 8) & 0xFF (high byte, zero extended)
;   - SWAP: dest = byte-swap of src
;   - After branches: always nop (delay slot)
;   - ldb/stb/ldw/stw only with R0-R11
;   - lms/sms: byte address parameter must be even
;   - Long jump: iwt r15, #label - $8000 / nop
; ============================================

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

.BANK 0
.SECTION "GSUCode" SUPERFREE

; -------------------------------------------------------
; Constants
; -------------------------------------------------------
.define SCREEN_H      96
.define HALF_H        48
.define NUM_COLS      32          ; 32 rays, rendered as 2 sub-columns per tile column
.define TILE_COLS     16          ; actual tile columns
.define MAX_STEPS     24
.define MAP_W         10
.define MAP_H         10

.define CEIL_COLOR    16
.define FLOOR_COLOR   17
.define WALL_BRIGHT   5
.define WALL_DARK     4

.define FRAMEBUF      $0400

; -------------------------------------------------------
; RAM variable layout (all even byte addresses for lms/sms)
; Player state (written by 65816):
;   $0000: posX     $0002: posY     $0004: dirX
;   $0006: dirY     $0008: planeX   $000A: planeY
;
; Scratch variables:
;   $0010: colNum       $0012: rayDirX      $0014: rayDirY
;   $0016: deltaDistX   $0018: deltaDistY   $001A: sideDistX
;   $001C: sideDistY    $001E: stepX        $0020: stepY
;   $0022: mapX         $0024: mapY         $0026: side
;   $0028: perpDist     $002A: drawStart    $002C: drawEnd
;   $002E: wallColor    $0030: tileX
; -------------------------------------------------------

; -------------------------------------------------------
; Entry point
; -------------------------------------------------------
gsu_fill_screen:
    iwt r0, #$70
    ramb                    ; RAM bank = $70 (for lms/sms/ldb/stb)
    iwt r0, #$00
    romb                    ; ROM bank = 0 (for getb/getbh on data tables)

    ; Initialize column counter
    iwt r0, #0
    sms ($10), r0           ; colNum = 0

; -------------------------------------------------------
; Main column loop
; -------------------------------------------------------
_col_loop:
    ; === Step 1: Compute ray direction ===
    ; rayDirX = dirX + fp_mul(planeX, cameraX[col])

    ; Load cameraX[col] from ROM
    lms r0, ($10)           ; r0 = col
    from r0
    to r1
    add r0                  ; r1 = col * 2
    iwt r0, #((cameraX_tbl - $8000) & $FFFF)
    add r1
    move r14, r0
    getb
    move r1, r0
    inc r14
    getbh
    move r1, r0             ; r1 = cameraX

    ; planeX * cameraX
    lms r0, ($08)           ; r0 = planeX
    move r6, r1             ; r6 = cameraX
    link #4
    iwt r15, #fp_mul_sub - $8000
    nop
    ; r0 = planeX * cameraX
    move r1, r0
    lms r0, ($04)           ; r0 = dirX
    add r1                  ; r0 = dirX + planeX*cameraX
    sms ($12), r0           ; rayDirX

    ; planeY * cameraX
    lms r1, ($10)           ; col
    from r1
    to r1
    add r1                  ; r1 = col*2
    iwt r0, #((cameraX_tbl - $8000) & $FFFF)
    add r1
    move r14, r0
    getb
    move r1, r0
    inc r14
    getbh
    move r1, r0             ; r1 = cameraX

    lms r0, ($0A)           ; r0 = planeY
    move r6, r1
    link #4
    iwt r15, #fp_mul_sub - $8000
    nop
    move r1, r0
    lms r0, ($06)           ; r0 = dirY
    add r1
    sms ($14), r0           ; rayDirY

    ; === Step 2: deltaDist = recip(|rayDir|) ===

    ; --- deltaDistX ---
    lms r0, ($12)           ; rayDirX
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bge _ddx_pos
    nop
    ibt r0, #0
    sub r1
    move r1, r0
_ddx_pos:
    ; r1 = |rayDirX|
    move r0, r1
    iwt r6, #256
    from r0
    cmp r6
    bge _ddx_large
    nop
    ; Table lookup for < 256
    from r1
    to r0
    add r1                  ; r0 = |rayDirX| * 2
    iwt r1, #((recip_tbl - $8000) & $FFFF)
    add r1
    move r14, r0
    getb
    move r1, r0
    inc r14
    getbh
    sms ($16), r0           ; deltaDistX
    iwt r15, #_ddx_done - $8000
    nop

_ddx_large:
    move r0, r1             ; |rayDirX|
    lsr                     ; / 2
    move r1, r0
    iwt r6, #256
    from r1
    cmp r6
    bge _ddx_vl
    nop
    from r1
    to r0
    add r1
    iwt r1, #((recip_tbl - $8000) & $FFFF)
    add r1
    move r14, r0
    getb
    move r1, r0
    inc r14
    getbh
    lsr                     ; result / 2
    sms ($16), r0
    iwt r15, #_ddx_done - $8000
    nop
_ddx_vl:
    iwt r0, #1
    sms ($16), r0
_ddx_done:

    ; --- deltaDistY ---
    lms r0, ($14)           ; rayDirY
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bge _ddy_pos
    nop
    ibt r0, #0
    sub r1
    move r1, r0
_ddy_pos:
    move r0, r1
    iwt r6, #256
    from r0
    cmp r6
    bge _ddy_large
    nop
    from r1
    to r0
    add r1
    iwt r1, #((recip_tbl - $8000) & $FFFF)
    add r1
    move r14, r0
    getb
    move r1, r0
    inc r14
    getbh
    sms ($18), r0
    iwt r15, #_ddy_done - $8000
    nop
_ddy_large:
    move r0, r1
    lsr
    move r1, r0
    iwt r6, #256
    from r1
    cmp r6
    bge _ddy_vl
    nop
    from r1
    to r0
    add r1
    iwt r1, #((recip_tbl - $8000) & $FFFF)
    add r1
    move r14, r0
    getb
    move r1, r0
    inc r14
    getbh
    lsr
    sms ($18), r0
    iwt r15, #_ddy_done - $8000
    nop
_ddy_vl:
    iwt r0, #1
    sms ($18), r0
_ddy_done:

    ; === Step 3: step directions and initial sideDist ===

    ; mapX = posX >> 8
    lms r0, ($00)           ; posX
    from r0
    to r0
    hib                     ; r0 = posX >> 8 (high byte, already clean 0..255)
    sms ($22), r0

    ; mapY = posY >> 8
    lms r0, ($02)           ; posY
    from r0
    to r0
    hib
    sms ($24), r0

    ; --- stepX and sideDistX ---
    lms r0, ($12)           ; rayDirX
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bge _sx_pos
    nop

    ; rayDirX < 0: stepX = -1
    iwt r0, #-1
    sms ($1E), r0
    ; fracX = posX & 0xFF
    lms r0, ($00)           ; posX
    from r0
    to r0
    lob                     ; r0 = posX & 0xFF
    move r6, r0             ; r6 = fracX
    lms r0, ($16)           ; deltaDistX
    link #4
    iwt r15, #frac_mul_sub - $8000
    nop
    sms ($1A), r0           ; sideDistX
    iwt r15, #_sx_done - $8000
    nop

_sx_pos:
    iwt r0, #1
    sms ($1E), r0
    ; fracX = 256 - (posX & 0xFF)
    lms r0, ($00)           ; posX
    from r0
    to r0
    lob                     ; low byte
    move r1, r0
    iwt r0, #256
    sub r1
    move r6, r0             ; r6 = fracX
    lms r0, ($16)           ; deltaDistX
    link #4
    iwt r15, #frac_mul_sub - $8000
    nop
    sms ($1A), r0
_sx_done:

    ; --- stepY and sideDistY ---
    lms r0, ($14)           ; rayDirY
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bge _sy_pos
    nop

    iwt r0, #-1
    sms ($20), r0
    lms r0, ($02)           ; posY
    from r0
    to r0
    lob
    move r6, r0
    lms r0, ($18)           ; deltaDistY
    link #4
    iwt r15, #frac_mul_sub - $8000
    nop
    sms ($1C), r0
    iwt r15, #_sy_done - $8000
    nop

_sy_pos:
    iwt r0, #1
    sms ($20), r0
    lms r0, ($02)           ; posY
    from r0
    to r0
    lob
    move r1, r0
    iwt r0, #256
    sub r1
    move r6, r0
    lms r0, ($18)           ; deltaDistY
    link #4
    iwt r15, #frac_mul_sub - $8000
    nop
    sms ($1C), r0
_sy_done:

    ; === Step 4: DDA loop ===
    iwt r0, #0
    sms ($26), r0           ; side = 0
    iwt r10, #0             ; step counter
    iwt r9, #0              ; hit flag

_dda_loop:
    ibt r0, #MAX_STEPS
    from r10
    cmp r0
    blt _dda_notmax         ; if steps < MAX, continue
    nop
    iwt r15, #_dda_done - $8000
    nop
_dda_notmax:

    ; Compare sideDistX vs sideDistY
    lms r0, ($1A)           ; sideDistX
    move r1, r0
    lms r0, ($1C)           ; sideDistY
    from r1
    cmp r0
    bge _dda_stepy
    nop

    ; Step X
    lms r0, ($1A)
    move r1, r0
    lms r0, ($16)           ; deltaDistX
    add r1
    sms ($1A), r0
    lms r0, ($22)           ; mapX
    move r1, r0
    lms r0, ($1E)           ; stepX
    add r1
    sms ($22), r0
    iwt r0, #0
    sms ($26), r0           ; side = 0
    iwt r15, #_dda_check - $8000
    nop

_dda_stepy:
    lms r0, ($1C)
    move r1, r0
    lms r0, ($18)           ; deltaDistY
    add r1
    sms ($1C), r0
    lms r0, ($24)           ; mapY
    move r1, r0
    lms r0, ($20)           ; stepY
    add r1
    sms ($24), r0
    iwt r0, #1
    sms ($26), r0           ; side = 1

_dda_check:
    ; Bounds check -- use inverted branches + long jump for far target
    lms r0, ($22)           ; mapX
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bge _dda_mx_ok          ; mapX >= 0, continue
    nop
    iwt r15, #_dda_done - $8000
    nop
_dda_mx_ok:
    ibt r0, #MAP_W
    from r1
    cmp r0
    blt _dda_mx_ok2         ; mapX < MAP_W, continue
    nop
    iwt r15, #_dda_done - $8000
    nop
_dda_mx_ok2:

    lms r0, ($24)           ; mapY
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bge _dda_my_ok
    nop
    iwt r15, #_dda_done - $8000
    nop
_dda_my_ok:
    ibt r0, #MAP_H
    from r1
    cmp r0
    blt _dda_my_ok2
    nop
    iwt r15, #_dda_done - $8000
    nop
_dda_my_ok2:

    ; Map lookup: world_map[mapY * 10 + mapX]
    lms r0, ($24)           ; mapY
    move r1, r0
    from r1
    to r0
    add r1                  ; *2
    move r2, r0
    add r0                  ; *4
    add r0                  ; *8
    add r2                  ; *10
    move r1, r0
    lms r0, ($22)           ; mapX
    add r1
    iwt r1, #((map_data - $8000) & $FFFF)
    add r1
    move r14, r0
    getb                    ; r0 = map cell (byte, already 0-extended by getb)
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    beq _dda_nohit
    nop

    ; Wall hit
    iwt r9, #1
    iwt r15, #_dda_done - $8000
    nop

_dda_nohit:
    inc r10
    iwt r15, #_dda_loop - $8000
    nop

_dda_done:

    ; === Step 5: perpDist ===
    move r0, r9             ; hit flag
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bne _pd_hit
    nop
    iwt r0, #$0400          ; 4.0 in 8.8
    sms ($28), r0
    iwt r15, #_pd_done - $8000
    nop

_pd_hit:
    lms r0, ($26)           ; side
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bne _pd_side1
    nop
    ; side == 0: perpDist = sideDistX - deltaDistX
    lms r0, ($1A)
    move r1, r0
    lms r0, ($16)
    move r2, r0
    move r0, r1
    sub r2
    sms ($28), r0
    iwt r15, #_pd_done - $8000
    nop

_pd_side1:
    lms r0, ($1C)
    move r1, r0
    lms r0, ($18)
    move r2, r0
    move r0, r1
    sub r2
    sms ($28), r0

_pd_done:
    ; Clamp perpDist >= 1
    lms r0, ($28)
    move r1, r0
    ibt r0, #1
    from r1
    cmp r0
    bge _pd_ok
    nop
    ibt r0, #1
    sms ($28), r0
_pd_ok:

    ; === Step 6: wall height ===
    lms r0, ($28)           ; perpDist
    move r1, r0
    iwt r0, #256
    from r1
    cmp r0
    bge _ht_calc
    nop
    ; perpDist < 256 (< 1.0): full height
    ibt r0, #SCREEN_H
    sms ($2A), r0
    iwt r15, #_ht_got - $8000
    nop

_ht_calc:
    ; Index = perpDist >> 2, clamped 1..255
    move r0, r1
    lsr
    lsr
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bne _ht_nz
    nop
    ibt r1, #1
_ht_nz:
    iwt r0, #255
    from r1
    cmp r0
    blt _ht_ok
    nop
    iwt r1, #255
_ht_ok:
    move r0, r1
    iwt r1, #((height_tbl - $8000) & $FFFF)
    add r1
    move r14, r0
    getb                    ; r0 = height (byte from ROM)
    sms ($2A), r0

_ht_got:
    ; drawStart = HALF_H - lineHeight/2
    ; drawEnd = HALF_H + lineHeight/2 - 1
    lms r0, ($2A)
    lsr                     ; half = lineHeight / 2
    move r2, r0             ; r2 = half
    ibt r0, #HALF_H
    sub r2                  ; drawStart
    ; Clamp >= 0
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bge _ds_ok
    nop
    ibt r1, #0
_ds_ok:
    move r0, r1
    sms ($2A), r0           ; drawStart

    ibt r0, #HALF_H
    add r2
    sub #1                  ; drawEnd
    ; Clamp < SCREEN_H
    move r1, r0
    ibt r0, #SCREEN_H
    from r1
    cmp r0
    blt _de_ok
    nop
    ibt r0, #SCREEN_H
    sub #1
    move r1, r0
_de_ok:
    ; Clamp drawEnd >= drawStart
    move r3, r1             ; r3 = drawEnd
    lms r0, ($2A)           ; drawStart
    move r4, r0
    from r3
    cmp r4
    bge _de_ok2
    nop
    move r3, r4
_de_ok2:
    sms ($2C), r3

    ; Wall color
    lms r0, ($26)           ; side
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bne _wc_dark
    nop
    ibt r0, #WALL_BRIGHT
    sms ($2E), r0
    iwt r15, #_store_col - $8000
    nop
_wc_dark:
    ibt r0, #WALL_DARK
    sms ($2E), r0

    ; === Step 7: Store ray result in column arrays ===
_store_col:
    lms r0, ($10)           ; r0 = col (0-31)
    ; drawStart[col] at $00C0+col
    move r1, r0
    iwt r2, #$00C0
    with r1
    add r2
    lms r0, ($2A)           ; drawStart
    stb (r1)

    lms r0, ($10)
    move r1, r0
    iwt r2, #$00E0
    with r1
    add r2
    lms r0, ($2C)           ; drawEnd
    stb (r1)

    lms r0, ($10)
    move r1, r0
    iwt r2, #$0100
    with r1
    add r2
    lms r0, ($2E)           ; wallColor
    stb (r1)

    ; === Next ray ===
    lms r0, ($10)
    add #1
    sms ($10), r0
    move r11, r0

    ibt r0, #NUM_COLS       ; 32 rays
    from r11
    cmp r0
    bge _all_rays_done
    nop
    iwt r15, #_col_loop - $8000
    nop

_all_rays_done:

    ; =================================================================
    ; PHASE 2: TILE RENDERING (sub-column pairs)
    ; =================================================================
    ; 16 tile columns, each with 2 sub-columns (left 4px + right 4px)
    ; Reads drawStart/drawEnd/wallColor from arrays at $C0/$E0/$100

    ibt r0, #0
    sms ($30), r0           ; tileCol = 0

_render_tilecol:
    ; Load sub-column A (left) and B (right) data
    ; Sub-col A = ray index tileCol*2, Sub-col B = ray index tileCol*2+1
    lms r0, ($30)           ; tileCol
    add r0                  ; tileCol*2 = ray index A

    ; Read sub-col A
    move r1, r0
    iwt r2, #$00C0
    with r1
    add r2
    ldb (r1)                ; r0 = drawStartA
    sms ($32), r0           ; save drawStartA
    lms r0, ($30)
    add r0
    move r1, r0
    iwt r2, #$00E0
    with r1
    add r2
    ldb (r1)                ; r0 = drawEndA
    sms ($34), r0
    lms r0, ($30)
    add r0
    move r1, r0
    iwt r2, #$0100
    with r1
    add r2
    ldb (r1)                ; r0 = wallColorA
    sms ($36), r0

    ; Read sub-col B (ray index = tileCol*2 + 1)
    lms r0, ($30)
    add r0
    add #1
    move r1, r0
    iwt r2, #$00C0
    with r1
    add r2
    ldb (r1)
    sms ($38), r0           ; drawStartB
    lms r0, ($30)
    add r0
    add #1
    move r1, r0
    iwt r2, #$00E0
    with r1
    add r2
    ldb (r1)
    sms ($3A), r0           ; drawEndB
    lms r0, ($30)
    add r0
    add #1
    move r1, r0
    iwt r2, #$0100
    with r1
    add r2
    ldb (r1)
    sms ($3C), r0           ; wallColorB

    ; Load into registers for render loop
    lms r5, ($32)           ; drawStartA
    lms r6, ($34)           ; drawEndA
    lms r7, ($36)           ; wallColorA

    iwt r8, #0              ; Y = 0
    iwt r2, #0              ; tileY = 0

_tilerow_loop:
    ; tileBase = FRAMEBUF + (tileY*16 + tileCol) * 64
    from r2
    to r0
    add r2                  ; *2
    add r0                  ; *4
    add r0                  ; *8
    add r0                  ; *16
    move r11, r0
    lms r0, ($30)           ; tileCol
    add r11                 ; tileIndex

    ; *64
    from r0
    to r4
    add r0                  ; *2
    from r4
    to r4
    add r4                  ; *4
    from r4
    to r4
    add r4                  ; *8
    from r4
    to r4
    add r4                  ; *16
    from r4
    to r4
    add r4                  ; *32
    from r4
    to r4
    add r4                  ; *64

    iwt r0, #FRAMEBUF
    from r4
    to r4
    add r0                  ; r4 = tileBase

    iwt r1, #0              ; py = 0

_pixrow_loop:
    ; === Sub-column A color (left 4 pixels) ===
    from r8
    cmp r5                  ; Y < drawStartA?
    bge _chk_wallA
    nop
    iwt r9, #CEIL_COLOR
    bra _colA_done
    nop
_chk_wallA:
    from r6
    cmp r8                  ; drawEndA >= Y?
    blt _floorA
    nop
    move r9, r7             ; wallColorA
    bra _colA_done
    nop
_floorA:
    iwt r9, #FLOOR_COLOR
_colA_done:

    ; === Sub-column B color (right 4 pixels) ===
    lms r0, ($38)           ; drawStartB (reload from RAM)
    from r8
    cmp r0                  ; Y < drawStartB?
    bge _chk_wallB
    nop
    iwt r10, #CEIL_COLOR
    bra _colB_done
    nop
_chk_wallB:
    lms r0, ($3A)           ; drawEndB
    from r0
    cmp r8                  ; drawEndB >= Y?
    blt _floorB
    nop
    lms r10, ($3C)          ; wallColorB
    bra _colB_done
    nop
_floorB:
    iwt r10, #FLOOR_COLOR
_colB_done:

    ; === Write 8 pixels: 4 of colorA + 4 of colorB ===
    ; addr = tileBase + py*8
    from r1
    to r0
    add r1                  ; py*2
    add r0                  ; py*4
    add r0                  ; py*8
    from r4
    to r3
    add r0                  ; r3 = write address

    ; Left 4 pixels (sub-col A)
    move r0, r9
    stb (r3)
    inc r3
    stb (r3)
    inc r3
    stb (r3)
    inc r3
    stb (r3)
    inc r3
    ; Right 4 pixels (sub-col B)
    move r0, r10
    stb (r3)
    inc r3
    stb (r3)
    inc r3
    stb (r3)
    inc r3
    stb (r3)

    inc r1                  ; py++
    inc r8                  ; Y++
    ibt r0, #8
    from r1
    cmp r0
    blt _pixrow_loop
    nop

    inc r2                  ; tileY++
    ibt r0, #12
    from r2
    cmp r0
    bge _tilerow_done
    nop
    iwt r15, #_tilerow_loop - $8000
    nop
_tilerow_done:

    ; === Next tile column ===
    lms r0, ($30)
    add #1
    sms ($30), r0
    move r11, r0

    ibt r0, #TILE_COLS      ; 16 tile columns
    from r11
    cmp r0
    bge _all_done
    nop
    iwt r15, #_render_tilecol - $8000
    nop

_all_done:
    stop
    nop

; -------------------------------------------------------
; fp_mul_sub: signed 8.8 * 8.8 -> 8.8 multiply
;
; Input:  R0 = A (signed 8.8), R6 = B (signed 8.8)
; Output: R0 = (A * B) >> 8
; Clobbers: R1-R6
; Uses: umult (unsigned 8x8->16)
; -------------------------------------------------------
fp_mul_sub:
    ; link #4 must be at CALL SITE, not here. R11 already has return addr.

    iwt r3, #0              ; sign flag

    ; Make A positive
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    bge _fpm_a_pos
    nop
    ibt r0, #0
    sub r1
    move r1, r0
    iwt r3, #1
_fpm_a_pos:

    ; Make B positive
    move r2, r6
    ibt r0, #0
    from r2
    cmp r0
    bge _fpm_b_pos
    nop
    ibt r0, #0
    sub r2
    move r2, r0
    ; Toggle sign
    move r0, r3
    move r4, r0
    ibt r0, #0
    from r4
    cmp r0
    bne _fpm_s0
    nop
    iwt r3, #1
    iwt r15, #_fpm_b_pos - $8000
    nop
_fpm_s0:
    iwt r3, #0
_fpm_b_pos:

    ; r1 = |A|, r2 = |B|, r3 = sign
    ; Extract bytes: Ah, Al, Bh, Bl
    from r1
    to r0
    hib                     ; Ah (hib gives clean byte)
    move r4, r0             ; r4 = Ah

    from r1
    to r0
    lob                     ; Al
    move r1, r0             ; r1 = Al

    from r2
    to r0
    hib
    move r6, r0             ; r6 = Bh

    from r2
    to r0
    lob
    move r2, r0             ; r2 = Bl

    ; Partial 1: (Al * Bl) >> 8
    move r0, r1
    umult r2                ; R0 = Al * Bl
    from r0
    to r0
    hib                     ; (Al * Bl) >> 8
    move r5, r0

    ; Partial 2: Ah * Bl
    move r0, r4
    umult r2
    from r0
    to r0
    add r5
    move r5, r0

    ; Partial 3: Al * Bh
    move r0, r1
    umult r6
    from r0
    to r0
    add r5
    move r5, r0

    ; Partial 4: (Ah * Bh) << 8
    move r0, r4
    umult r6                ; R0 = Ah * Bh (max 255*255 = 65025 = $FE01)
    ; Shift left 8: use swap (swaps hi/lo bytes)
    ; But we only want (Ah*Bh) << 8 = (Ah*Bh).lo_byte in high position
    ; After swap: hi_byte goes to lo, lo_byte goes to hi
    ; The low byte of the product (which should go to high byte) is correct
    ; But the high byte of the product in low position is garbage we don't want
    ; Since Ah and Bh are at most ~10 for our game, Ah*Bh < 100, fits in low byte
    ; So high byte of product is 0, and swap gives: (lo_byte << 8) | 0. Perfect.
    from r0
    to r0
    swap                    ; R0 = (Ah*Bh) << 8
    add r5
    move r5, r0

    ; Apply sign
    move r0, r3
    move r1, r0
    ibt r0, #0
    from r1
    cmp r0
    beq _fpm_ret
    nop
    ibt r0, #0
    sub r5
    move r5, r0
_fpm_ret:
    move r0, r5
    move r15, r11
    nop

; -------------------------------------------------------
; frac_mul_sub: (frac * deltaDist) >> 8
;
; Input:  R0 = deltaDist (unsigned 8.8)
;         R6 = frac (0..256)
; Output: R0 = result
; Clobbers: R1-R5
; -------------------------------------------------------
frac_mul_sub:
    ; link #4 must be at CALL SITE. R11 already has return addr.

    move r1, r0             ; r1 = deltaDist
    move r2, r6             ; r2 = frac

    ; dHi = deltaDist >> 8
    from r1
    to r0
    hib
    move r3, r0             ; r3 = dHi

    ; dLo = deltaDist & 0xFF
    from r1
    to r0
    lob
    move r4, r0             ; r4 = dLo

    ; (frac * dLo) >> 8
    move r0, r2
    umult r4
    from r0
    to r0
    hib
    move r5, r0

    ; frac * dHi
    move r0, r2
    umult r3
    add r5

    move r15, r11
    nop

; -------------------------------------------------------
; ROM DATA TABLES
; -------------------------------------------------------

cameraX_tbl:
    .dw -256, -240, -224, -208, -192, -176, -160, -144
    .dw -128, -112, -96, -80, -64, -48, -32, -16
    .dw 0, 16, 32, 48, 64, 80, 96, 112
    .dw 128, 144, 160, 176, 192, 208, 224, 240

recip_tbl:
    .dw 32767, 32767, 32767, 21845, 16384, 13107, 10922, 9362
    .dw 8192, 7281, 6553, 5957, 5461, 5041, 4681, 4369
    .dw 4096, 3855, 3640, 3449, 3276, 3120, 2978, 2849
    .dw 2730, 2621, 2520, 2427, 2340, 2259, 2184, 2114
    .dw 2048, 1985, 1927, 1872, 1820, 1771, 1724, 1680
    .dw 1638, 1598, 1560, 1524, 1489, 1456, 1424, 1394
    .dw 1365, 1337, 1310, 1285, 1260, 1236, 1213, 1191
    .dw 1170, 1149, 1129, 1110, 1092, 1074, 1057, 1040
    .dw 1024, 1008, 992, 978, 963, 949, 936, 923
    .dw 910, 897, 885, 873, 862, 851, 840, 829
    .dw 819, 809, 799, 789, 780, 771, 762, 753
    .dw 744, 736, 728, 720, 712, 704, 697, 689
    .dw 682, 675, 668, 661, 655, 648, 642, 636
    .dw 630, 624, 618, 612, 606, 601, 595, 590
    .dw 585, 579, 574, 569, 564, 560, 555, 550
    .dw 546, 541, 537, 532, 528, 524, 520, 516
    .dw 512, 508, 504, 500, 496, 492, 489, 485
    .dw 481, 478, 474, 471, 468, 464, 461, 458
    .dw 455, 451, 448, 445, 442, 439, 436, 434
    .dw 431, 428, 425, 422, 420, 417, 414, 412
    .dw 409, 407, 404, 402, 399, 397, 394, 392
    .dw 390, 387, 385, 383, 381, 378, 376, 374
    .dw 372, 370, 368, 366, 364, 362, 360, 358
    .dw 356, 354, 352, 350, 348, 346, 344, 343
    .dw 341, 339, 337, 336, 334, 332, 330, 329
    .dw 327, 326, 324, 322, 321, 319, 318, 316
    .dw 315, 313, 312, 310, 309, 307, 306, 304
    .dw 303, 302, 300, 299, 297, 296, 295, 293
    .dw 292, 291, 289, 288, 287, 286, 284, 283
    .dw 282, 281, 280, 278, 277, 276, 275, 274
    .dw 273, 271, 270, 269, 268, 267, 266, 265
    .dw 264, 263, 262, 261, 260, 259, 258, 257

height_tbl:
    .db 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96
    .db 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96
    .db 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96
    .db 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96, 96
    .db 96, 95, 93, 92, 90, 89, 88, 87, 85, 84, 83, 82, 81, 80, 79, 78
    .db 77, 76, 75, 74, 73, 72, 71, 71, 70, 69, 68, 68, 67, 66, 65, 65
    .db 64, 63, 63, 62, 61, 61, 60, 60, 59, 59, 58, 57, 57, 56, 56, 55
    .db 55, 54, 54, 53, 53, 53, 52, 52, 51, 51, 50, 50, 50, 49, 49, 48
    .db 48, 48, 47, 47, 47, 46, 46, 46, 45, 45, 45, 44, 44, 44, 43, 43
    .db 43, 42, 42, 42, 42, 41, 41, 41, 40, 40, 40, 40, 39, 39, 39, 39
    .db 38, 38, 38, 38, 37, 37, 37, 37, 37, 36, 36, 36, 36, 36, 35, 35
    .db 35, 35, 35, 34, 34, 34, 34, 34, 33, 33, 33, 33, 33, 33, 32, 32
    .db 32, 32, 32, 32, 31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 30
    .db 30, 29, 29, 29, 29, 29, 29, 29, 28, 28, 28, 28, 28, 28, 28, 28
    .db 27, 27, 27, 27, 27, 27, 27, 27, 26, 26, 26, 26, 26, 26, 26, 26
    .db 26, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 24, 24, 24, 24, 24

map_data:
    .db 1,1,1,1,1,1,1,1,1,1
    .db 1,0,0,0,0,0,0,0,0,1
    .db 1,0,0,0,0,0,0,0,0,1
    .db 1,0,0,0,0,0,0,0,0,1
    .db 1,0,0,0,2,2,0,0,0,1
    .db 1,0,0,0,2,2,0,0,0,1
    .db 1,0,0,0,0,0,0,0,0,1
    .db 1,0,0,0,0,0,0,0,0,1
    .db 1,0,0,0,0,0,0,0,0,1
    .db 1,1,1,1,1,1,1,1,1,1

.ENDS
