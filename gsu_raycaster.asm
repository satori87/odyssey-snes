; GSU DDA Raycaster — stb-based bitplane renderer (Doom resolution 216x144)
;
; Phase 1: Cast 27 rays via DDA, compute drawStart/drawEnd/wallColor
; Phase 2: Row-by-row tile rendering using stb (no plot instruction)

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

.define SCREEN_H     144
.define HALF_H       72
.define NUM_COLS     27
.define NUM_TROWS    18
.define MAP_W        10
.define MAP_H        10
.define FB_BASE      $0400
.define TILE_SIZE    64

.define RAM_POSX      $0000
.define RAM_POSY      $0002
.define RAM_DIRX      $0004
.define RAM_DIRY      $0006
.define RAM_PLANEX    $0008
.define RAM_PLANEY    $000A
.define RAM_DRAWSTART $0040
.define RAM_DRAWEND   $0060
.define RAM_WALLCOLOR $0080
.define RAM_RAYDIRX    $00A0
.define RAM_RAYDIRY    $00A2
.define RAM_DELTADX    $00A4
.define RAM_DELTADY    $00A6
.define RAM_SIDEDX     $00A8
.define RAM_SIDEDY     $00AA
.define RAM_STEPX      $00AC
.define RAM_STEPY      $00AE
.define RAM_MAPX       $00B0
.define RAM_MAPY       $00B2
.define RAM_SIDE       $00B4
.define RAM_COL        $00B6
.define RAM_PERPDIST   $00B8
.define RAM_FRACX      $00BA
.define RAM_FRACY      $00BC
.define RAM_SCRATCH    $00BE
.define RAM_CEIL_BP   $00C0
.define RAM_WALL_BP   $00C8
.define RAM_FLOOR_BP  $00D0
.define RAM_TROW_Y    $00D8

.BANK 0
.SECTION "GSUCode" SUPERFREE

gsu_fill_screen:
    iwt r0, #$70
    ramb
    ibt r0, #0
    romb

    ; ===== PHASE 1: DDA Raycasting (27 columns) =====
    ibt r0, #0
    sm (RAM_COL), r0

_phase1_loop:
    lm r9, (RAM_COL)

    ; --- Read cameraX[col] from ROM ---
    from r9
    add r9                  ; r0 = col * 2
    iwt r1, #(cameraX_tbl - $8000)
    to r14
    add r1                  ; r14 -> cameraX_tbl[col]
    getb
    getbh                   ; r0 = cameraX[col] (s16 8.8)
    sm (RAM_SCRATCH), r0    ; save cameraX for rayDirY calc

    ; --- rayDirX = dirX + fp_mul(planeX, cameraX) ---
    lm r1, (RAM_PLANEX)    ; r1 = planeX
    ; r0 = cameraX
    ; Need r0 in r3 for fp_mul(r1, r3)
    to r3
    move r3, r0
    ; Inline fp_mul: result -> r10
    ; Make both positive, track sign in r5
    ibt r5, #0
    moves r0, r1            ; test r1 sign
    bpl _fp1_apos
    nop
    with r1
    not
    inc r1                  ; r1 = |planeX|
    ibt r5, #1
_fp1_apos:
    moves r0, r3            ; test r3 sign
    bpl _fp1_bpos
    nop
    with r3
    not
    inc r3                  ; r3 = |cameraX|
    ; flip sign: r5 = 1 - r5
    ibt r0, #1
    from r0
    to r5
    sub r5
_fp1_bpos:
    ; r1 = |a|, r3 = |b|, r5 = neg flag
    ; Decompose: ah=r1>>8, al=r1&FF, bh=r3>>8, bl=r3&FF
    from r1
    hib                     ; r0 = ah
    to r7
    move r7, r0
    from r1
    lob                     ; r0 = al
    to r6
    move r6, r0
    from r3
    hib                     ; r0 = bh
    to r8
    move r8, r0
    from r3
    lob                     ; r0 = bl
    to r11
    move r11, r0

    ; (ah * bh) << 8
    move r0, r7
    umult r8                ; r0 = ah * bh
    swap                    ; r0 <<= 8 (swap hi/lo bytes)
    to r10
    move r10, r0

    ; ah * bl
    move r0, r7
    umult r11               ; r0 = ah * bl
    with r10
    add r0

    ; al * bh
    move r0, r6
    umult r8                ; r0 = al * bh
    with r10
    add r0

    ; (al * bl) >> 8
    move r0, r6
    umult r11               ; r0 = al * bl
    swap
    lob                     ; r0 = (al*bl) >> 8
    with r10
    add r0

    ; Apply sign
    ibt r0, #0
    from r5
    cmp r0                  ; r5 == 0?
    beq _fp1_done
    nop
    from r10
    not
    inc r0
    to r10
    move r10, r0
_fp1_done:
    ; r10 = fp_mul(planeX, cameraX)
    lm r1, (RAM_DIRX)
    from r10
    to r0
    add r1                  ; r0 = dirX + result = rayDirX
    sm (RAM_RAYDIRX), r0

    ; --- rayDirY = dirY + fp_mul(planeY, cameraX) ---
    lm r1, (RAM_PLANEY)
    lm r3, (RAM_SCRATCH)   ; r3 = cameraX

    ibt r5, #0
    moves r0, r1
    bpl _fp2_apos
    nop
    with r1
    not
    inc r1
    ibt r5, #1
_fp2_apos:
    moves r0, r3
    bpl _fp2_bpos
    nop
    with r3
    not
    inc r3
    ibt r0, #1
    from r0
    to r5
    sub r5
