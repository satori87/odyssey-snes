; ============================================
; SuperFX Pixel Plotter (Doom SNES style)
; NO math on GSU -- reads pre-computed column data from $70:0000,
; writes pixel data directly into tile-formatted framebuffer at $70:0400.
;
; Column data format (120 bytes at $70:0000):
;   3 bytes per column x 40 columns
;   byte 0: drawStart (Y coord, 0-79)
;   byte 1: drawEnd   (Y coord, 0-79)
;   byte 2: wallColor (palette index)
;
; Tile framebuffer at $70:0400:
;   200 tiles (20x10), 64 bytes each = 12800 bytes
;   Pixel within tile: row*8 + col (Mode 7, 1 byte/pixel)
;
; Screen: 160x80 = 20x10 tiles, column C -> screenX = C*4
;
; Notes on wla-superfx assembler:
;   - ldb/stb/ldw/stw only work with R0-R11 (not R12-R15)
;   - "AND" must be uppercase (lowercase "and" is a reserved keyword)
;   - add #N and sub #N work for immediates 0-15
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

.define SCREEN_H     80
.define NUM_COLS     40
.define CEIL_COLOR   16
.define FLOOR_COLOR  17
.define COL_DATA     $0000
.define FRAMEBUF     $0400

; Scratch RAM past framebuffer ($0400 + 12800 = $3640)
.define VAR_TILEX      $3640
.define VAR_COLNUM     $3642
.define VAR_SCREENX    $3644

; -------------------------------------------------------
; Register plan:
;   R0  = scratch (default accumulator)
;   R1  = py (pixel row in tile, inner loop) / temp for ldw/stw addr
;   R2  = tileY (0..9)
;   R3  = write pointer for stb (R0-R11 range)
;   R4  = tileBase address
;   R5  = drawStart
;   R6  = drawEnd
;   R7  = wallColor
;   R8  = Y (0..79)
;   R9  = current color to write
;   R10 = px (pixel X within tile: 0 or 4)
;   R11 = general temp
; -------------------------------------------------------

gsu_fill_screen:
    iwt r0, #$70
    ramb
    romb

    ; Initialize column counter and screenX
    iwt r0, #0
    iwt r1, #VAR_COLNUM
    stw (r1)
    iwt r1, #VAR_SCREENX
    stw (r1)

_col_loop:
    ; --- Read column index ---
    iwt r1, #VAR_COLNUM
    ldw (r1)                ; r0 = col
    move r11, r0            ; r11 = col

    ; --- Pointer: col*3 (COL_DATA is $0000) ---
    from r11
    to r0
    add r11                 ; r0 = col*2
    from r0
    to r3
    add r11                 ; r3 = col*3

    ; Read drawStart, drawEnd, wallColor
    ldb (r3)
    move r5, r0             ; r5 = drawStart
    inc r3
    ldb (r3)
    move r6, r0             ; r6 = drawEnd
    inc r3
    ldb (r3)
    move r7, r0             ; r7 = wallColor

    ; --- Get screenX ---
    iwt r1, #VAR_SCREENX
    ldw (r1)                ; r0 = screenX
    move r11, r0

    ; --- px = screenX & 7 ---
    iwt r10, #7
    from r11
    AND r10                 ; r0 = screenX & 7
    move r10, r0            ; r10 = px (0 or 4)

    ; --- tileX = screenX >> 3, save to RAM ---
    from r11
    to r0
    lsr
    lsr
    lsr                     ; r0 = screenX / 8 = tileX
    iwt r1, #VAR_TILEX
    stw (r1)

    ; --- Draw vertical strip Y=0..79 ---
    iwt r8, #0              ; Y = 0
    iwt r2, #0              ; tileY = 0

_tilerow_loop:
    ; tileBase = FRAMEBUF + (tileY*20 + tileX) * 64
    ; Step 1: tileY*20 = tileY*16 + tileY*4
    from r2
    to r0
    add r2                  ; r0 = tileY*2
    add r0                  ; r0 = tileY*4
    move r11, r0            ; r11 = tileY*4
    add r0                  ; r0 = tileY*8
    add r0                  ; r0 = tileY*16
    add r11                 ; r0 = tileY*20
    move r11, r0            ; r11 = tileY*20

    ; Load tileX and add
    iwt r1, #VAR_TILEX
    ldw (r1)                ; r0 = tileX
    add r11                 ; r0 = tileX + tileY*20 = tileIndex

    ; Step 2: *64 (6 doublings)
    from r0
    to r4
    add r0                  ; r4 = tileIndex * 2
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

    ; + FRAMEBUF offset
    iwt r0, #FRAMEBUF
    from r4
    to r4
    add r0                  ; r4 = tileBase

    ; --- 8 pixel rows ---
    iwt r1, #0              ; r1 = py

_pixrow_loop:
    ; Determine color for Y
    ; Y < drawStart -> ceiling
    from r8
    cmp r5                  ; Y - drawStart
    bge _pw_chk_wall
    nop
    iwt r9, #CEIL_COLOR
    iwt r15, #_pw_write - $8000
    nop

_pw_chk_wall:
    ; drawEnd >= Y -> wall
    from r6
    cmp r8                  ; drawEnd - Y
    blt _pw_floor           ; if drawEnd < Y -> floor
    nop
    move r9, r7
    iwt r15, #_pw_write - $8000
    nop

_pw_floor:
    iwt r9, #FLOOR_COLOR

_pw_write:
    ; address = tileBase + py*8 + px
    from r1
    to r0
    add r1                  ; py*2
    add r0                  ; py*4
    add r0                  ; py*8
    add r10                 ; + px
    from r4
    to r3
    add r0                  ; r3 = write address

    ; Write 4 pixels
    move r0, r9
    stb (r3)
    inc r3
    stb (r3)
    inc r3
    stb (r3)
    inc r3
    stb (r3)

    ; Next row
    inc r1                  ; py++
    inc r8                  ; Y++
    ibt r0, #8
    from r1
    cmp r0
    blt _pixrow_loop
    nop

    ; Next tile row
    inc r2
    ibt r0, #10
    from r2
    cmp r0
    blt _tilerow_loop
    nop

    ; --- Next column ---
    iwt r1, #VAR_COLNUM
    ldw (r1)
    add #1
    stw (r1)
    move r11, r0            ; r11 = new col

    iwt r1, #VAR_SCREENX
    ldw (r1)
    add #4
    stw (r1)

    ; Check done: if col < NUM_COLS, loop
    ; Branch range is only +/-127 bytes, so use inverted branch + long jump
    iwt r0, #NUM_COLS
    from r11
    cmp r0
    bge _all_done
    nop
    iwt r15, #_col_loop - $8000
    nop

_all_done:
    stop
    nop

.ENDS
