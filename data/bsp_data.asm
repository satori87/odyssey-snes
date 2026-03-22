; bsp_data.asm — Auto-generated BSP data from WAD
; 8 vertices, 8 segs, 8 subsectors
; 7 nodes, 1 sectors
; 8 linedefs, 8 sidedefs

; --- Vertices (8) ---
.define NUM_VERTS 8
bsp_vertices:
    .dw 0, 0    ; vertex 0
    .dw 1024, 0    ; vertex 1
    .dw 1024, 1024    ; vertex 2
    .dw 0, 1024    ; vertex 3
    .dw 384, 384    ; vertex 4
    .dw 640, 384    ; vertex 5
    .dw 640, 640    ; vertex 6
    .dw 384, 640    ; vertex 7

; --- Segs (8) ---
.define NUM_SEGS 8
bsp_segs:
    .dw 0, 1, 0, 0, 0, 0    ; seg 0
    .dw 1, 2, 16384, 1, 0, 0    ; seg 1
    .dw 2, 3, -32768, 2, 0, 0    ; seg 2
    .dw 3, 0, -16384, 3, 0, 0    ; seg 3
    .dw 7, 4, -16384, 7, 0, 0    ; seg 4
    .dw 4, 5, 0, 4, 0, 0    ; seg 5
    .dw 5, 6, 16384, 5, 0, 0    ; seg 6
    .dw 6, 7, -32768, 6, 0, 0    ; seg 7

; --- Subsectors (8) ---
.define NUM_SSECTORS 8
bsp_subsectors:
    .dw 1, 0    ; ssector 0
    .dw 1, 1    ; ssector 1
    .dw 1, 2    ; ssector 2
    .dw 1, 3    ; ssector 3
    .dw 1, 4    ; ssector 4
    .dw 1, 5    ; ssector 5
    .dw 1, 6    ; ssector 6
    .dw 1, 7    ; ssector 7

; --- BSP Nodes (7) ---
.define NUM_NODES 7
.define ROOT_NODE 6
bsp_nodes:
    ; node 0: partition (0,1024)+(0,-1024)
    .dw 0, 1024, 0, -1024
    .dw 1024, 0, 0, 0    ; right bbox
    .dw 640, 384, 384, 384    ; left bbox
    .dw 32771, 32772    ; children
    ; node 1: partition (640,384)+(0,256)
    .dw 640, 384, 0, 256
    .dw 640, 384, 640, 640    ; right bbox
    .dw 640, 640, 384, 640    ; left bbox
    .dw 32774, 32775    ; children
    ; node 2: partition (384,384)+(256,0)
    .dw 384, 384, 256, 0
    .dw 384, 384, 384, 640    ; right bbox
    .dw 640, 384, 384, 640    ; left bbox
    .dw 32773, 1    ; children
    ; node 3: partition (384,640)+(0,-256)
    .dw 384, 640, 0, -256
    .dw 1024, 0, 0, 384    ; right bbox
    .dw 640, 384, 384, 640    ; left bbox
    .dw 0, 2    ; children
    ; node 4: partition (1024,1024)+(-1024,0)
    .dw 1024, 1024, -1024, 0
    .dw 1024, 1024, 0, 1024    ; right bbox
    .dw 1024, 0, 0, 640    ; left bbox
    .dw 32770, 3    ; children
    ; node 5: partition (1024,0)+(0,1024)
    .dw 1024, 0, 0, 1024
    .dw 1024, 0, 1024, 1024    ; right bbox
    .dw 1024, 0, 0, 1024    ; left bbox
    .dw 32769, 4    ; children
    ; node 6: partition (0,0)+(1024,0)
    .dw 0, 0, 1024, 0
    .dw 0, 0, 0, 1024    ; right bbox
    .dw 1024, 0, 0, 1024    ; left bbox
    .dw 32768, 5    ; children

; --- Sectors (1) ---
.define NUM_SECTORS 1
bsp_sectors:
    .dw 0, 128, 192    ; sector 0

; --- Linedefs (8) ---
.define NUM_LINEDEFS 8
bsp_linedefs:
    .dw 0, 1, 1, 0, 65535    ; line 0
    .dw 1, 2, 1, 1, 65535    ; line 1
    .dw 2, 3, 1, 2, 65535    ; line 2
    .dw 3, 0, 1, 3, 65535    ; line 3
    .dw 4, 5, 1, 4, 65535    ; line 4
    .dw 5, 6, 1, 5, 65535    ; line 5
    .dw 6, 7, 1, 6, 65535    ; line 6
    .dw 7, 4, 1, 7, 65535    ; line 7

; --- Sidedefs (8) ---
.define NUM_SIDEDEFS 8
bsp_sidedefs:
    .dw 0, 0, 0, 178    ; side 0 (WALL00)
    .dw 0, 0, 0, 178    ; side 1 (WALL00)
    .dw 0, 0, 0, 178    ; side 2 (WALL00)
    .dw 0, 0, 0, 178    ; side 3 (WALL00)
    .dw 0, 0, 0, 128    ; side 4 (WALL01)
    .dw 0, 0, 0, 128    ; side 5 (WALL01)
    .dw 0, 0, 0, 128    ; side 6 (WALL01)
    .dw 0, 0, 0, 128    ; side 7 (WALL01)