_fp2_bpos:
    from r1
    hib
    to r7
    move r7, r0
    from r1
    lob
    to r6
    move r6, r0
    from r3
    hib
    to r8
    move r8, r0
    from r3
    lob
    to r11
    move r11, r0

    move r0, r7
    umult r8
    swap
    to r10
    move r10, r0
    move r0, r7
    umult r11
    with r10
    add r0
    move r0, r6
    umult r8
    with r10
    add r0
    move r0, r6
    umult r11
    swap
    lob
    with r10
    add r0

    ibt r0, #0
    from r5
    cmp r0
    beq _fp2_done
    nop
    from r10
    not
    inc r0
    to r10
    move r10, r0
_fp2_done:
    lm r1, (RAM_DIRY)
    from r10
    to r0
    add r1
    sm (RAM_RAYDIRY), r0

    ; --- Compute deltaDistX = recip_tbl[clamp(|rayDirX|, 1, 255)] ---
    lm r0, (RAM_RAYDIRX)
    moves r0, r0            ; set flags
    bpl _ddx_pos
    nop
    from r0
    not
    inc r0                  ; r0 = |rayDirX|
_ddx_pos:
    ; Clamp to 1-255
    ibt r1, #0
    from r0
    cmp r1
    bne _ddx_nz
    nop
    iwt r0, #$7FFF
    sm (RAM_DELTADX), r0
    bra _ddx_end
    nop
_ddx_nz:
    iwt r1, #256
    from r0
    cmp r1
    blt _ddx_ok
    nop
    ibt r0, #255            ; clamp high; ibt sign-extends, but 255=$FF -> $FFFF
    lob                     ; r0 = $00FF = 255
_ddx_ok:
    ; Lookup: recip_tbl[r0], 2 bytes per entry
    from r0
    add r0                  ; r0 = index * 2
    iwt r1, #(recip_tbl - $8000)
    to r14
    add r1
    getb
    getbh                   ; r0 = recip value (u16)
    sm (RAM_DELTADX), r0
_ddx_end:

    ; --- Compute deltaDistY ---
    lm r0, (RAM_RAYDIRY)
    moves r0, r0
    bpl _ddy_pos
    nop
    from r0
    not
    inc r0
_ddy_pos:
    ibt r1, #0
    from r0
    cmp r1
    bne _ddy_nz
    nop
    iwt r0, #$7FFF
    sm (RAM_DELTADY), r0
    bra _ddy_end
    nop
_ddy_nz:
    iwt r1, #256
    from r0
    cmp r1
    blt _ddy_ok
    nop
    ibt r0, #255
    lob
_ddy_ok:
    from r0
    add r0
    iwt r1, #(recip_tbl - $8000)
    to r14
    add r1
    getb
    getbh
    sm (RAM_DELTADY), r0
_ddy_end:

    ; --- Initialize mapX, mapY, fracX, fracY ---
    lm r0, (RAM_POSX)
    to r1
    move r1, r0
    hib                     ; r0 = posX >> 8 = mapX (integer part)
    sm (RAM_MAPX), r0
    from r1
    lob                     ; r0 = posX & FF = fracX
    sm (RAM_FRACX), r0

    lm r0, (RAM_POSY)
    to r1
    move r1, r0
    hib
    sm (RAM_MAPY), r0
    from r1
    lob
    sm (RAM_FRACY), r0

    ; --- Compute stepX, sideDistX ---
    ; if rayDirX < 0: stepX=-1, sideDistX = fracX * deltaDist / 256
    ; if rayDirX >= 0: stepX=+1, sideDistX = (256 - fracX) * deltaDist / 256
    lm r0, (RAM_RAYDIRX)
    moves r0, r0
    bmi _stepx_neg
    nop

    ; rayDirX >= 0
    ibt r0, #1
    sm (RAM_STEPX), r0
    iwt r0, #256
    lm r1, (RAM_FRACX)
    from r0
    to r0
    sub r1                  ; r0 = 256 - fracX
    bra _sdx_calc
    nop

_stepx_neg:
    iwt r0, #$FFFF
    sm (RAM_STEPX), r0
    lm r0, (RAM_FRACX)

_sdx_calc:
    ; r0 = frac (0-256). Multiply by deltaDistX >> 8
    ; sideDistX = (frac * deltaDistX) >> 8
    ; Clamp frac to 255 for u8 multiply
    to r6
    move r6, r0
    iwt r1, #256
    from r6
    cmp r1
    blt _sdx_small
    nop
    ; frac >= 256 means full step
    lm r0, (RAM_DELTADX)
    sm (RAM_SIDEDX), r0
    bra _sdx_done
    nop
_sdx_small:
    ; frac * deltaDist_hi + (frac * deltaDist_lo) >> 8
    lm r0, (RAM_DELTADX)
    to r7
    move r7, r0             ; r7 = deltaDist
    hib                      ; r0 = deltaDist >> 8 = hi
    to r8
    move r8, r0
    from r7
    lob                      ; r0 = deltaDist & FF = lo
    to r11
    move r11, r0

    move r0, r6              ; r0 = frac
    umult r8                 ; r0 = frac * hi
    to r10
    move r10, r0

    move r0, r6
    umult r11                ; r0 = frac * lo
    swap
    lob                      ; r0 = (frac * lo) >> 8
    with r10
    add r0
    sm (RAM_SIDEDX), r10
_sdx_done:

    ; --- Compute stepY, sideDistY ---
    lm r0, (RAM_RAYDIRY)
    moves r0, r0
    bmi _stepy_neg
    nop

    ibt r0, #1
    sm (RAM_STEPY), r0
    iwt r0, #256
    lm r1, (RAM_FRACY)
    from r0
    to r0
    sub r1
    bra _sdy_calc
    nop

_stepy_neg:
    iwt r0, #$FFFF
    sm (RAM_STEPY), r0
    lm r0, (RAM_FRACY)

