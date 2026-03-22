; gsu_raycaster.asm -- BSP renderer (Doom-style)
;
; Phase 1: BSP traversal + vertex rotation + screen projection + column fill
; Phase 2: Row-by-row stb tile rendering (proven working, from previous code)
;
; Follows Doom SNES patterns from rlbsp.a, rlsegs2.a, rlsegs3.a

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

; =====================================================================
; CONSTANTS
; =====================================================================
.define SCREEN_H     144
.define HALF_H       72
.define NUM_COLS     27
.define NUM_TROWS    18
.define HALF_W       108      ; half viewport width in pixels (216/2)
.define FB_BASE      $0400
.define TILE_SIZE    64
.define SCREEN_PLANE 4        ; distance from eye to screen (Doom: RLScreenPlane)
.define WALL_CONST   576      ; SCREEN_H * SCREEN_PLANE = 144 * 4 = 576

; Seg structure offsets (11 bytes, matches Doom's rlgSize)
.define SEG_V1       0        ; vertex 1 byte offset (2)
.define SEG_V2       2        ; vertex 2 byte offset (2)
.define SEG_FLAGS    4        ; flags (1)
.define SEG_COLOR    5        ; wall color (1)
.define SEG_SIZE     11       ; total size

; =====================================================================
; RAM MAP ($70:0000)
; =====================================================================
; Player state (written by 65816)
.define RAM_VIEWX     $0000   ; player world X (s16)
.define RAM_VIEWY     $0002   ; player world Y (s16)
.define RAM_ANGLE     $0004   ; player angle byte (0-255)

; Column buffer (output for Phase 2)
.define RAM_DRAWSTART $0040   ; drawStart[27] (1 byte each)
.define RAM_DRAWEND   $0060   ; drawEnd[27] (1 byte each)
.define RAM_WALLCOLOR $0080   ; wallColor[27] (1 byte each)
.define RAM_COLFILLED $00A0   ; columnFilled[27] (1 byte: 0=empty, 1=filled)

; Rotated vertex cache (8 verts x 4 bytes = 32 bytes)
; Each: rotY(s16), rotX(s16). rotY=$8000 = not rotated yet
.define RAM_ROTVERTS  $00C0

; Trig values
.define RAM_SIN       $00E8
.define RAM_COS       $00EA

; Scratch
.define RAM_SCRATCH   $00EC
.define RAM_SCRATCH2  $00EE

; Bitplane precompute for Phase 2
.define RAM_CEIL_BP   $00F0
.define RAM_WALL_BP   $00F8
.define RAM_FLOOR_BP  $0100

; BSP stack
.define RAM_BSPSTACK  $0110   ; 64 bytes (16 levels max)

; Phase 2 scratch
.define RAM_TROW_Y    $0150

; =====================================================================
; CODE
; =====================================================================
.BANK 0
.SECTION "GSUCode" SUPERFREE

gsu_fill_screen:
    ; === SETUP ===
    iwt r0, #$70
    ramb                        ; RAM bank = $70
    ibt r0, #0
    romb                        ; ROM bank 0 (GSU code + data)

    ; === Read player state ===
    lm r0, (RAM_VIEWX)
    sm (RAM_SCRATCH), r0        ; save ViewX
    lm r0, (RAM_VIEWY)
    sm (RAM_SCRATCH2), r0       ; save ViewY

    ; === Compute sin/cos from angle ===
    lm r0, (RAM_ANGLE)
    lob                         ; ensure byte (0-255)
    add r0                      ; r0 = angle * 2 (word index)
    iwt r1, #(sin_tbl - $8000)
    from r0
    to r14
    add r1                      ; r14 -> sin_tbl[angle]
    getb
    inc r14
    to r2
    getbh                       ; r2 = sin(angle) in 1.15 format
    sm (RAM_SIN), r2

    lm r0, (RAM_ANGLE)
    lob
    add r0                      ; r0 = angle * 2
    iwt r1, #(cos_tbl - $8000)
    from r0
    to r14
    add r1                      ; r14 -> cos_tbl[angle]
    getb
    inc r14
    to r2
    getbh                       ; r2 = cos(angle)
    sm (RAM_COS), r2

    ; === Clear column buffer ===
    ; drawStart = 0, drawEnd = SCREEN_H-1, wallColor = 0, columnFilled = 0
    iwt r1, #RAM_DRAWSTART
    iwt r2, #RAM_DRAWEND
    iwt r3, #RAM_WALLCOLOR
    iwt r4, #RAM_COLFILLED
    ibt r5, #NUM_COLS
_clear_loop:
    ibt r0, #0
    stb (r1)                    ; drawStart = 0
    inc r1
    ibt r0, #(SCREEN_H - 1)
    stb (r2)                    ; drawEnd = 143
    inc r2
    ibt r0, #0
    stb (r3)                    ; wallColor = 0
    inc r3
    ibt r0, #0
    stb (r4)                    ; columnFilled = 0
    inc r4
    with r5
    sub #1
    bne _clear_loop
    nop

    ; === Initialize rotated vertex cache ===
    ; Mark all 8 vertices as "not rotated" ($8000 flag)
    iwt r1, #RAM_ROTVERTS
    ibt r2, #8                  ; 8 vertices
    iwt r0, #$8000
_init_vert_loop:
    stw (r1)                    ; rotY = $8000 (not rotated)
    inc r1
    inc r1
    ibt r0, #0
    stw (r1)                    ; rotX = 0
    inc r1
    inc r1
    iwt r0, #$8000
    with r2
    sub #1
    bne _init_vert_loop
    nop

    ; Initialize subsector visit counter
    ibt r0, #0
    sm ($0024), r0

    ; =================================================================
    ; PHASE 1: BSP TRAVERSAL (follows rlbsp.a)
    ; =================================================================
    ; Register allocation during BSP walk:
    ; r8 = current node/area pointer (byte offset or $8000|area_offset)
    ; r9 = BSP stack pointer
    ; r14 = ROM data pointer

    ; Initialize BSP stack
    iwt r9, #RAM_BSPSTACK
    ; Push final return address
    iwt r0, #(_bsp_done - $8000)
    stw (r9)
    inc r9
    inc r9

    ; Start from root node
    iwt r8, #ROOT_NODE_OFFSET

    ; --- BSP Node Processing ---
_bsp_node:
    ; Check if this is a subsector (bit 15 set = negative)
    moves r0, r8
    bpl _bsp_is_node            ; positive = node, continue below
    nop
    ; Negative = subsector, long branch
    iwt r15, #(_bsp_subsector - $8000)
    nop
_bsp_is_node:

    ; === It's a BSP node — read partition line ===
    iwt r0, #(bsp_nodes - $8000)
    from r8
    to r14
    add r0                      ; r14 -> node data

    ; Read partition: LineY(2), DeltaX(2), LineX(2), DeltaY(2)
    getb
    inc r14
    to r1
    getbh                       ; r1 = LineY
    inc r14
    getb
    inc r14
    to r2
    getbh                       ; r2 = DeltaX
    inc r14
    getb
    inc r14
    to r3
    getbh                       ; r3 = LineX
    inc r14
    getb
    inc r14
    to r4
    getbh                       ; r4 = DeltaY
    inc r14

    ; Save r14 (now points to LeftBBox) and DeltaY
    sm ($0006), r14             ; save ROM ptr at LeftBBox
    sm ($0008), r4              ; save DeltaY

    ; === Cross product: DeltaX*(ViewY-LineY) - DeltaY*(ViewX-LineX) ===
    ; Part 1: DeltaX * (ViewY - LineY)
    lm r0, (RAM_VIEWY)
    with r0
    sub r1                      ; r0 = ViewY - LineY
    move r6, r2                 ; r6 = DeltaX
    lmult                       ; R0:R4 = DeltaX * (ViewY - LineY)
    move r5, r0                 ; r5 = high word
    move r7, r4                 ; r7 = low word

    ; Part 2: DeltaY * (ViewX - LineX)
    lm r6, ($0008)              ; r6 = DeltaY
    lm r0, (RAM_VIEWX)
    with r0
    sub r3                      ; r0 = ViewX - LineX
    lmult                       ; R0:R4 = DeltaY * (ViewX - LineX)

    ; Cross = Part1 - Part2
    with r7
    sub r4
    with r5
    sbc r0

    ; r5 = sign of cross product
    ; >= 0 (LEFT): visit left first, then right (front-to-back)
    ; < 0 (RIGHT): visit right first, then left
    moves r0, r5
    bmi _bsp_right_side
    nop

    ; === LEFT SIDE: visit left child first (near), then right (far) ===
_bsp_left_side:
    lm r14, ($0006)             ; restore ROM ptr at LeftBBox
    ; Skip LeftBBox (8 bytes) to reach LeftChild
    with r14
    add #8                      ; r14 at LeftChild

    ; Save pointer to RightChild for later
    ; RightChild = LeftChild + 2 + 8 = LeftChild + 10
    move r1, r14
    with r1
    add #10                     ; r1 = ptr to RightChild
    from r1
    stw (r9)                    ; push RightChild ptr
    inc r9
    inc r9

    ; Push return address
    iwt r0, #(_after_left_near - $8000)
    stw (r9)
    inc r9
    inc r9

    ; Read left child and recurse
    getb
    inc r14
    to r8
    getbh                       ; r8 = LeftChild
    iwt r15, #(_bsp_node - $8000)
    nop

_after_left_near:
    ; Pop RightChild pointer
    dec r9
    dec r9
    to r14
    ldw (r9)                    ; r14 -> RightChild in ROM

    ; Read right child and recurse (parent's return addr still on stack)
    getb
    inc r14
    to r8
    getbh                       ; r8 = RightChild
    iwt r15, #(_bsp_node - $8000)
    nop

    ; === RIGHT SIDE: visit right child first (near), then left (far) ===
_bsp_right_side:
    lm r14, ($0006)             ; restore ROM ptr at LeftBBox
    ; LeftChild is at +8
    with r14
    add #8                      ; r14 at LeftChild

    ; Save LeftChild pointer for later
    from r14
    stw (r9)                    ; push LeftChild ptr
    inc r9
    inc r9

    ; Skip LeftChild(2) + RightBBox(8) = 10 to reach RightChild
    with r14
    add #10                     ; r14 at RightChild

    ; Push return address
    iwt r0, #(_after_right_near - $8000)
    stw (r9)
    inc r9
    inc r9

    ; Read right child and recurse
    getb
    inc r14
    to r8
    getbh                       ; r8 = RightChild
    iwt r15, #(_bsp_node - $8000)
    nop

_after_right_near:
    ; Pop LeftChild pointer
    dec r9
    dec r9
    to r14
    ldw (r9)                    ; r14 -> LeftChild in ROM

    ; Read left child and recurse (parent's return addr still on stack)
    getb
    inc r14
    to r8
    getbh                       ; r8 = LeftChild
    iwt r15, #(_bsp_node - $8000)
    nop

    ; === SUBSECTOR (AREA) PROCESSING ===
_bsp_subsector:
    ; r8 = $8000 | area_byte_offset
    ; Strip $8000 flag
    iwt r0, #$8000
    from r8
    add r0                      ; r0 = area byte offset

    ; Read area data from ROM
    iwt r1, #(bsp_areas - $8000)
    to r14
    add r1                      ; r14 -> area data

    to r11
    getb                        ; r11 = numSegs
    inc r14
    getb
    inc r14
    to r10
    getbh                       ; r10 = segOffset
    inc r14

    ; Compute absolute ROM address of first seg
    iwt r0, #(bsp_segs - $8000)
    with r10
    add r0                      ; r10 = ROM addr of first seg

    ; Save BSP stack pointer before segment processing
    sm ($000E), r9

    ; Process each segment in this subsector
_seg_loop:
    moves r0, r11
    bne _seg_has_more
    nop
    iwt r15, #(_seg_done - $8000)
    nop
_seg_has_more:

    ; Save loop state
    sm ($000A), r11             ; remaining seg count
    sm ($000C), r10             ; current seg ROM addr

    ; === Read segment data ===
    move r14, r10
    ; V1 offset (2 bytes)
    getb
    inc r14
    to r1
    getbh                       ; r1 = v1 byte offset
    inc r14
    ; V2 offset (2 bytes)
    getb
    inc r14
    to r2
    getbh                       ; r2 = v2 byte offset
    inc r14
    ; Skip flags (1 byte)
    inc r14
    ; Wall color (1 byte)
    to r3
    getb                        ; r3 = wallColor
    sm ($0010), r3              ; save wallColor

    ; Save vertex offsets
    sm ($0012), r1              ; v1 offset
    sm ($0014), r2              ; v2 offset

    ; === SEGMENT PROCESSING: rotate, project, fill columns ===
    ; Uses SAFE addressing: move+with+add (never stacked from/to)

    ; --- Read + rotate vertex 1 ---
    lm r1, ($0012)              ; v1 byte offset
    iwt r0, #(bsp_vertices - $8000)
    move r14, r1
    with r14
    add r0                      ; r14 -> vertex data (SAFE: move+with+add)
    getb
    inc r14
    to r3
    getbh                       ; r3 = v1.x
    inc r14
    getb
    inc r14
    to r4
    getbh                       ; r4 = v1.y

    ; Translate to player-relative coords
    lm r0, (RAM_VIEWX)
    with r3
    sub r0                      ; r3 = dx1
    lm r0, (RAM_VIEWY)
    with r4
    sub r0                      ; r4 = dy1

    ; Rotate vertex 1: rotY = cos*dx + sin*dy, rotX = sin*dx - cos*dy
    lm r6, (RAM_COS)
    move r0, r3
    fmult
    rol
    move r5, r0                 ; r5 = cos*dx1

    lm r6, (RAM_SIN)
    move r0, r4
    fmult
    rol
    with r5
    add r0                      ; r5 = rotY1 = cos*dx + sin*dy
    with r5
    sub #SCREEN_PLANE           ; r5 -= 4

    lm r6, (RAM_SIN)
    move r0, r3
    fmult
    rol
    move r7, r0                 ; r7 = sin*dx1

    lm r6, (RAM_COS)
    move r0, r4
    fmult
    rol
    from r7
    sub r0                      ; r0 = rotX1 = sin*dx - cos*dy

    sm ($0016), r5              ; save rotY1
    sm ($0018), r0              ; save rotX1

    ; --- Read vertex 2 from ROM ---
    lm r2, ($0014)
    iwt r0, #(bsp_vertices - $8000)
    move r14, r2
    with r14
    add r0                      ; SAFE: move+with+add
    getb
    inc r14
    to r3
    getbh                       ; r3 = v2.x
    inc r14
    getb
    inc r14
    to r4
    getbh                       ; r4 = v2.y

    lm r0, (RAM_VIEWX)
    with r3
    sub r0                      ; r3 = dx2
    lm r0, (RAM_VIEWY)
    with r4
    sub r0                      ; r4 = dy2

    ; Rotate vertex 2
    lm r6, (RAM_COS)
    move r0, r3
    fmult
    rol
    move r5, r0

    lm r6, (RAM_SIN)
    move r0, r4
    fmult
    rol
    with r5
    add r0
    with r5
    sub #SCREEN_PLANE

    lm r6, (RAM_SIN)
    move r0, r3
    fmult
    rol
    move r7, r0

    lm r6, (RAM_COS)
    move r0, r4
    fmult
    rol
    from r7
    sub r0                      ; r0 = rotX2

    sm ($001A), r5              ; save rotY2
    sm ($001C), r0              ; save rotX2

    ; === Skip if both behind camera ===
    lm r1, ($0016)              ; rotY1
    lm r2, ($001A)              ; rotY2
    moves r0, r1
    bpl _v_front
    nop
    moves r0, r2
    bpl _v_front
    nop
    iwt r15, #(_seg_next - $8000)
    nop
_v_front:

    ; === Clamp depths to >= 1 (prevent divide-by-zero) ===
    lm r1, ($0016)              ; rotY1
    lm r2, ($0018)              ; rotX1
    lm r3, ($001A)              ; rotY2
    lm r4, ($001C)              ; rotX2
    ; Clamp rotY1: must be > 0 (not just >= 0!)
    moves r0, r1
    bmi _y1_clamp
    nop
    bne _y1_ok                  ; positive non-zero → OK
    nop
_y1_clamp:
    ibt r1, #4                  ; clamp to 4 (screen plane dist)
    move r2, r4                 ; use rotX2 as approximation
_y1_ok:
    ; Clamp rotY2: must be > 0
    moves r0, r3
    bmi _y2_clamp
    nop
    bne _y2_ok
    nop
_y2_clamp:
    ibt r3, #4
    move r4, r2
_y2_ok:

    ; === Project: col = (rotX * 13 / rotY) + 13 ===
    ; Uses 16-iteration binary divide (guaranteed termination)

    ; --- Project V1 ---
    ; Use repeated subtraction for divide (max quotient ~27, fast enough)
    ; Numerator = |rotX1| * 13, Denominator = rotY1
    ibt r5, #0                  ; sign flag
    moves r0, r2               ; r2 = rotX1
    bpl _px1_pos
    nop
    from r2
    not
    inc r0
    move r2, r0
    ibt r5, #1
_px1_pos:
    ; r2 = |rotX1|, r5 = sign
    ; Compute |rotX1| * 13 = |X|*8 + |X|*4 + |X| (using only safe patterns)
    move r0, r2
    add r0                      ; r0 = |X|*2
    add r0                      ; r0 = |X|*4
    add r0                      ; r0 = |X|*8
    move r7, r0                 ; r7 = |X|*8
    move r0, r2
    add r0                      ; r0 = |X|*2
    add r0                      ; r0 = |X|*4
    with r7
    add r0                      ; r7 = |X|*12
    with r7
    add r2                      ; r7 = |X|*13
    ; Binary divide: r7 / r1 → r3 (16 iterations, always terminates)
    ibt r2, #0                  ; remainder
    ibt r3, #0                  ; quotient
    iwt r12, #16
_bdiv1:
    with r7
    add r7                      ; shift num left, MSB → carry
    with r2
    rol                         ; remainder = (rem << 1) | carry
    with r3
    add r3                      ; quotient <<= 1
    from r2
    cmp r1                      ; remainder >= divisor?
    blt _bdiv1_ns
    nop
    with r2
    sub r1
    inc r3
_bdiv1_ns:
    dec r12
    bne _bdiv1
    nop
    ; r3 = |rotX1*13| / rotY1
    ; Apply sign, add center offset
    moves r0, r5
    beq _px1_ns
    nop
    from r3
    not
    inc r0
    move r3, r0
_px1_ns:
    with r3
    add #13
    move r11, r3                ; save col1 in r11 (avoids sm/lm bug)

    ; --- Project V2 ---
    lm r4, ($001C)              ; reload rotX2
    lm r1, ($001A)              ; r1 = rotY2 (new divisor)
    ; Ensure rotY2 >= 4
    ibt r0, #4
    from r1
    cmp r0
    bge _ry2ok
    nop
    ibt r1, #4
_ry2ok:
    ibt r5, #0
    moves r0, r4
    bpl _px2_pos
    nop
    from r4
    not
    inc r0
    move r4, r0
    ibt r5, #1
_px2_pos:
    ; r4 = |rotX2|, r3 = rotY2
    move r0, r4
    add r0
    add r0
    add r0
    move r7, r0                 ; r7 = r4*8
    move r0, r4
    add r0
    add r0
    with r7
    add r0                      ; r7 = r4*8 + r4*4 = r4*12
    with r7
    add r4                      ; r7 = r4*13
    ; Binary divide: r7 / r1 → r3
    ibt r2, #0
    ibt r3, #0
    iwt r12, #16
_bdiv2:
    with r7
    add r7
    with r2
    rol
    with r3
    add r3
    from r2
    cmp r1
    blt _bdiv2_ns
    nop
    with r2
    sub r1
    inc r3
_bdiv2_ns:
    dec r12
    bne _bdiv2
    nop
    moves r0, r5
    beq _px2_ns
    nop
    from r3
    not
    inc r0
    move r3, r0
_px2_ns:
    with r3
    add #13
    ; col2 is in r3, col1 is in r11
    move r4, r3                 ; r4 = col2
    move r3, r11                ; r3 = col1 (restored from register)

    ; === Determine column range ===

    ; Ensure col1 <= col2 (swap if needed, also swap depths)
    from r3
    cmp r4
    blt _no_swap
    beq _no_swap
    nop
    move r0, r3
    move r3, r4
    move r4, r0
    lm r0, ($0016)
    lm r1, ($001A)
    sm ($0016), r1
    sm ($001A), r0
_no_swap:
    ; Clamp both to 0..26
    moves r0, r3
    bpl _c1_min_ok
    nop
    ibt r3, #0
_c1_min_ok:
    ibt r0, #(NUM_COLS - 1)
    from r3
    cmp r0
    blt _c1_max_ok
    beq _c1_max_ok
    nop
    ibt r3, #(NUM_COLS - 1)
_c1_max_ok:
    moves r0, r4
    bpl _c2_min_ok
    nop
    ibt r4, #0
_c2_min_ok:
    ibt r0, #(NUM_COLS - 1)
    from r4
    cmp r0
    blt _c2_max_ok
    beq _c2_max_ok
    nop
    ibt r4, #(NUM_COLS - 1)
_c2_max_ok:
    ; Skip if offscreen
    from r4
    cmp r3
    bge _not_offscreen
    nop
    iwt r15, #(_seg_next - $8000)
    nop
_not_offscreen:
    ; FORCE col1=0, col2=26
    ibt r3, #0
    ibt r4, #26

    ; === Fill columns col1..col2 ===
    ; Use average depth for wall height (simplified)
    lm r7, ($0016)              ; rotY1
    lm r8, ($001A)              ; rotY2
    move r0, r7
    with r0
    add r8                      ; r0 = rotY1 + rotY2 (SAFE)
    lsr                         ; r0 = avg depth
    bne _davg_ok
    nop
    ibt r0, #1
_davg_ok:
    ; wallHeight = 576 / avgDepth (repeated subtraction)
    move r1, r0                 ; r1 = divisor (avgDepth)
    iwt r7, #WALL_CONST         ; r7 = 576
    ibt r10, #0                 ; quotient
_whdiv:
    from r7
    cmp r1
    blt _whdiv_done
    nop
    with r7
    sub r1
    inc r10
    ; Cap at SCREEN_H (no point computing higher)
    iwt r0, #SCREEN_H
    from r10
    cmp r0
    blt _whdiv
    nop
_whdiv_done:
    ; r10 = wallHeight, clamp to SCREEN_H
    iwt r0, #SCREEN_H
    from r10
    cmp r0
    blt _wh_ok
    nop
    iwt r10, #SCREEN_H
_wh_ok:
    ; drawStart = HALF_H - wallHeight/2
    from r10
    lsr                         ; r0 = wallHeight/2
    move r5, r0                 ; r5 = half wall
    iwt r6, #HALF_H
    with r6
    sub r5                      ; r6 = drawStart (SAFE: with)
    moves r0, r6
    bpl _ds_ok
    nop
    ibt r6, #0
_ds_ok:
    ; drawEnd = HALF_H + wallHeight/2 - 1
    iwt r0, #HALF_H
    from r0
    add r5                      ; r0 = drawEnd
    iwt r1, #(SCREEN_H - 1)
    from r0
    cmp r1
    blt _de_ok
    beq _de_ok
    nop
    move r0, r1
_de_ok:
    move r7, r0                 ; r7 = drawEnd

    lm r5, ($0010)              ; wallColor

    ; (diagnostics removed - using registers now)

    ; === Fill ALL 27 columns from computed wall height ===
    ; r6 = drawStart, r7 = drawEnd, r5 = wallColor (from wall height code above)
    iwt r1, #RAM_DRAWSTART
    iwt r2, #RAM_DRAWEND
    iwt r3, #RAM_WALLCOLOR
    iwt r8, #RAM_COLFILLED
    ibt r4, #NUM_COLS
_fill_loop:
    ; Check colFilled (ldb doesn't set flags, so add #0 to set them)
    ldb (r8)                    ; r0 = colFilled[col]
    add #0                      ; set zero flag from r0 (ldb doesn't!)
    bne _fill_skip              ; already filled → skip
    nop
    from r6
    stb (r1)                    ; drawStart
    from r7
    stb (r2)                    ; drawEnd
    from r5
    stb (r3)                    ; wallColor
    ibt r0, #1
    stb (r8)                    ; mark filled
_fill_skip:
    inc r1
    inc r2
    inc r3
    inc r8
    with r4
    sub #1
    bne _fill_loop
    nop

_seg_next:
    ; Advance to next seg
    lm r10, ($000C)
    ibt r0, #SEG_SIZE
    with r10
    add r0                      ; r10 += 11

    lm r11, ($000A)             ; remaining count
    with r11
    sub #1
    lm r9, ($000E)              ; restore BSP stack

    iwt r15, #(_seg_loop - $8000)
    nop

_seg_done:
    ; Return from subsector
    lm r9, ($000E)
    dec r9
    dec r9
    to r0
    ldw (r9)
    move r15, r0
    nop

_bsp_done:
    ; BSP traversal + segment processing complete
    ; Fall through to Phase 2 tile rendering.

    ; =================================================================
    ; PHASE 2: ROW-BY-ROW TILE RENDERING (stb bitplane method)
    ; =================================================================
    ; This code reads drawStart[27], drawEnd[27], wallColor[27]
    ; and writes 8bpp tiles to the framebuffer at $70:0400
    ;
    ; For each tile row (0..17), for each column (0..26):
    ;   Determine ceiling/wall/floor for each of the 8 pixel rows
    ;   Write 64-byte tile data using stb

    ; Precompute ceiling color bitplanes (color 16 = bit4, BP4=$FF all others $00)
    iwt r7, #RAM_CEIL_BP
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$FF
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)

    ; Precompute floor color bitplanes (color 17 = bit0+bit4, BP0=$FF BP4=$FF)
    iwt r7, #RAM_FLOOR_BP
    ibt r0, #$FF
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$FF
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)
    inc r7
    ibt r0, #$00
    stb (r7)

    ; Initialize tile row loop
    ibt r3, #0                  ; r3 = tileRow (0..17)
    ibt r0, #0
    sm (RAM_TROW_Y), r0        ; pixel_y_start = 0

    ; Compute framebuffer base pointer
    iwt r1, #FB_BASE

_trow_loop:
    ; Initialize column loop
    ibt r2, #0                  ; r2 = column (0..26)

_col_loop:
    ; r1 = FB write pointer (tile data destination)
    ; r2 = column index (0..26)
    ; r3 = tile row index (0..17)

    ; Read drawStart, drawEnd, wallColor for this column
    iwt r0, #RAM_DRAWSTART
    from r2
    to r8
    add r0
    to r4
    ldb (r8)                   ; r4 = drawStart

    iwt r0, #RAM_DRAWEND
    from r2
    to r8
    add r0
    to r5
    ldb (r8)                   ; r5 = drawEnd

    iwt r0, #RAM_WALLCOLOR
    from r2
    to r8
    add r0
    to r6
    ldb (r8)                   ; r6 = wallColor

    ; Precompute wall color bitplanes from r6
    ; BP0 = bit0 expanded, BP1 = bit1, ... BP7 = bit7
    ; For each bit: $FF if set, $00 if clear
    iwt r7, #RAM_WALL_BP
    ; BP0 = bit 0
    from r6
    lob
    ibt r8, #1
    AND r8
    ibt r8, #0
    from r8
    to r0
    sub r0
    lob
    stb (r7)
    inc r7
    ; BP1 = bit 1
    from r6
    lob
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
    lob
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

    ; --- Per-row tile rendering (pixel-accurate boundaries) ---
    ; Precompute 8 row color types at $00E0-$00E7
    ; 0=ceiling, 1=wall, 2=floor
    lm r7, (RAM_TROW_Y)    ; pixel_y_start for this tile row
    iwt r10, #$00E0
    ibt r11, #8
_pc_loop:
    from r7
    cmp r4                  ; pixel_y - drawStart
    bge _pc_nc
    nop
    ibt r0, #0              ; ceiling
    bra _pc_store
    nop
_pc_nc:
    from r5
    cmp r7                  ; drawEnd - pixel_y
    bge _pc_w
    nop
    ibt r0, #2              ; floor
    bra _pc_store
    nop
_pc_w:
    ibt r0, #1              ; wall
_pc_store:
    stb (r10)
    inc r10
    inc r7
    ibt r0, #1
    with r11
    sub r0
    ibt r0, #0
    from r11
    cmp r0
    bne _pc_loop
    nop

    ; Write 4 BP groups using precomputed color types
    ; Group 0 (BP0, BP1)
    iwt r10, #$00E0
    ibt r11, #8
_wt_g0:
    ldb (r10)               ; r0 = color type
    ibt r8, #1
    from r0
    cmp r8
    blt _wt_g0_c
    nop
    beq _wt_g0_w
    nop
    iwt r9, #RAM_FLOOR_BP
    bra _wt_g0_s
    nop
_wt_g0_c:
    iwt r9, #RAM_CEIL_BP
    bra _wt_g0_s
    nop
_wt_g0_w:
    iwt r9, #RAM_WALL_BP
_wt_g0_s:
    ldb (r9)
    stb (r1)
    inc r1
    inc r9
    ldb (r9)
    stb (r1)
    inc r1
    inc r10
    ibt r0, #1
    with r11
    sub r0
    ibt r0, #0
    from r11
    cmp r0
    bne _wt_g0
    nop

    ; Group 1 (BP2, BP3)
    iwt r10, #$00E0
    ibt r11, #8
_wt_g1:
    ldb (r10)
    ibt r8, #1
    from r0
    cmp r8
    blt _wt_g1_c
    nop
    beq _wt_g1_w
    nop
    iwt r9, #RAM_FLOOR_BP + 2
    bra _wt_g1_s
    nop
_wt_g1_c:
    iwt r9, #RAM_CEIL_BP + 2
    bra _wt_g1_s
    nop
_wt_g1_w:
    iwt r9, #RAM_WALL_BP + 2
_wt_g1_s:
    ldb (r9)
    stb (r1)
    inc r1
    inc r9
    ldb (r9)
    stb (r1)
    inc r1
    inc r10
    ibt r0, #1
    with r11
    sub r0
    ibt r0, #0
    from r11
    cmp r0
    bne _wt_g1
    nop

    ; Group 2 (BP4, BP5)
    iwt r10, #$00E0
    ibt r11, #8
_wt_g2:
    ldb (r10)
    ibt r8, #1
    from r0
    cmp r8
    blt _wt_g2_c
    nop
    beq _wt_g2_w
    nop
    iwt r9, #RAM_FLOOR_BP + 4
    bra _wt_g2_s
    nop
_wt_g2_c:
    iwt r9, #RAM_CEIL_BP + 4
    bra _wt_g2_s
    nop
_wt_g2_w:
    iwt r9, #RAM_WALL_BP + 4
_wt_g2_s:
    ldb (r9)
    stb (r1)
    inc r1
    inc r9
    ldb (r9)
    stb (r1)
    inc r1
    inc r10
    ibt r0, #1
    with r11
    sub r0
    ibt r0, #0
    from r11
    cmp r0
    bne _wt_g2
    nop

    ; Group 3 (BP6, BP7)
    iwt r10, #$00E0
    ibt r11, #8
_wt_g3:
    ldb (r10)
    ibt r8, #1
    from r0
    cmp r8
    blt _wt_g3_c
    nop
    beq _wt_g3_w
    nop
    iwt r9, #RAM_FLOOR_BP + 6
    bra _wt_g3_s
    nop
_wt_g3_c:
    iwt r9, #RAM_CEIL_BP + 6
    bra _wt_g3_s
    nop
_wt_g3_w:
    iwt r9, #RAM_WALL_BP + 6
_wt_g3_s:
    ldb (r9)
    stb (r1)
    inc r1
    inc r9
    ldb (r9)
    stb (r1)
    inc r1
    inc r10
    ibt r0, #1
    with r11
    sub r0
    ibt r0, #0
    from r11
    cmp r0
    bne _wt_g3
    nop

    ; Next column
    inc r2
    ibt r0, #NUM_COLS
    from r2
    cmp r0
    bge _col_done
    nop
    iwt r15, #(_col_loop - $8000)
    nop
_col_done:

    ; Next tile row
    inc r3
    lm r0, (RAM_TROW_Y)
    ibt r2, #8
    from r0
    to r0
    add r2
    sm (RAM_TROW_Y), r0
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

; Sin/Cos tables (1.15 format, 256 entries each)
.include "data/gsu_tables.asm"

; BSP map data (Doom SNES format)
.include "data/bsp_data.asm"


.ENDS
