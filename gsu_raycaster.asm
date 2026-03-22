; GSU Raycaster — manual bitplane tile rendering (no plot instruction)
;
; The plot instruction's tile layout doesn't match BG sequential tiles.
; Instead, we write bitplane bytes directly with stb.
;
; 8bpp SNES tile format (64 bytes per tile):
;   Bytes  0-15: BP0,BP1 interleaved (8 rows × 2 bytes)
;   Bytes 16-31: BP2,BP3 interleaved
;   Bytes 32-47: BP4,BP5 interleaved
;   Bytes 48-63: BP6,BP7 interleaved
;
; For a full row of 8 identical pixels with color C:
;   BP_N byte = $FF if bit N of C is set, else $00

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

.define NUM_COLS     20
.define NUM_TROWS    12
.define NUM_TILES    240
.define FB_BASE      $0400

; RAM scratch
.define RAM_DRAWSTART $0040
.define RAM_DRAWEND   $0060
.define RAM_WALLCOLOR $0080

; Precomputed BP bytes for 3 colors (8 bytes each)
.define RAM_CEIL_BP   $00C0
.define RAM_WALL_BP   $00C8
.define RAM_FLOOR_BP  $00D0

.BANK 0
.SECTION "GSUCode" SUPERFREE

gsu_fill_screen:
    iwt r0, #$70
    ramb                    ; RAM bank = $70

    ; ===== TEST: Write hardcoded column data =====
    ibt r8, #0
_test_fill:
    iwt r0, #RAM_DRAWSTART
    to r3
    add r8
    ibt r0, #32
    stb (r3)
    iwt r0, #RAM_DRAWEND
    to r3
    add r8
    ibt r0, #64
    stb (r3)
    iwt r0, #RAM_WALLCOLOR
    to r3
    add r8
    ibt r0, #1
    stb (r3)
    inc r8
    ibt r0, #NUM_COLS
    from r8
    cmp r0
    blt _test_fill
    nop

    ; ===== Precompute bitplane bytes for ceiling(16), wall(1), floor(17) =====
    ; Color 16 = 00010000: BP4=$FF, rest $00
    iwt r1, #RAM_CEIL_BP
    ibt r0, #0
    stb (r1)                ; BP0=$00
    inc r1
    stb (r1)                ; BP1=$00
    inc r1
    stb (r1)                ; BP2=$00
    inc r1
    stb (r1)                ; BP3=$00
    inc r1
    ibt r0, #$FF
    lob
    stb (r1)                ; BP4=$FF
    inc r1
    ibt r0, #0
    stb (r1)                ; BP5=$00
    inc r1
    stb (r1)                ; BP6=$00
    inc r1
    stb (r1)                ; BP7=$00

    ; Color 1 = 00000001: BP0=$FF, rest $00
    iwt r1, #RAM_WALL_BP
    ibt r0, #$FF
    lob
    stb (r1)                ; BP0=$FF
    inc r1
    ibt r0, #0
    stb (r1)                ; BP1=$00
    inc r1
    stb (r1)                ; BP2=$00
    inc r1
    stb (r1)                ; BP3=$00
    inc r1
    stb (r1)                ; BP4=$00
    inc r1
    stb (r1)                ; BP5=$00
    inc r1
    stb (r1)                ; BP6=$00
    inc r1
    stb (r1)                ; BP7=$00

    ; Color 17 = 00010001: BP0=$FF, BP4=$FF, rest $00
    iwt r1, #RAM_FLOOR_BP
    ibt r0, #$FF
    lob
    stb (r1)                ; BP0=$FF
    inc r1
    ibt r0, #0
    stb (r1)                ; BP1=$00
    inc r1
    stb (r1)                ; BP2=$00
    inc r1
    stb (r1)                ; BP3=$00
    inc r1
    ibt r0, #$FF
    lob
    stb (r1)                ; BP4=$FF
    inc r1
    ibt r0, #0
    stb (r1)                ; BP5=$00
    inc r1
    stb (r1)                ; BP6=$00
    inc r1
    stb (r1)                ; BP7=$00

    ; ===== PHASE 2: Render tiles column by column =====
    ; For each column, for each tile row, for each pixel row:
    ;   determine color, write bitplane bytes

    ibt r2, #0              ; r2 = column counter (0-19)