_sdy_calc:
    to r6
    move r6, r0
    iwt r1, #256
    from r6
    cmp r1
    blt _sdy_small
    nop
    lm r0, (RAM_DELTADY)
    sm (RAM_SIDEDY), r0
    bra _sdy_done
    nop
_sdy_small:
    lm r0, (RAM_DELTADY)
    to r7
    move r7, r0
    hib
    to r8
    move r8, r0
    from r7
    lob
    to r11
    move r11, r0
    move r0, r6
    umult r8
    to r10
    move r10, r0
    move r0, r6
    umult r11
    swap
    lob
    with r10
    add r0
    sm (RAM_SIDEDY), r10
_sdy_done:

    ; === DDA step loop ===
    ibt r11, #0              ; step counter (safety limit)

_dda_loop:
    ; Which side to step? Compare sideDistX vs sideDistY
    lm r0, (RAM_SIDEDX)
    lm r1, (RAM_SIDEDY)
    from r0
    cmp r1
    blt _dda_xstep           ; sideDistX < sideDistY -> step X
    nop

    ; --- Step Y ---
    lm r0, (RAM_SIDEDY)
    lm r1, (RAM_DELTADY)
    from r0
    to r0
    add r1
    sm (RAM_SIDEDY), r0
    lm r0, (RAM_MAPY)
    lm r1, (RAM_STEPY)
    from r0
    to r0
    add r1
    sm (RAM_MAPY), r0
    ibt r0, #1
    sm (RAM_SIDE), r0
    bra _dda_check
    nop

_dda_xstep:
    ; --- Step X ---
    lm r0, (RAM_SIDEDX)
    lm r1, (RAM_DELTADX)
    from r0
    to r0
    add r1
    sm (RAM_SIDEDX), r0
    lm r0, (RAM_MAPX)
    lm r1, (RAM_STEPX)
    from r0
    to r0
    add r1
    sm (RAM_MAPX), r0
    ibt r0, #0
    sm (RAM_SIDE), r0

_dda_check:
    ; --- Check map[mapY][mapX] ---
    lm r0, (RAM_MAPY)
    ; Bounds check: 0 <= mapY < MAP_H
    moves r0, r0
    bmi _dda_oob             ; negative -> out of bounds
    nop
    ibt r1, #MAP_H
    from r0
    cmp r1
    bge _dda_oob
    nop

    lm r1, (RAM_MAPX)
    moves r0, r1             ; test mapX
    bmi _dda_oob
    nop
    ibt r2, #MAP_W
    from r1
    cmp r2
    bge _dda_oob
    nop

    ; mapY * 10 + mapX
    ; mapY * 10 = mapY * 8 + mapY * 2
    lm r0, (RAM_MAPY)
    from r0
    to r2
    add r0                   ; r2 = mapY * 2
    from r2
    to r3
    add r2                   ; r3 = mapY * 4
    with r3
    add r3                   ; r3 = mapY * 8
    with r3
    add r2                   ; r3 = mapY * 8 + mapY * 2 = mapY * 10
    from r3
    to r0
    add r1                   ; r0 = mapY * 10 + mapX

    ; Read map tile from ROM
    iwt r1, #(map_data - $8000)
    to r14
    add r1
    getb                     ; r0 = map[mapY][mapX]

    ; Wall hit if nonzero
    ibt r1, #0
    from r0
    cmp r1
    bne _dda_hit_wall
    nop

    ; Continue stepping
    inc r11
    ibt r0, #30
    from r11
    cmp r0
    bge _dda_maxsteps         ; if stepCount >= 30, stop (inverted condition)
    nop
    ; Long branch back to DDA loop top
    iwt r15, #(_dda_loop - $8000)
    nop

_dda_maxsteps:
    ; Too many steps: default to wall 1
    bra _dda_oob
    nop

_dda_oob:
    ibt r0, #1               ; default wall color for out-of-bounds
_dda_hit_wall:
    ; r0 = wall tile value (1 or 2)
    ; Darken Y-side walls by adding 8 to color index
    to r6
    move r6, r0              ; r6 = wall color
    lm r0, (RAM_SIDE)
    ibt r1, #0
    from r0
    cmp r1
    beq _wc_done
    nop
    ibt r0, #8
    with r6
    add r0                   ; r6 += 8 for Y-side darkening
_wc_done:

    ; --- Perpendicular distance ---
    ; side==0: perpDist = sideDistX - deltaDistX
    ; side==1: perpDist = sideDistY - deltaDistY
    lm r0, (RAM_SIDE)
    ibt r1, #0
    from r0
    cmp r1
    bne _perp_y
    nop
    lm r0, (RAM_SIDEDX)
    lm r1, (RAM_DELTADX)
    bra _perp_sub
    nop
_perp_y:
    lm r0, (RAM_SIDEDY)
    lm r1, (RAM_DELTADY)
_perp_sub:
    from r0
    to r0
    sub r1                   ; r0 = sideDist - deltaDist = perpDist
    ; Clamp to >= 1
    moves r0, r0
    bpl _perp_pos
    nop
    ibt r0, #1               ; negative -> clamp to 1
_perp_pos:
    ibt r1, #0
    from r0
    cmp r1
    bne _perp_nz
    nop
    ibt r0, #1               ; zero -> clamp to 1
_perp_nz:
    sm (RAM_PERPDIST), r0

    ; --- Height lookup ---
    ; Index = perpDist >> 4 (covers 0 to ~15.9 tiles distance)
    lm r0, (RAM_PERPDIST)
    lsr
    lsr
    lsr
    lsr                      ; r0 = perpDist >> 4
    ; Clamp to 1-255
    ibt r1, #0
    from r0
    cmp r1
    bne _ht_nz
    nop
    ibt r0, #1               ; zero -> 1 (very close wall)
