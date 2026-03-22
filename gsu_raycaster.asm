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
    sm ($0180), r0

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
    sm ($0152), r14             ; save ROM ptr at LeftBBox
    sm ($0154), r4              ; save DeltaY

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
    lm r6, ($0154)              ; r6 = DeltaY
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
    lm r14, ($0152)             ; restore ROM ptr at LeftBBox
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
    lm r14, ($0152)             ; restore ROM ptr at LeftBBox
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
    ; Strip $8000 flag by adding $8000 (wraps: $8000+offset + $8000 = offset)
    iwt r0, #$8000
    from r8
    add r0                      ; r0 = area byte offset (stripped $8000)

    ; Read area data from ROM
    iwt r1, #(bsp_areas - $8000)
    to r14
    add r1                      ; r14 -> area: numSegs(1), segOffset(2), sector(1)

    to r11
    getb                        ; r11 = numSegs
    inc r14
    getb
    inc r14
    to r10
    getbh                       ; r10 = segOffset (byte offset from bsp_segs)
    inc r14

    ; Compute absolute ROM address of first seg
    iwt r0, #(bsp_segs - $8000)
    from r10
    to r10
    add r0                      ; r10 = ROM addr of first seg

    ; Process each segment in this subsector
_seg_loop:
    moves r0, r11
    bne _seg_has_more
    nop
    ; No more segs — long branch to _seg_done
    iwt r15, #(_seg_done - $8000)
    nop
_seg_has_more:

    ; Save loop state
    sm ($0156), r11             ; remaining seg count
    sm ($0158), r10             ; current seg ROM addr
    sm ($015A), r9              ; BSP stack ptr (preserve during seg processing)

    ; === Read segment data ===
    move r14, r10
    ; V1 offset
    getb
    inc r14
    to r1
    getbh                       ; r1 = v1 byte offset into vertex array
    inc r14
    ; V2 offset
    getb
    inc r14
    to r2
    getbh                       ; r2 = v2 byte offset into vertex array
    inc r14
    ; Skip flags (1 byte)
    inc r14
    ; Wall color
    to r3
    getb                        ; r3 = wallColor
    sm ($015C), r3              ; save wallColor

    ; === Process this segment: rotate vertices, project, fill columns ===
    ; Save vertex offsets
    sm ($015E), r1              ; v1 offset
    sm ($0160), r2              ; v2 offset

    ; --- Rotate vertex 1 ---
    lm r1, ($015E)              ; v1 byte offset
    ; Check if already rotated: RAM_ROTVERTS + v1_offset has rotY
    ; v1_offset is vertex_index * 4, and RAM_ROTVERTS also uses 4 bytes per vert
    ; So RAM address = RAM_ROTVERTS + v1_byte_offset
    iwt r0, #RAM_ROTVERTS
    from r1
    to r7
    add r0                      ; r7 = RAM addr of rotated v1
    to r0
    ldw (r7)                    ; r0 = rotY of v1
    iwt r4, #$8000
    from r0
    cmp r4
    beq _v1_need_rotate
    nop
    ; Already rotated — long branch
    iwt r15, #(_v1_already_rotated - $8000)
    nop
