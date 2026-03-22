; bsp_data.asm — Doom SNES format BSP data (auto-generated)
; 8 vertices, 8 segs, 8 areas
; 7 nodes, 1 sectors
; Structure sizes: vertex=4, seg=11, area=4, node=28

.define NUM_VERTS 8
.define NUM_SEGS 8
.define NUM_AREAS 8
.define NUM_NODES 7
.define NUM_SECTORS 1
.define ROOT_NODE_OFFSET 168

; --- Vertices (8, 4 bytes each) ---
bsp_vertices:
    .dw 0, 0    ; v0 @0
    .dw 1024, 0    ; v1 @4
    .dw 1024, 1024    ; v2 @8
    .dw 0, 1024    ; v3 @12
    .dw 384, 384    ; v4 @16
    .dw 640, 384    ; v5 @20
    .dw 640, 640    ; v6 @24
    .dw 384, 640    ; v7 @28

; --- BSP Nodes (7, 28 bytes each) ---
; Field order: LineY, DeltaX, LineX, DeltaY,
;   LeftBBox(YMax,YMin,XMin,XMax), LeftChild,
;   RightBBox(YMax,YMin,XMin,XMax), RightChild
bsp_nodes:
    ; node 0 @0: partition (0,1024)+(0,-1024)
    .dw 1024, 0, 0, -1024
    .dw 640, 384, 384, 384    ; left bbox
    .dw $8010    ; left child
    .dw 1024, 0, 0, 0    ; right bbox
    .dw $800C    ; right child
    ; node 1 @28: partition (640,384)+(0,256)
    .dw 384, 0, 640, 256
    .dw 640, 640, 384, 640    ; left bbox
    .dw $801C    ; left child
    .dw 640, 384, 640, 640    ; right bbox
    .dw $8018    ; right child
    ; node 2 @56: partition (384,384)+(256,0)
    .dw 384, 256, 384, 0
    .dw 640, 384, 384, 640    ; left bbox
    .dw $001C    ; left child
    .dw 384, 384, 384, 640    ; right bbox
    .dw $8014    ; right child
    ; node 3 @84: partition (384,640)+(0,-256)
    .dw 640, 0, 384, -256
    .dw 640, 384, 384, 640    ; left bbox
    .dw $0038    ; left child
    .dw 1024, 0, 0, 384    ; right bbox
    .dw $0000    ; right child
    ; node 4 @112: partition (1024,1024)+(-1024,0)
    .dw 1024, -1024, 1024, 0
    .dw 1024, 0, 0, 640    ; left bbox
    .dw $0054    ; left child
    .dw 1024, 1024, 0, 1024    ; right bbox
    .dw $8008    ; right child
    ; node 5 @140: partition (1024,0)+(0,1024)
    .dw 0, 0, 1024, 1024
    .dw 1024, 0, 0, 1024    ; left bbox
    .dw $0070    ; left child
    .dw 1024, 0, 1024, 1024    ; right bbox
    .dw $8004    ; right child
    ; node 6 @168: partition (0,0)+(1024,0)
    .dw 0, 1024, 0, 0
    .dw 1024, 0, 0, 1024    ; left bbox
    .dw $008C    ; left child
    .dw 0, 0, 0, 1024    ; right bbox
    .dw $8000    ; right child

; --- Areas (8, 4 bytes each) ---
; Fields: NumSegs(1), SegOffset(2), Sector(1)
bsp_areas:
    .db 1         ; numSegs  (area 0)
    .dw 0     ; segOffset
    .db 0         ; sector
    .db 1         ; numSegs  (area 1)
    .dw 11     ; segOffset
    .db 0         ; sector
    .db 1         ; numSegs  (area 2)
    .dw 22     ; segOffset
    .db 0         ; sector
    .db 1         ; numSegs  (area 3)
    .dw 33     ; segOffset
    .db 0         ; sector
    .db 1         ; numSegs  (area 4)
    .dw 44     ; segOffset
    .db 0         ; sector
    .db 1         ; numSegs  (area 5)
    .dw 55     ; segOffset
    .db 0         ; sector
    .db 1         ; numSegs  (area 6)
    .dw 66     ; segOffset
    .db 0         ; sector
    .db 1         ; numSegs  (area 7)
    .dw 77     ; segOffset
    .db 0         ; sector

; --- Segs (8, 11 bytes each) ---
; Fields: V1offset(2), V2offset(2), Flags(1), WallColor(1),
;         pad(1), Face(2), Line(2)
bsp_segs:
    ; seg 0: v0->v1 (line 0, color 1)
    .dw 0, 4    ; vertex byte offsets
    .db $01              ; flags
    .db 1              ; wallColor
    .db 0              ; pad
    .dw 0, 0           ; face, line (unused)
    ; seg 1: v1->v2 (line 1, color 1)
    .dw 4, 8    ; vertex byte offsets
    .db $01              ; flags
    .db 1              ; wallColor
    .db 0              ; pad
    .dw 0, 0           ; face, line (unused)
    ; seg 2: v2->v3 (line 2, color 1)
    .dw 8, 12    ; vertex byte offsets
    .db $01              ; flags
    .db 1              ; wallColor
    .db 0              ; pad
    .dw 0, 0           ; face, line (unused)
    ; seg 3: v3->v0 (line 3, color 1)
    .dw 12, 0    ; vertex byte offsets
    .db $01              ; flags
    .db 1              ; wallColor
    .db 0              ; pad
    .dw 0, 0           ; face, line (unused)
    ; seg 4: v7->v4 (line 7, color 3)
    .dw 28, 16    ; vertex byte offsets
    .db $01              ; flags
    .db 3              ; wallColor
    .db 0              ; pad
    .dw 0, 0           ; face, line (unused)
    ; seg 5: v4->v5 (line 4, color 3)
    .dw 16, 20    ; vertex byte offsets
    .db $01              ; flags
    .db 3              ; wallColor
    .db 0              ; pad
    .dw 0, 0           ; face, line (unused)
    ; seg 6: v5->v6 (line 5, color 3)
    .dw 20, 24    ; vertex byte offsets
    .db $01              ; flags
    .db 3              ; wallColor
    .db 0              ; pad
    .dw 0, 0           ; face, line (unused)
    ; seg 7: v6->v7 (line 6, color 3)
    .dw 24, 28    ; vertex byte offsets
    .db $01              ; flags
    .db 3              ; wallColor
    .db 0              ; pad
    .dw 0, 0           ; face, line (unused)

; --- Sectors (1) ---
bsp_sectors:
    .dw 0, 128, 192    ; sector 0