_ht_nz:
    iwt r1, #256
    from r0
    cmp r1
    blt _ht_ok
    nop
    ibt r0, #255
    lob                      ; clamp to 255
_ht_ok:
    ; height_tbl is byte-indexed (1 byte per entry)
    iwt r1, #(height_tbl - $8000)
    to r14
    add r1
    getb                     ; r0 = wall height (0-96)

    ; --- drawStart, drawEnd ---
    to r7
    move r7, r0              ; r7 = height
    from r7
    lsr                      ; r0 = height / 2
    to r8
    move r8, r0              ; r8 = halfHeight

    ; drawStart = HALF_H - halfHeight, clamped to >= 0
    ibt r0, #72
    from r0
    to r3
    sub r8                   ; r3 = 48 - halfHeight
    moves r0, r3             ; test sign
    bpl _ds_ok
    nop
    ibt r3, #0
_ds_ok:

    ; drawEnd = HALF_H + halfHeight - 1, clamped to <= 95
    ibt r0, #72
    from r0
    to r4
    add r8                   ; r4 = 48 + halfHeight
    ibt r0, #1
    from r4
    to r4
    sub r0                  ; r4 -= 1
    iwt r0, #143
    from r4
    cmp r0
    blt _de_ok
    nop
    iwt r4, #143
_de_ok:

    ; --- Store to RAM arrays ---
    lm r9, (RAM_COL)

    iwt r0, #RAM_DRAWSTART
    to r5
    add r9                   ; r5 = RAM_DRAWSTART + col
    move r0, r3              ; r0 = drawStart (stb always stores R0)
    stb (r5)                 ; drawStart[col] = r0.lo

    iwt r0, #RAM_DRAWEND
    to r5
    add r9
    move r0, r4              ; r0 = drawEnd
    stb (r5)                 ; drawEnd[col] = r0.lo

    iwt r0, #RAM_WALLCOLOR
    to r5
    add r9
    move r0, r6              ; r0 = wallColor
    stb (r5)                 ; wallColor[col] = r0.lo


    ; --- Next column ---
    lm r0, (RAM_COL)
    inc r0
    sm (RAM_COL), r0
    ibt r1, #27
    from r0
    cmp r1
    blt _p1_cont
    nop
    ; All columns done, go to Phase 2
    iwt r15, #(_phase2 - $8000)
    nop

_p1_cont:
    iwt r15, #(_phase1_loop - $8000)
    nop
_phase2:
    nop

    ; ===== Precompute BP bytes for ceiling (16) and floor (17) =====
    ; Color 16 = 00010000: BP4=$FF, rest $00
    iwt r1, #RAM_CEIL_BP
    ibt r0, #0
    stb (r1)                ; BP0
    inc r1
    stb (r1)                ; BP1
    inc r1
    stb (r1)                ; BP2
    inc r1
    stb (r1)                ; BP3
    inc r1
    ibt r0, #$FF
    lob
    stb (r1)                ; BP4=$FF
    inc r1
    ibt r0, #0
    stb (r1)                ; BP5
    inc r1
    stb (r1)                ; BP6
    inc r1
    stb (r1)                ; BP7

    ; Color 17 = 00010001: BP0=$FF, BP4=$FF, rest $00
    iwt r1, #RAM_FLOOR_BP
    ibt r0, #$FF
    lob
    stb (r1)                ; BP0=$FF
    inc r1
    ibt r0, #0
    stb (r1)                ; BP1
    inc r1
    stb (r1)                ; BP2
    inc r1
    stb (r1)                ; BP3
    inc r1
    ibt r0, #$FF
    lob
    stb (r1)                ; BP4=$FF
    inc r1
    ibt r0, #0
    stb (r1)                ; BP5
    inc r1
    stb (r1)                ; BP6
    inc r1
    stb (r1)                ; BP7

    ; ===== PHASE 2: Row-by-row tile rendering =====
    ; Process tiles sequentially (row 0 cols 0-26, row 1 cols 0-26, ...)
    ; For each tile: determine color, write 64 bytes of bitplane data

    iwt r1, #FB_BASE        ; r1 = tile write address (auto-advancing)
    ibt r3, #0              ; r3 = tile_row (0-17)
    ibt r0, #0
    sm (RAM_TROW_Y), r0     ; pixel_y of row start = 0

_trow_loop:
    ibt r2, #0              ; r2 = column (0-26)