_v1_need_rotate:

    ; Not rotated — compute rotation
    ; Read original vertex from ROM
    iwt r0, #(bsp_vertices - $8000)
    from r1
    to r14
    add r0                      ; r14 -> vertex X, Y in ROM

    getb
    inc r14
    to r3
    getbh                       ; r3 = vertexX
    inc r14
    getb
    inc r14
    to r4
    getbh                       ; r4 = vertexY

    ; dx = vertexX - viewX, dy = vertexY - viewY
    lm r0, (RAM_VIEWX)
    from r3
    to r3
    sub r0                      ; r3 = dx = vertexX - viewX
    lm r0, (RAM_VIEWY)
    from r4
    to r4
    sub r0                      ; r4 = dy = vertexY - viewY

    ; rotY = cos*dx + sin*dy (following Doom's rlsegs2.a)
    lm r6, (RAM_COS)
    move r0, r3                 ; r0 = dx
    fmult
    rol                         ; r0 = cos * dx (world units)
    move r5, r0                 ; r5 = cos*dx

    lm r6, (RAM_SIN)
    move r0, r4                 ; r0 = dy
    fmult
    rol                         ; r0 = sin * dy
    with r5
    add r0                      ; r5 = cos*dx + sin*dy = rotY

    ; Subtract screen plane distance
    with r5
    sub #SCREEN_PLANE           ; r5 = rotY - 4

    ; rotX = sin*dx - cos*dy
    lm r6, (RAM_SIN)
    move r0, r3                 ; r0 = dx
    fmult
    rol                         ; r0 = sin * dx
    move r8, r0                 ; r8 = sin*dx (temporarily reusing r8)

    lm r6, (RAM_COS)
    move r0, r4                 ; r0 = dy
    fmult
    rol                         ; r0 = cos * dy
    from r8
    sub r0                      ; r0 = sin*dx - cos*dy = rotX

    ; Store rotated vertex
    ; r7 = RAM addr, r5 = rotY, r0 = rotX
    from r5
    stw (r7)                    ; store rotY
    inc r7
    inc r7
    stw (r7)                    ; store rotX (r0)
    dec r7
    dec r7

_v1_already_rotated:
    ; Load rotated v1: r5 = rotY1, r6 = rotX1
    ; r7 = RAM addr of v1
    to r5
    ldw (r7)                    ; r5 = rotY1
    inc r7
    inc r7
    to r6
    ldw (r7)                    ; r6 = rotX1
    sm ($0162), r5              ; save rotY1
    sm ($0164), r6              ; save rotX1

    ; --- Rotate vertex 2 ---
    lm r2, ($0160)              ; v2 byte offset
    iwt r0, #RAM_ROTVERTS
    from r2
    to r7
    add r0                      ; r7 = RAM addr of rotated v2
    to r0
    ldw (r7)
    iwt r4, #$8000
    from r0
    cmp r4
    beq _v2_need_rotate
    nop
    iwt r15, #(_v2_already_rotated - $8000)
    nop
_v2_need_rotate:

    ; Not rotated — compute rotation (same as v1)
    iwt r0, #(bsp_vertices - $8000)
    from r2
    to r14
    add r0

    getb
    inc r14
    to r3
    getbh                       ; r3 = vertexX
    inc r14
    getb
    inc r14
    to r4
    getbh                       ; r4 = vertexY

    lm r0, (RAM_VIEWX)
    from r3
    to r3
    sub r0                      ; r3 = dx
    lm r0, (RAM_VIEWY)
    from r4
    to r4
    sub r0                      ; r4 = dy

    lm r6, (RAM_COS)
    move r0, r3
    fmult
    rol
    move r5, r0                 ; cos*dx

    lm r6, (RAM_SIN)
    move r0, r4
    fmult
    rol
    with r5
    add r0                      ; rotY = cos*dx + sin*dy
    with r5
    sub #SCREEN_PLANE

    lm r6, (RAM_SIN)
    move r0, r3
    fmult
    rol
    move r8, r0                 ; sin*dx

    lm r6, (RAM_COS)
    move r0, r4
    fmult
    rol
    from r8
    sub r0                      ; rotX = sin*dx - cos*dy

    from r5
    stw (r7)
    inc r7
    inc r7
    stw (r7)
    dec r7
    dec r7

_v2_already_rotated:
    ; Load rotated v2
    to r5
    ldw (r7)                    ; r5 = rotY2
    inc r7
    inc r7
    to r6
    ldw (r7)                    ; r6 = rotX2
    sm ($0166), r5              ; save rotY2
    sm ($0168), r6              ; save rotX2

    ; === Visibility checks ===
    ; Skip if both vertices behind camera (rotY <= 0)
    lm r5, ($0162)              ; rotY1
    lm r3, ($0166)              ; rotY2
    moves r0, r5
    bpl _v1_in_front
    nop
    ; v1 behind. Check v2.
    moves r0, r3
    bpl _at_least_one_front
    nop
    ; Both behind — skip this segment
    iwt r15, #(_seg_next - $8000)
    nop
_v1_in_front:
_at_least_one_front:

    ; === Back-face cull ===
    ; Cross product of segment direction and view-to-v1 direction
    ; segDX = rotX2 - rotX1, segDY = rotY2 - rotY1
    ; viewDX = rotX1, viewDY = rotY1 (from origin since already translated)
    ; Cross = segDX * rotY1 - segDY * rotX1
    ; If cross < 0: back-facing, skip
    lm r1, ($0164)              ; rotX1
    lm r2, ($0162)              ; rotY1
    lm r3, ($0168)              ; rotX2
    lm r4, ($0166)              ; rotY2

    ; segDX = rotX2 - rotX1
    from r3
    to r5
    sub r1                      ; r5 = segDX

    ; segDY = rotY2 - rotY1
    from r4
    to r7
    sub r2                      ; r7 = segDY

    ; Cross = segDX * rotY1 - segDY * rotX1
    move r6, r5                 ; r6 = segDX
    move r0, r2                 ; r0 = rotY1
    lmult                       ; R0:R4 = segDX * rotY1
    move r5, r0                 ; high word
    move r8, r4                 ; low word

    move r6, r7                 ; r6 = segDY
    move r0, r1                 ; r0 = rotX1
    lmult                       ; R0:R4 = segDY * rotX1

    ; Cross = (r5:r8) - (r0:r4)
    with r8
    sub r4
    with r5
    sbc r0

    ; If cross < 0: back-facing, skip (long branch)
    moves r0, r5
    bpl _not_backface
    nop
    iwt r15, #(_seg_next - $8000)
    nop
_not_backface:

    ; === Clamp depths: if a vertex is behind camera, set depth = 1 ===
    lm r1, ($0162)              ; rotY1
    lm r2, ($0164)              ; rotX1
    lm r3, ($0166)              ; rotY2
    lm r4, ($0168)              ; rotX2
    moves r0, r1
    bpl _y1_ok
    nop
    ibt r1, #1                  ; clamp depth to 1
    ; Clip rotX1 towards rotX2 (simplified: just use rotX2)
    move r2, r4
_y1_ok:
    moves r0, r3
    bpl _y2_ok
    nop
    ibt r3, #1
    move r4, r2
_y2_ok:
    ; r1=Y1, r2=X1, r3=Y2, r4=X2 (all positive depths)

    ; === Project to screen X ===
    ; screenX = rotX * 27 / rotY * 4 + HALF_W
    ; Using tile columns: tileCol = rotX * 13 / rotY + 13
    ; (13 = NUM_COLS/2 = 27/2, we use 13 and add 0.5 by rounding)

    ; Project vertex 1: screenX1 = rotX1 * 27 / rotY1
    ; Step 1: rotX1 * 27 (fits in s16 for our map size)
    move r0, r2                 ; r0 = rotX1
    iwt r6, #27
    lmult                       ; R0:R4 = rotX1 * 27
    ; For small values, result is in R4 (low word)
    ; Use R4 as numerator for divide
    move r5, r4                 ; r5 = rotX1 * 27 (low 16 bits)
    move r7, r0                 ; r7 = high word (for overflow check)

    ; Divide r5 by r1 (rotY1)
    ; Handle sign: r5 could be negative
    sm ($016A), r1              ; save rotY1 for later
    sm ($016C), r2              ; save rotX1
    sm ($016E), r3              ; save rotY2
    sm ($0170), r4              ; save rotX2

    ; Signed divide: r5 / r1 -> result in r0
    ; numerator in r5, denominator in r1
    ibt r11, #0                 ; sign flag
    moves r0, r5
    bpl _d1_npos
    nop
    with r5
    not
    inc r5
    ibt r11, #1
_d1_npos:
    ; r1 (rotY1) is always positive (we clamped it)
    ; 16-bit unsigned divide: r5 / r1
    ibt r2, #0                  ; remainder
    ibt r3, #0                  ; quotient
    iwt r12, #16                ; loop counter
_div1_loop:
    with r5
    add r5                      ; shift numerator left, MSB to carry
    with r2
    rol                         ; remainder = (remainder << 1) | carry
    with r3
    add r3                      ; quotient <<= 1
    from r2
    cmp r1                      ; remainder >= divisor?
    blt _div1_nosub
    nop
    with r2
    sub r1                      ; remainder -= divisor
    inc r3                      ; quotient |= 1
_div1_nosub:
    dec r12
    bne _div1_loop
    nop
    ; r3 = quotient = |rotX1 * 27 / rotY1|

    ; Apply sign
    moves r0, r11
    beq _d1_done
    nop
    with r3
    not
    inc r3
_d1_done:
    ; r3 = rotX1 * 27 / rotY1 (signed)
    ; screenX1 = r3 * 4 + HALF_W
    with r3
    add r3                      ; r3 *= 2
    with r3
    add r3                      ; r3 *= 2 (total: *4)
    iwt r0, #HALF_W
    with r3
    add r0                      ; r3 = screenX1 in pixels
    sm ($0172), r3              ; save screenX1

    ; Project vertex 2: same procedure
    lm r2, ($0170)              ; rotX2 (saved earlier... wait, r4 was overwritten)
    ; Reload from saved values
    lm r4, ($0168)              ; rotX2 (original)
    lm r1, ($016E)              ; rotY2

    ; rotX2 * 27
    move r0, r4
    iwt r6, #27
    lmult
    move r5, r4                 ; r5 = rotX2 * 27 (low word)

    ; Signed divide: r5 / r1
    ibt r11, #0
    moves r0, r5
    bpl _d2_npos
    nop
    with r5
    not
    inc r5
    ibt r11, #1
_d2_npos:
    ibt r2, #0
    ibt r3, #0
    iwt r12, #16
_div2_loop:
    with r5
    add r5
    with r2
    rol
    with r3
    add r3
    from r2
    cmp r1
    blt _div2_nosub
    nop
    with r2
    sub r1
    inc r3
_div2_nosub:
    dec r12
    bne _div2_loop
    nop

    moves r0, r11
    beq _d2_done
    nop
    with r3
    not
    inc r3
_d2_done:
    with r3
    add r3
    with r3
    add r3
    iwt r0, #HALF_W
    with r3
    add r0
    sm ($0174), r3              ; save screenX2

    ; === Determine column range ===
    lm r1, ($0172)              ; screenX1 (pixels)
    lm r2, ($0174)              ; screenX2 (pixels)

    ; Ensure x1 <= x2 (swap if needed, also swap depths)
    from r1
    cmp r2
    blt _no_swap
    beq _no_swap
    nop
    ; Swap
    move r0, r1
    move r1, r2
    move r2, r0
    ; Also swap depths
    lm r3, ($016A)              ; rotY1
    lm r4, ($016E)              ; rotY2
    sm ($016A), r4
    sm ($016E), r3
_no_swap:
    ; r1 = leftX (pixels), r2 = rightX (pixels)
    ; Clamp to viewport: 0..215
    moves r0, r1
    bpl _x1_pos
    nop
    ibt r1, #0
_x1_pos:
    iwt r0, #215
    from r2
    cmp r0
    blt _x2_ok
    beq _x2_ok
    nop
    iwt r2, #215
_x2_ok:
    ; Skip if entirely off-screen (long branch)
    from r2
    cmp r1
    bge _not_offscreen
    nop
    iwt r15, #(_seg_next - $8000)
    nop
_not_offscreen:

    ; Convert to tile columns: col = pixelX / 8
    from r1
    lsr
    lsr
    to r3
    lsr                         ; r3 = leftCol = leftX / 8
    from r2
    lsr
    lsr
    to r4
    lsr                         ; r4 = rightCol = rightX / 8

    ; Clamp columns to 0..26
    ibt r0, #(NUM_COLS - 1)
    from r4
    cmp r0
    blt _col_ok
    beq _col_ok
    nop
    ibt r4, #(NUM_COLS - 1)
_col_ok:

    ; === Fill columns ===
    ; For each column from r3 (leftCol) to r4 (rightCol):
    ;   if not filled: compute wall height, fill column
    lm r5, ($015C)              ; wallColor
    lm r7, ($016A)              ; rotY1 (depth at left edge)
    lm r8, ($016E)              ; rotY2 (depth at right edge)

_fill_col_loop:
    ; Check if column already filled
    iwt r0, #RAM_COLFILLED
    from r3
    to r14
    add r0                      ; r14 would need to be ROM... but this is RAM
    ; Use ldb for RAM read instead
    iwt r0, #RAM_COLFILLED
    from r3
    to r1
    add r0                      ; r1 = RAM addr of columnFilled[col]
    to r0
    ldb (r1)                    ; r0 = columnFilled[col]
    beq _fill_this_col          ; not filled, process it
    nop
    iwt r15, #(_fill_next_col - $8000)
    nop
_fill_this_col:

    ; Interpolate depth for this column
    ; For simplicity, use average of Y1 and Y2 for now
    ; (proper interpolation would weight by column position within segment)
    from r7
    to r0
    add r8                      ; r0 = Y1 + Y2
    lsr                         ; r0 = (Y1 + Y2) / 2 = average depth

    ; Ensure depth >= 1
    bne _depth_ok
    nop
    ibt r0, #1
_depth_ok:
    ; Wall height = WALL_CONST / depth = 576 / depth
    ; Using divide: numerator = 576, divisor = depth
    move r1, r0                 ; r1 = depth (divisor)
    iwt r5, #WALL_CONST         ; r5 = 576 (numerator)

    ; Unsigned divide: r5 / r1 -> wallHeight in r10
    move r6, r5                 ; r6 = numerator (576)
    ibt r2, #0                  ; remainder
    ibt r10, #0                 ; quotient
    iwt r12, #16
_div3_loop2:
    with r6
    add r6
    with r2
    rol
    with r10
    add r10                     ; quotient <<= 1
    from r2
    cmp r1                      ; remainder >= divisor?
    blt _div3_nosub
    nop
    with r2
    sub r1
    inc r10
_div3_nosub:
    dec r12
    bne _div3_loop2
    nop
    ; r10 = wallHeight = 576 / depth

    ; Clamp wallHeight to SCREEN_H
    iwt r0, #SCREEN_H
    from r10
    cmp r0
    blt _wh_ok
    nop
    iwt r10, #SCREEN_H
_wh_ok:
    ; drawStart = HALF_H - wallHeight/2
    from r10
    lsr                         ; r0 = wallHeight / 2
    iwt r1, #HALF_H
    from r1
    to r2
    sub r0                      ; r2 = HALF_H - wallHeight/2 = drawStart
    ; Clamp drawStart >= 0
    moves r0, r2
    bpl _ds_ok
    nop
    ibt r2, #0
_ds_ok:

    ; drawEnd = HALF_H + wallHeight/2
    from r10
    lsr                         ; r0 = wallHeight / 2
    iwt r1, #HALF_H
    from r1
    add r0                      ; r0 = HALF_H + wallHeight/2 = drawEnd
    ; Clamp drawEnd <= SCREEN_H - 1
    iwt r1, #(SCREEN_H - 1)
    from r0
    cmp r1
    blt _de_ok
    beq _de_ok
    nop
    iwt r0, #(SCREEN_H - 1)
_de_ok:
    move r11, r0                ; r11 = drawEnd

    ; Write to column buffer
    ; drawStart[col]
    iwt r0, #RAM_DRAWSTART
    from r3
    to r1
    add r0
    from r2
    stb (r1)                    ; drawStart[col] = r2

    ; drawEnd[col]
    iwt r0, #RAM_DRAWEND
    from r3
    to r1
    add r0
    from r11
    stb (r1)                    ; drawEnd[col] = r11

    ; wallColor[col]
    lm r5, ($015C)              ; reload wallColor
    iwt r0, #RAM_WALLCOLOR
    from r3
    to r1
    add r0
    from r5
    stb (r1)                    ; wallColor[col] = color

    ; Mark column as filled
    iwt r0, #RAM_COLFILLED
    from r3
    to r1
    add r0
    ibt r0, #1
    stb (r1)                    ; columnFilled[col] = 1

_fill_next_col:
    ; Reload wallColor and depths for next iteration
    lm r5, ($015C)
    lm r7, ($016A)
    lm r8, ($016E)
    inc r3                      ; next column
    from r4
    cmp r3                      ; rightCol >= col? (swapped for bge)
    blt _fill_col_done
    nop
    iwt r15, #(_fill_col_loop - $8000)
    nop
_fill_col_done:

_seg_next:
    ; Advance to next seg in subsector
    lm r10, ($0158)             ; current seg ROM addr
    ibt r0, #SEG_SIZE           ; +11 bytes
    with r10
    add r0                      ; Hmm, 11 > 15 max for add #N
    ; Need: r10 += 11. Use two adds: +8 then +3
    ; Actually, we use with r10; add r0 where r0 = 11
    ; But add rN uses register not immediate for values > 15
    ; Wait, `with r10; add r0` means r10 = r10 + r0, where r0 = 11 (set by ibt)
    ; ibt r0, #11 → r0 = 11 (sign extended: 11 is fine, < 128)
    ; Then: with r10; add r0 → r10 = r10 + 11. But `add rN` format?
    ; Actually `add rN` is: DREG = SREG + rN. Default DREG=SREG=R0.
    ; with r10: DREG=r10, SREG=r10. So `with r10; add r0` = r10 = r10 + r0. Yes!

    ; Recalculate properly:
    lm r10, ($0158)
    ibt r0, #SEG_SIZE
    with r10
    add r0                      ; r10 += 11

    lm r11, ($0156)             ; remaining seg count
    with r11
    sub #1                      ; --numSegs
    lm r9, ($015A)              ; restore BSP stack ptr

    ; Continue seg loop
    iwt r15, #(_seg_loop - $8000)
    nop

_seg_done:
    ; Return from subsector — pop return address from BSP stack
    lm r9, ($015A)              ; restore BSP stack ptr (in case it wasn't saved)
    dec r9
    dec r9
    to r0
    ldw (r9)                    ; r0 = return address
    move r15, r0                ; jump
    nop

_bsp_done:
    ; BSP traversal complete.
    ; TEST: Fill columns using visit count + angle to verify traversal worked
    lm r5, (RAM_ANGLE)          ; r5 = angle (0-255)
    lm r6, ($0180)              ; r6 = subsector visit count

    ; Fill 27 columns: height based on angle, color based on visit count
    iwt r1, #RAM_DRAWSTART
    iwt r2, #RAM_DRAWEND
    iwt r3, #RAM_WALLCOLOR
    ibt r4, #NUM_COLS
_bsp_diag_fill:
    ; drawStart = angle/2
    move r0, r5
    lsr                         ; r0 = angle/2
    stb (r1)
    inc r1

    ; drawEnd = 143 - angle/2
    move r0, r5
    lsr
    iwt r7, #143
    from r7
    sub r0
    stb (r2)
    inc r2

    ; wallColor = 1 (brown, known visible)
    ibt r0, #1
    stb (r3)
    inc r3

    with r4
    sub #1
    bne _bsp_diag_fill
    nop

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