_col_loop:
    ; Load column data
    iwt r0, #RAM_DRAWSTART
    to r3
    add r2
    ldb (r3)
    move r4, r0             ; r4 = drawStart

    iwt r0, #RAM_DRAWEND
    to r3
    add r2
    ldb (r3)
    move r5, r0             ; r5 = drawEnd

    ; wallColor not needed for precomputed BP lookup — always color 1 in test

    ibt r3, #0              ; r3 = tile_row counter (0-11)

_trow_loop:
    ; Compute tile_base = FB_BASE + (tile_row * 20 + col) * 64
    ; tile_row * 20 = tile_row * 16 + tile_row * 4
    from r3
    to r6
    add r3                  ; r6 = tile_row * 2
    from r6
    to r6
    add r6                  ; r6 = tile_row * 4
    from r6
    to r7
    add r6                  ; r7 = tile_row * 8
    from r7
    to r7
    add r7                  ; r7 = tile_row * 16
    with r7
    add r6                  ; r7 = tile_row * 16 + tile_row * 4 = tile_row * 20
    with r7
    add r2                  ; r7 = tile_row * 20 + col = tile_index

    ; tile_base = FB_BASE + tile_index * 64
    ; tile_index * 64 = tile_index << 6
    from r7
    to r7
    add r7                  ; r7 = tile_index * 2
    from r7
    to r7
    add r7                  ; r7 = tile_index * 4
    from r7
    to r7
    add r7                  ; r7 = tile_index * 8
    from r7
    to r7
    add r7                  ; r7 = tile_index * 16
    from r7
    to r7
    add r7                  ; r7 = tile_index * 32
    from r7
    to r7
    add r7                  ; r7 = tile_index * 64
    iwt r0, #FB_BASE
    with r7
    add r0                  ; r7 = FB_BASE + tile_index * 64 = tile_base

    ; Now write 64 bytes for this tile
    ; For each of 4 bitplane pair groups (offset 0, 16, 32, 48):
    ;   For each of 8 rows:
    ;     pixel_y = tile_row * 8 + row
    ;     Determine color → get BP byte from precomputed table
    ;     Write bp_even, bp_odd

    move r1, r7             ; r1 = write address (tile_base)
    ibt r8, #0              ; r8 = bitplane pair index (0-3)

_bp_group_loop:
    ibt r9, #0              ; r9 = pixel row within tile (0-7)

_prow_loop:
    ; pixel_y = tile_row * 8 + r9
    from r3
    to r10
    add r3                  ; r10 = tile_row * 2
    from r10
    to r10
    add r10                 ; r10 = tile_row * 4
    from r10
    to r10
    add r10                 ; r10 = tile_row * 8
    with r10
    add r9                  ; r10 = pixel_y

    ; Determine color: pixel_y < drawStart → ceiling, <= drawEnd → wall, else floor
    ; r11 = pointer to BP array for this color
    from r10
    cmp r4                  ; pixel_y - drawStart
    bge _not_ceil
    nop
    iwt r11, #RAM_CEIL_BP
    bra _got_color
    nop
_not_ceil:
    from r5
    cmp r10                 ; drawEnd - pixel_y
    bge _is_wall
    nop
    iwt r11, #RAM_FLOOR_BP
    bra _got_color
    nop
_is_wall:
    iwt r11, #RAM_WALL_BP
_got_color:
    ; r11 = BP array base. Read BP[r8*2] and BP[r8*2+1]
    from r8
    to r6
    add r8                  ; r6 = bitplane_pair * 2
    with r6
    add r11                 ; r6 = BP_base + pair * 2

    ; Read bp_even
    ldb (r6)                ; r0 = BP[pair*2]
    stb (r1)                ; write to tile
    inc r1
    inc r6

    ; Read bp_odd
    ldb (r6)                ; r0 = BP[pair*2 + 1]
    stb (r1)                ; write to tile
    inc r1

    ; Next pixel row
    inc r9
    ibt r0, #8
    from r9
    cmp r0
    blt _prow_loop
    nop

    ; Next bitplane pair group
    inc r8
    ibt r0, #4
    from r8
    cmp r0
    blt _bp_group_loop
    nop

    ; Next tile row
    inc r3
    ibt r0, #NUM_TROWS
    from r3
    cmp r0
    blt _trow_loop
    nop

    ; Next column
    inc r2
    ibt r0, #NUM_COLS
    from r2
    cmp r0
    blt _col_loop
    nop

    stop
    nop

.ENDS