_col_loop:
    ; Load drawStart[col] and drawEnd[col]
    iwt r0, #RAM_DRAWSTART
    to r4
    add r2
    ldb (r4)                ; r0 = drawStart[col]
    move r4, r0             ; r4 = drawStart

    iwt r0, #RAM_DRAWEND
    to r5
    add r2
    ldb (r5)                ; r0 = drawEnd[col]
    move r5, r0             ; r5 = drawEnd

    ; Load wallColor[col]
    iwt r0, #RAM_WALLCOLOR
    to r6
    add r2
    ldb (r6)                ; r0 = wallColor[col]
    move r6, r0             ; r6 = wallColor

    ; Precompute wall BP bytes (color varies per column)
    ; Color r6: for each bit N, BP[N] = $FF if set, $00 if clear
    iwt r7, #RAM_WALL_BP
    ; BP0 = bit 0
    from r6
    lob
    ibt r8, #1
    AND r8                  ; r0 = color & 1
    ibt r8, #0
    from r8
    to r0
    sub r0                  ; r0 = 0 - (color&1) = $0000 or $FFFF
    lob                     ; r0 = $00 or $FF
    stb (r7)
    inc r7
    ; BP1 = bit 1
    from r6
    lob
    lsr                     ; r0 = color >> 1
    ibt r8, #1
    AND r8
    ibt r8, #0
    from r8
    to r0
    sub r0
    lob
    stb (r7)
    inc r7
    ; BP2 = bit 2
    from r6
    lob
    lsr
    lsr
    ibt r8, #1
    AND r8
    ibt r8, #0
    from r8
    to r0
    sub r0
    lob
    stb (r7)
    inc r7
    ; BP3 = bit 3
    from r6
    lob
    lsr
    lsr
    lsr
    ibt r8, #1
    AND r8
    ibt r8, #0
    from r8
    to r0
    sub r0
    lob
    stb (r7)
    inc r7
    ; BP4 = bit 4
    from r6
    hib                     ; r0 = color >> 8... no, hib gives high byte
    ; Actually for 8-bit color, bits 4-7 need: color >> 4
    from r6
    lob
    lsr
    lsr
    lsr
    lsr                     ; r0 = color >> 4
    ibt r8, #1
    AND r8
    ibt r8, #0
    from r8
    to r0
    sub r0
    lob
    stb (r7)
    inc r7
    ; BP5 = bit 5
    from r6
    lob
    lsr
    lsr
    lsr
    lsr
    lsr
    ibt r8, #1
    AND r8
    ibt r8, #0
    from r8
    to r0
    sub r0
    lob
    stb (r7)
    inc r7
    ; BP6-7 = 0 for colors 0-31
    ibt r0, #0
    stb (r7)
    inc r7
    stb (r7)

    ; --- Determine tile color ---
    ; pixel_y_start = tile_row * 8
    ; pixel_y_end = pixel_y_start + 7
    lm r7, (RAM_TROW_Y)    ; r7 = pixel_y_start
    iwt r0, #7
    from r7
    to r8
    add r0                  ; r8 = pixel_y_end (= pixel_y_start + 7)

    ; Is this tile fully ceiling? (pixel_y_end < drawStart)
    from r8
    cmp r4                  ; pixel_y_end - drawStart
    bge _not_pure_ceil
    nop
    iwt r9, #RAM_CEIL_BP
    bra _write_tile
    nop

_not_pure_ceil:
    ; Is this tile fully floor? (pixel_y_start > drawEnd)
    ; Equivalent: drawEnd < pixel_y_start → drawEnd - pixel_y_start < 0
    from r5
    cmp r7                  ; drawEnd - pixel_y_start
    bge _not_pure_floor     ; drawEnd >= pixel_y_start → not floor
    nop
    iwt r9, #RAM_FLOOR_BP
    bra _write_tile
    nop

_not_pure_floor:
    ; Wall or transition — use wall color for simplicity
    iwt r9, #RAM_WALL_BP

_write_tile:
    ; r9 = pointer to BP array (8 bytes: BP0-BP7)
    ; r1 = tile write address
    ; Write 4 BP groups × 8 rows × 2 bytes = 64 bytes

    ; BP group 0 (BP0, BP1)
    move r10, r9            ; r10 = BP array base
    ldb (r10)               ; r0 = BP0
    move r7, r0             ; r7 = BP0 byte
    inc r10
    ldb (r10)               ; r0 = BP1
    move r8, r0             ; r8 = BP1 byte
    ; Write 8 rows
    ibt r11, #8
_wt_g0:
    move r0, r7
    stb (r1)
    inc r1
    move r0, r8
    stb (r1)
    inc r1
    ibt r0, #1
    with r11
    sub r0                  ; r11 -= 1 (manual decrement)
    ibt r0, #0
    from r11
    cmp r0
    bne _wt_g0
    nop

    ; BP group 1 (BP2, BP3)
    iwt r10, #2
    from r9
    to r10
    add r10                 ; r10 = BP_base + 2
    ldb (r10)
    move r7, r0
    inc r10
    ldb (r10)
    move r8, r0
    ibt r11, #8
_wt_g1:
    move r0, r7
    stb (r1)
    inc r1
    move r0, r8
    stb (r1)
    inc r1
    ibt r0, #1
    with r11
    sub r0
    ibt r0, #0
    from r11
    cmp r0
    bne _wt_g1
    nop

    ; BP group 2 (BP4, BP5)
    iwt r10, #4
    from r9
    to r10
    add r10
    ldb (r10)
    move r7, r0
    inc r10
    ldb (r10)
    move r8, r0
    ibt r11, #8
_wt_g2:
    move r0, r7
    stb (r1)
    inc r1
    move r0, r8
    stb (r1)
    inc r1
    ibt r0, #1
    with r11
    sub r0
    ibt r0, #0
    from r11
    cmp r0
    bne _wt_g2
    nop

    ; BP group 3 (BP6, BP7)
    iwt r10, #6
    from r9
    to r10
    add r10
    ldb (r10)
    move r7, r0
    inc r10
    ldb (r10)
    move r8, r0
    ibt r11, #8
_wt_g3:
    move r0, r7
    stb (r1)
    inc r1
    move r0, r8
    stb (r1)
    inc r1
    ibt r0, #1
    with r11
    sub r0
    ibt r0, #0
    from r11
    cmp r0
    bne _wt_g3
    nop

    ; Next column (long branch — _col_loop is >128 bytes away)
    inc r2
    ibt r0, #NUM_COLS
    from r2
    cmp r0
    bge _col_done
    nop
    iwt r15, #(_col_loop - $8000)
    nop
_col_done:

    ; Next tile row (long branch — _trow_loop is >128 bytes away)
    inc r3
    ; Advance pixel_y_start by 8
    lm r0, (RAM_TROW_Y)
    ibt r2, #8
    from r0
    to r0
    add r2
    sm (RAM_TROW_Y), r0
    ; Check if done
    ibt r0, #NUM_TROWS
    from r3
    cmp r0
    bge _trow_done
    nop
    iwt r15, #(_trow_loop - $8000)
    nop
_trow_done:

    stop
    nop


; =====================================================================
; ROM DATA TABLES
; =====================================================================

; --- cameraX_tbl: 27 entries (s16 8.8) ---
cameraX_tbl:
    .dw   -256   ; col 0
    .dw   -237   ; col 1
    .dw   -218   ; col 2
    .dw   -199   ; col 3
    .dw   -180   ; col 4
    .dw   -161   ; col 5
    .dw   -142   ; col 6
    .dw   -123   ; col 7
    .dw   -104   ; col 8
    .dw    -85   ; col 9
    .dw    -66   ; col 10
    .dw    -47   ; col 11
    .dw    -28   ; col 12
    .dw     -9   ; col 13
    .dw      9   ; col 14
    .dw     28   ; col 15
    .dw     47   ; col 16
    .dw     66   ; col 17
    .dw     85   ; col 18
    .dw    104   ; col 19
    .dw    123   ; col 20
    .dw    142   ; col 21
    .dw    161   ; col 22
    .dw    180   ; col 23
    .dw    199   ; col 24
    .dw    218   ; col 25
    .dw    237   ; col 26

; --- recip_tbl: 256 entries (u16) ---
recip_tbl:
    .dw $7FFF  ; 0
    .dw $7FFF  ; 1
    .dw $7FFF  ; 2
    .dw $5555  ; 3
    .dw $4000  ; 4
    .dw $3333  ; 5
    .dw $2AAA  ; 6
    .dw $2492  ; 7
    .dw $2000  ; 8
    .dw $1C71  ; 9
    .dw $1999  ; 10
    .dw $1745  ; 11
    .dw $1555  ; 12
    .dw $13B1  ; 13
    .dw $1249  ; 14
    .dw $1111  ; 15
    .dw $1000  ; 16
    .dw $0F0F  ; 17
    .dw $0E38  ; 18
    .dw $0D79  ; 19
    .dw $0CCC  ; 20
    .dw $0C30  ; 21
    .dw $0BA2  ; 22
    .dw $0B21  ; 23
    .dw $0AAA  ; 24
    .dw $0A3D  ; 25
    .dw $09D8  ; 26
    .dw $097B  ; 27
    .dw $0924  ; 28
    .dw $08D3  ; 29
    .dw $0888  ; 30
    .dw $0842  ; 31
    .dw $0800  ; 32
    .dw $07C1  ; 33
    .dw $0787  ; 34
    .dw $0750  ; 35
    .dw $071C  ; 36
    .dw $06EB  ; 37
    .dw $06BC  ; 38
    .dw $0690  ; 39
    .dw $0666  ; 40
    .dw $063E  ; 41
    .dw $0618  ; 42
    .dw $05F4  ; 43
    .dw $05D1  ; 44
    .dw $05B0  ; 45
    .dw $0590  ; 46
    .dw $0572  ; 47
    .dw $0555  ; 48
    .dw $0539  ; 49
    .dw $051E  ; 50
    .dw $0505  ; 51
    .dw $04EC  ; 52
    .dw $04D4  ; 53
    .dw $04BD  ; 54
    .dw $04A7  ; 55
    .dw $0492  ; 56
    .dw $047D  ; 57
    .dw $046A  ; 58
    .dw $0457  ; 59
    .dw $0444  ; 60
    .dw $0432  ; 61
    .dw $0421  ; 62
    .dw $0410  ; 63
    .dw $0400  ; 64
    .dw $03F0  ; 65
    .dw $03E0  ; 66
    .dw $03D2  ; 67
    .dw $03C3  ; 68
    .dw $03B5  ; 69
    .dw $03A8  ; 70
    .dw $039B  ; 71
    .dw $038E  ; 72
    .dw $0381  ; 73
    .dw $0375  ; 74
    .dw $0369  ; 75
    .dw $035E  ; 76
    .dw $0353  ; 77
    .dw $0348  ; 78
    .dw $033D  ; 79
    .dw $0333  ; 80
    .dw $0329  ; 81
    .dw $031F  ; 82
    .dw $0315  ; 83
    .dw $030C  ; 84
    .dw $0303  ; 85
    .dw $02FA  ; 86
    .dw $02F1  ; 87
    .dw $02E8  ; 88
    .dw $02E0  ; 89
    .dw $02D8  ; 90
    .dw $02D0  ; 91
    .dw $02C8  ; 92
    .dw $02C0  ; 93
    .dw $02B9  ; 94
    .dw $02B1  ; 95
    .dw $02AA  ; 96
    .dw $02A3  ; 97
    .dw $029C  ; 98
    .dw $0295  ; 99
    .dw $028F  ; 100
    .dw $0288  ; 101
    .dw $0282  ; 102
    .dw $027C  ; 103
    .dw $0276  ; 104
    .dw $0270  ; 105
    .dw $026A  ; 106
    .dw $0264  ; 107
    .dw $025E  ; 108
    .dw $0259  ; 109
    .dw $0253  ; 110
    .dw $024E  ; 111
    .dw $0249  ; 112
    .dw $0243  ; 113
    .dw $023E  ; 114
    .dw $0239  ; 115
    .dw $0234  ; 116
    .dw $0230  ; 117
    .dw $022B  ; 118
    .dw $0226  ; 119
    .dw $0222  ; 120
    .dw $021D  ; 121
    .dw $0219  ; 122
    .dw $0214  ; 123
    .dw $0210  ; 124
    .dw $020C  ; 125
    .dw $0208  ; 126
    .dw $0204  ; 127
    .dw $0200  ; 128
    .dw $01FC  ; 129
    .dw $01F8  ; 130
    .dw $01F4  ; 131
    .dw $01F0  ; 132
    .dw $01EC  ; 133
    .dw $01E9  ; 134
    .dw $01E5  ; 135
    .dw $01E1  ; 136
    .dw $01DE  ; 137
    .dw $01DA  ; 138
    .dw $01D7  ; 139
    .dw $01D4  ; 140
    .dw $01D0  ; 141
    .dw $01CD  ; 142
    .dw $01CA  ; 143
    .dw $01C7  ; 144
    .dw $01C3  ; 145
    .dw $01C0  ; 146
    .dw $01BD  ; 147
    .dw $01BA  ; 148
    .dw $01B7  ; 149
    .dw $01B4  ; 150
    .dw $01B2  ; 151
    .dw $01AF  ; 152
    .dw $01AC  ; 153
    .dw $01A9  ; 154
    .dw $01A6  ; 155
    .dw $01A4  ; 156
    .dw $01A1  ; 157
    .dw $019E  ; 158
    .dw $019C  ; 159
    .dw $0199  ; 160
    .dw $0197  ; 161
    .dw $0194  ; 162
    .dw $0192  ; 163
    .dw $018F  ; 164
    .dw $018D  ; 165
    .dw $018A  ; 166
    .dw $0188  ; 167
    .dw $0186  ; 168
    .dw $0183  ; 169
    .dw $0181  ; 170
    .dw $017F  ; 171
    .dw $017D  ; 172
    .dw $017A  ; 173
    .dw $0178  ; 174
    .dw $0176  ; 175
    .dw $0174  ; 176
    .dw $0172  ; 177
    .dw $0170  ; 178
    .dw $016E  ; 179
    .dw $016C  ; 180
    .dw $016A  ; 181
    .dw $0168  ; 182
    .dw $0166  ; 183
    .dw $0164  ; 184
    .dw $0162  ; 185
    .dw $0160  ; 186
    .dw $015E  ; 187
    .dw $015C  ; 188
    .dw $015B  ; 189
    .dw $0159  ; 190
    .dw $0157  ; 191
    .dw $0155  ; 192
    .dw $0153  ; 193
    .dw $0152  ; 194
    .dw $0150  ; 195
    .dw $014E  ; 196
    .dw $014D  ; 197
    .dw $014B  ; 198
    .dw $0149  ; 199
    .dw $0148  ; 200
    .dw $0146  ; 201
    .dw $0144  ; 202
    .dw $0143  ; 203
    .dw $0141  ; 204
    .dw $0140  ; 205
    .dw $013E  ; 206
    .dw $013D  ; 207
    .dw $013B  ; 208
    .dw $013A  ; 209
    .dw $0138  ; 210
    .dw $0137  ; 211
    .dw $0135  ; 212
    .dw $0134  ; 213
    .dw $0132  ; 214
    .dw $0131  ; 215
    .dw $0130  ; 216
    .dw $012E  ; 217
    .dw $012D  ; 218
    .dw $012B  ; 219
    .dw $012A  ; 220
    .dw $0129  ; 221
    .dw $0127  ; 222
    .dw $0126  ; 223
    .dw $0125  ; 224
    .dw $0124  ; 225
    .dw $0122  ; 226
    .dw $0121  ; 227
    .dw $0120  ; 228
    .dw $011E  ; 229
    .dw $011D  ; 230
    .dw $011C  ; 231
    .dw $011B  ; 232
    .dw $011A  ; 233
    .dw $0118  ; 234
    .dw $0117  ; 235
    .dw $0116  ; 236
    .dw $0115  ; 237
    .dw $0114  ; 238
    .dw $0113  ; 239
    .dw $0111  ; 240
    .dw $0110  ; 241
    .dw $010F  ; 242
    .dw $010E  ; 243
    .dw $010D  ; 244
    .dw $010C  ; 245
    .dw $010B  ; 246
    .dw $010A  ; 247
    .dw $0109  ; 248
    .dw $0108  ; 249
    .dw $0107  ; 250
    .dw $0106  ; 251
    .dw $0105  ; 252
    .dw $0104  ; 253
    .dw $0103  ; 254
    .dw $0102  ; 255

; --- height_tbl: 256 entries (u8) ---
height_tbl:
    .db 144    ; 0
    .db 144    ; 1
    .db 144    ; 2
    .db 144    ; 3
    .db 144    ; 4
    .db 144    ; 5
    .db 144    ; 6
    .db 144    ; 7
    .db 144    ; 8
    .db 144    ; 9
    .db 144    ; 10
    .db 144    ; 11
    .db 144    ; 12
    .db 144    ; 13
    .db 144    ; 14
    .db 144    ; 15
    .db 144    ; 16
    .db 135    ; 17
    .db 128    ; 18
    .db 121    ; 19
    .db 115    ; 20
    .db 109    ; 21
    .db 104    ; 22
    .db 100    ; 23
    .db  96    ; 24
    .db  92    ; 25
    .db  88    ; 26
    .db  85    ; 27
    .db  82    ; 28
    .db  79    ; 29
    .db  76    ; 30
    .db  74    ; 31
    .db  72    ; 32
    .db  69    ; 33
    .db  67    ; 34
    .db  65    ; 35
    .db  64    ; 36
    .db  62    ; 37
    .db  60    ; 38
    .db  59    ; 39
    .db  57    ; 40
    .db  56    ; 41
    .db  54    ; 42
    .db  53    ; 43
    .db  52    ; 44
    .db  51    ; 45
    .db  50    ; 46
    .db  49    ; 47
    .db  48    ; 48
    .db  47    ; 49
    .db  46    ; 50
    .db  45    ; 51
    .db  44    ; 52
    .db  43    ; 53
    .db  42    ; 54
    .db  41    ; 55
    .db  41    ; 56
    .db  40    ; 57
    .db  39    ; 58
    .db  39    ; 59
    .db  38    ; 60
    .db  37    ; 61
    .db  37    ; 62
    .db  36    ; 63
    .db  36    ; 64
    .db  35    ; 65
    .db  34    ; 66
    .db  34    ; 67
    .db  33    ; 68
    .db  33    ; 69
    .db  32    ; 70
    .db  32    ; 71
    .db  32    ; 72
    .db  31    ; 73
    .db  31    ; 74
    .db  30    ; 75
    .db  30    ; 76
    .db  29    ; 77
    .db  29    ; 78
    .db  29    ; 79
    .db  28    ; 80
    .db  28    ; 81
    .db  28    ; 82
    .db  27    ; 83
    .db  27    ; 84
    .db  27    ; 85
    .db  26    ; 86
    .db  26    ; 87
    .db  26    ; 88
    .db  25    ; 89
    .db  25    ; 90
    .db  25    ; 91
    .db  25    ; 92
    .db  24    ; 93
    .db  24    ; 94
    .db  24    ; 95
    .db  24    ; 96
    .db  23    ; 97
    .db  23    ; 98
    .db  23    ; 99
    .db  23    ; 100
    .db  22    ; 101
    .db  22    ; 102
    .db  22    ; 103
    .db  22    ; 104
    .db  21    ; 105
    .db  21    ; 106
    .db  21    ; 107
    .db  21    ; 108
    .db  21    ; 109
    .db  20    ; 110
    .db  20    ; 111
    .db  20    ; 112
    .db  20    ; 113
    .db  20    ; 114
    .db  20    ; 115
    .db  19    ; 116
    .db  19    ; 117
    .db  19    ; 118
    .db  19    ; 119
    .db  19    ; 120
    .db  19    ; 121
    .db  18    ; 122
    .db  18    ; 123
    .db  18    ; 124
    .db  18    ; 125
    .db  18    ; 126
    .db  18    ; 127
    .db  18    ; 128
    .db  17    ; 129
    .db  17    ; 130
    .db  17    ; 131
    .db  17    ; 132
    .db  17    ; 133
    .db  17    ; 134
    .db  17    ; 135
    .db  16    ; 136
    .db  16    ; 137
    .db  16    ; 138
    .db  16    ; 139
    .db  16    ; 140
    .db  16    ; 141
    .db  16    ; 142
    .db  16    ; 143
    .db  16    ; 144
    .db  15    ; 145
    .db  15    ; 146
    .db  15    ; 147
    .db  15    ; 148
    .db  15    ; 149
    .db  15    ; 150
    .db  15    ; 151
    .db  15    ; 152
    .db  15    ; 153
    .db  14    ; 154
    .db  14    ; 155
    .db  14    ; 156
    .db  14    ; 157
    .db  14    ; 158
    .db  14    ; 159
    .db  14    ; 160
    .db  14    ; 161
    .db  14    ; 162
    .db  14    ; 163
    .db  14    ; 164
    .db  13    ; 165
    .db  13    ; 166
    .db  13    ; 167
    .db  13    ; 168
    .db  13    ; 169
    .db  13    ; 170
    .db  13    ; 171
    .db  13    ; 172
    .db  13    ; 173
    .db  13    ; 174
    .db  13    ; 175
    .db  13    ; 176
    .db  13    ; 177
    .db  12    ; 178
    .db  12    ; 179
    .db  12    ; 180
    .db  12    ; 181
    .db  12    ; 182
    .db  12    ; 183
    .db  12    ; 184
    .db  12    ; 185
    .db  12    ; 186
    .db  12    ; 187
    .db  12    ; 188
    .db  12    ; 189
    .db  12    ; 190
    .db  12    ; 191
    .db  12    ; 192
    .db  11    ; 193
    .db  11    ; 194
    .db  11    ; 195
    .db  11    ; 196
    .db  11    ; 197
    .db  11    ; 198
    .db  11    ; 199
    .db  11    ; 200
    .db  11    ; 201
    .db  11    ; 202
    .db  11    ; 203
    .db  11    ; 204
    .db  11    ; 205
    .db  11    ; 206
    .db  11    ; 207
    .db  11    ; 208
    .db  11    ; 209
    .db  10    ; 210
    .db  10    ; 211
    .db  10    ; 212
    .db  10    ; 213
    .db  10    ; 214
    .db  10    ; 215
    .db  10    ; 216
    .db  10    ; 217
    .db  10    ; 218
    .db  10    ; 219
    .db  10    ; 220
    .db  10    ; 221
    .db  10    ; 222
    .db  10    ; 223
    .db  10    ; 224
    .db  10    ; 225
    .db  10    ; 226
    .db  10    ; 227
    .db  10    ; 228
    .db  10    ; 229
    .db  10    ; 230
    .db   9    ; 231
    .db   9    ; 232
    .db   9    ; 233
    .db   9    ; 234
    .db   9    ; 235
    .db   9    ; 236
    .db   9    ; 237
    .db   9    ; 238
    .db   9    ; 239
    .db   9    ; 240
    .db   9    ; 241
    .db   9    ; 242
    .db   9    ; 243
    .db   9    ; 244
    .db   9    ; 245
    .db   9    ; 246
    .db   9    ; 247
    .db   9    ; 248
    .db   9    ; 249
    .db   9    ; 250
    .db   9    ; 251
    .db   9    ; 252
    .db   9    ; 253
    .db   9    ; 254
    .db   9    ; 255

; --- map_data: 10x10 map ---
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
