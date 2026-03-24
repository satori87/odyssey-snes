/* ============================================
 * SNES Raycaster — 65816 CPU-only DDA version
 *
 * ALL raycasting runs on the 65816 (no SuperFX).
 * Portable DDA algorithm ported from the GSU version.
 *
 * 65816 responsibilities:
 *   - Joypad input
 *   - Player angle / rotation
 *   - Direction + plane vector computation (sin/cos tables)
 *   - Movement with collision detection
 *   - DDA raycasting (112 columns)
 *   - Fill column arrays for assembly renderer
 * ============================================ */

/* Type definitions (replaces PVSnesLib's snes.h) */
typedef unsigned char u8;
typedef signed char s8;
typedef unsigned short u16;
typedef signed short s16;
typedef unsigned long long u32;
typedef signed long long s32;

#include "../data/palettes.h"
#include "../data/tables.h"
#include "../data/map.h"
#include "../data/bsp_tables.h"

#define SCREEN_W  112
#define SCREEN_H  80
#define HALF_H    40
#define NUM_COLS  112

#define MAX_STEPS 24

/* Movement speed in 8.8 fixed point */
#define MOVE_SPEED 60       /* ~0.234 per frame */
#define ROT_SPEED  8        /* angle increment per frame */

/* Wall color indices */
#define WALL_BRIGHT 5
#define WALL_DARK   4

/* Joypad bit masks */
#define PAD_RIGHT  0x0100
#define PAD_LEFT   0x0200
#define PAD_DOWN   0x0400
#define PAD_UP     0x0800
#define PAD_B      0x8000
#define PAD_A      0x0080

/* External assembly functions (in data.asm) */
extern void initMode7Display(void);
extern void disableNMI(void);
extern u16  readJoypad(void);
extern void renderColumns(void);
extern void clearFramebuffer(void);
extern void dmaFramebuffer(void);
extern void fillTestWall(void);
extern void initColumnArrays(void);
extern void renderOneWall(void);
extern void renderAllWalls(void);
extern void testWMADD(void);

/* Player state (8.8 fixed point) */
s16 posX;           /* position X */
s16 posY;           /* position Y */
s16 dirX;           /* direction vector X */
s16 dirY;           /* direction vector Y */
s16 planeX;         /* camera plane X */
s16 planeY;         /* camera plane Y */
u8  playerAngle;    /* 0-255, indexes sin/cos tables */

/* Column arrays — filled by castAllRays(), read by renderColumns() */
u8 colDrawStart[112];
u8 colDrawEnd[112];
u8 colWallColor[112];

/* ============================================
 * cameraX table: maps column index to camera-space X
 * cameraX[col] = 2*col/NUM_COLS - 1, in signed 8.8
 * Range: -256 (left edge) to ~251 (right edge)
 * ============================================ */
const s16 cameraX_tbl[112] = {
    -256, -251, -247, -242, -238, -233, -229, -224,
    -220, -215, -211, -206, -202, -197, -193, -188,
    -184, -179, -175, -170, -165, -161, -156, -152,
    -147, -143, -138, -134, -129, -125, -120, -116,
    -111, -107, -102, -98, -93, -89, -84, -79,
    -75, -70, -66, -61, -57, -52, -48, -43,
    -39, -34, -30, -25, -21, -16, -12, -7,
    -2, 2, 7, 12, 16, 21, 25, 30,
    34, 39, 43, 48, 52, 57, 61, 66,
    70, 75, 79, 84, 89, 93, 98, 102,
    107, 111, 116, 120, 125, 129, 134, 138,
    143, 147, 152, 156, 161, 165, 170, 175,
    179, 184, 188, 193, 197, 202, 206, 211,
    215, 220, 224, 229, 233, 238, 242, 247
};

/* ============================================
 * Reciprocal table: recip_tbl[i] = 65536/i (unsigned 8.8)
 * Entry 0,1,2 capped at 32767 to avoid overflow.
 * Used for deltaDist = recip(|rayDir|).
 * ============================================ */
const u16 recip_tbl[256] = {
    32767, 32767, 32767, 21845, 16384, 13107, 10922, 9362,
    8192, 7281, 6553, 5957, 5461, 5041, 4681, 4369,
    4096, 3855, 3640, 3449, 3276, 3120, 2978, 2849,
    2730, 2621, 2520, 2427, 2340, 2259, 2184, 2114,
    2048, 1985, 1927, 1872, 1820, 1771, 1724, 1680,
    1638, 1598, 1560, 1524, 1489, 1456, 1424, 1394,
    1365, 1337, 1310, 1285, 1260, 1236, 1213, 1191,
    1170, 1149, 1129, 1110, 1092, 1074, 1057, 1040,
    1024, 1008, 992, 978, 963, 949, 936, 923,
    910, 897, 885, 873, 862, 851, 840, 829,
    819, 809, 799, 789, 780, 771, 762, 753,
    744, 736, 728, 720, 712, 704, 697, 689,
    682, 675, 668, 661, 655, 648, 642, 636,
    630, 624, 618, 612, 606, 601, 595, 590,
    585, 579, 574, 569, 564, 560, 555, 550,
    546, 541, 537, 532, 528, 524, 520, 516,
    512, 508, 504, 500, 496, 492, 489, 485,
    481, 478, 474, 471, 468, 464, 461, 458,
    455, 451, 448, 445, 442, 439, 436, 434,
    431, 428, 425, 422, 420, 417, 414, 412,
    409, 407, 404, 402, 399, 397, 394, 392,
    390, 387, 385, 383, 381, 378, 376, 374,
    372, 370, 368, 366, 364, 362, 360, 358,
    356, 354, 352, 350, 348, 346, 344, 343,
    341, 339, 337, 336, 334, 332, 330, 329,
    327, 326, 324, 322, 321, 319, 318, 316,
    315, 313, 312, 310, 309, 307, 306, 304,
    303, 302, 300, 299, 297, 296, 295, 293,
    292, 291, 289, 288, 287, 286, 284, 283,
    282, 281, 280, 278, 277, 276, 275, 274,
    273, 271, 270, 269, 268, 267, 266, 265,
    264, 263, 262, 261, 260, 259, 258, 257
};

/* ============================================
 * Height table: height_tbl[i] = SCREEN_H / (perpDist>>2)
 * Maps perpendicular distance index to wall column height.
 * Index = perpDist >> 2, clamped 1..255.
 * Entries 0..19 capped at SCREEN_H (close walls fill screen).
 * ============================================ */
const u8 height_tbl[256] = {
    80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
    80, 80, 80, 80, 80, 78, 76, 74, 72, 70, 69, 67, 66, 64, 63, 61,
    60, 59, 58, 57, 56, 55, 54, 53, 52, 51, 50, 49, 48, 48, 47, 46,
    45, 45, 44, 43, 43, 42, 42, 41, 40, 40, 39, 39, 38, 38, 37, 37,
    36, 36, 35, 35, 35, 34, 34, 33, 33, 33, 32, 32, 32, 31, 31, 31,
    30, 30, 30, 29, 29, 29, 29, 28, 28, 28, 28, 27, 27, 27, 27, 26,
    26, 26, 26, 25, 25, 25, 25, 25, 24, 24, 24, 24, 24, 23, 23, 23,
    23, 23, 22, 22, 22, 22, 22, 22, 21, 21, 21, 21, 21, 21, 20, 20,
    20, 20, 20, 20, 20, 19, 19, 19, 19, 19, 19, 19, 19, 18, 18, 18,
    18, 18, 18, 18, 18, 17, 17, 17, 17, 17, 17, 17, 17, 17, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 11, 11, 11, 11,
    11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 10, 10, 10,
    10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10
};

/* ============================================
 * Fixed-point 8.8 multiply: (a * b) >> 8
 * Only used for movement (~8 calls/frame, not perf critical)
 * ============================================ */
s16 fp_mul(s16 a, s16 b) {
    u8 neg, al, ah, bl, bh;
    u16 ua, ub, result;
    neg = 0;
    if (a < 0) { a = -a; neg = 1; }
    if (b < 0) { b = -b; neg ^= 1; }
    ua = (u16)a; ub = (u16)b;
    al = (u8)(ua & 0xFF); ah = (u8)(ua >> 8);
    bl = (u8)(ub & 0xFF); bh = (u8)(ub >> 8);
    result = ((u16)ah * (u16)bh) << 8;
    result += (u16)ah * (u16)bl;
    result += (u16)al * (u16)bh;
    result += ((u16)al * (u16)bl) >> 8;
    if (neg) return -(s16)result;
    return (s16)result;
}

/* ============================================
 * Unsigned fractional multiply: (frac * val) >> 8
 * frac is 0..256, val is unsigned 8.8.
 * Used for initial sideDist computation.
 * ============================================ */
u16 frac_mul(u16 frac, u16 val) {
    u8 vhi, vlo;
    u16 result;
    vhi = (u8)(val >> 8);
    vlo = (u8)(val & 0xFF);
    result = (u16)((u16)(frac * vlo) >> 8);
    result += (u16)(frac * vhi);
    return result;
}

/* ============================================
 * Initialize player state
 * ============================================ */
void initPlayer(void) {
    /* Start at position (7.5, 5.0) facing east — close to east wall */
    posX = (7 << 8) | 128;     /* 7.5 in 8.8 */
    posY = (5 << 8);           /* 5.0 in 8.8 */
    playerAngle = 0;

    /* Direction and camera plane from angle */
    dirX = cos_table[playerAngle];
    dirY = sin_table[playerAngle];
    /* Camera plane perpendicular to dir, scaled by FOV (~0.66) */
    /* 0.66 * 256 = 169 in 8.8 */
    planeX = fp_mul(-sin_table[playerAngle], 169);
    planeY = fp_mul(cos_table[playerAngle], 169);
}

/* Update direction and plane vectors from current angle */
void updateVectors(void) {
    dirX = cos_table[playerAngle];
    dirY = sin_table[playerAngle];
    planeX = fp_mul(-sin_table[playerAngle], 169);
    planeY = fp_mul(cos_table[playerAngle], 169);
}

/* Check if map position is a wall */
/* Simple wall check: is map cell at (x,y) solid? */
u8 isWall(s16 x, s16 y) {
    u16 mx, my, idx;
    if (x < 0 || y < 0) return 1;
    mx = (u16)(x >> 8);
    my = (u16)(y >> 8);
    if (mx >= MAP_W || my >= MAP_H) return 1;
    /* Flatten 2D access: my*10 + mx using shifts+adds (no multiply) */
    idx = (my << 3) + (my << 1) + mx;  /* my*8 + my*2 + mx = my*10 + mx */
    if (((u8*)world_map)[idx] != 0) return 1;
    return 0;
}

/* ============================================
 * Handle d-pad input
 * ============================================ */
void handleInput(void) {
    u16 pad;
    s16 newX, newY;
    s16 moveX, moveY;

    pad = readJoypad();

    /* Left/Right: rotate */
    if (pad & PAD_LEFT) {
        playerAngle -= ROT_SPEED;
        updateVectors();
    }
    if (pad & PAD_RIGHT) {
        playerAngle += ROT_SPEED;
        updateVectors();
    }

    /* Up: move forward */
    if (pad & PAD_UP) {
        moveX = fp_mul(dirX, MOVE_SPEED);
        moveY = fp_mul(dirY, MOVE_SPEED);
        newX = posX + moveX;
        newY = posY + moveY;
        if (!isWall(newX, newY)) {
            posX = newX;
            posY = newY;
        } else if (!isWall(newX, posY)) {
            posX = newX;
        } else if (!isWall(posX, newY)) {
            posY = newY;
        }
    }

    /* Down: move backward */
    if (pad & PAD_DOWN) {
        moveX = fp_mul(dirX, MOVE_SPEED);
        moveY = fp_mul(dirY, MOVE_SPEED);
        newX = posX - moveX;
        newY = posY - moveY;
        if (!isWall(newX, newY)) {
            posX = newX;
            posY = newY;
        } else if (!isWall(newX, posY)) {
            posX = newX;
        } else if (!isWall(posX, newY)) {
            posY = newY;
        }
    }

    /* B button: strafe left */
    if (pad & PAD_B) {
        moveX = fp_mul(planeX, MOVE_SPEED);
        moveY = fp_mul(planeY, MOVE_SPEED);
        newX = posX - moveX;
        newY = posY - moveY;
        if (!isWall(newX, newY)) {
            posX = newX;
            posY = newY;
        } else if (!isWall(newX, posY)) {
            posX = newX;
        } else if (!isWall(posX, newY)) {
            posY = newY;
        }
    }

    /* A button: strafe right */
    if (pad & PAD_A) {
        moveX = fp_mul(planeX, MOVE_SPEED);
        moveY = fp_mul(planeY, MOVE_SPEED);
        newX = posX + moveX;
        newY = posY + moveY;
        if (!isWall(newX, newY)) {
            posX = newX;
            posY = newY;
        } else if (!isWall(newX, posY)) {
            posX = newX;
        } else if (!isWall(posX, newY)) {
            posY = newY;
        }
    }
}

/* ============================================
 * DDA raycaster — cast all 112 rays
 *
 * Port of GSU DDA algorithm to 65816 C.
 * For each column, compute ray direction, step through
 * the grid via DDA, compute perpendicular distance,
 * then wall height via lookup table.
 *
 * Results stored in colDrawStart[], colDrawEnd[],
 * colWallColor[] for the assembly renderer.
 * ============================================ */
void castAllRays(void) {
    u16 col;
    s16 cameraX;
    s16 rayDirX, rayDirY;
    u16 absRayX, absRayY;
    u16 deltaDistX, deltaDistY;
    s16 sideDistX, sideDistY;
    s16 stepX, stepY;
    u16 mapX, mapY;
    u16 fracX, fracY;
    u8 side;
    u8 hit;
    u8 steps;
    u16 idx;
    u8 mapCell;
    s16 perpDist;
    u16 htIdx;
    u8 lineHeight;
    s16 half;
    s16 drawStart, drawEnd;

    for (col = 0; col < NUM_COLS; col++) {

        /* --- Step 1: Compute ray direction --- */
        cameraX = cameraX_tbl[col];
        rayDirX = dirX + fp_mul(planeX, cameraX);
        rayDirY = dirY + fp_mul(planeY, cameraX);

        /* --- Step 2: deltaDist = recip(|rayDir|) --- */

        /* deltaDistX */
        absRayX = (u16)(rayDirX < 0 ? -rayDirX : rayDirX);
        if (absRayX == 0) {
            deltaDistX = 32767;
        } else if (absRayX < 256) {
            deltaDistX = recip_tbl[absRayX];
        } else {
            /* Large rayDir: halve, look up, halve result */
            absRayX >>= 1;
            if (absRayX < 256) {
                deltaDistX = recip_tbl[absRayX] >> 1;
            } else {
                deltaDistX = 1;
            }
        }

        /* deltaDistY */
        absRayY = (u16)(rayDirY < 0 ? -rayDirY : rayDirY);
        if (absRayY == 0) {
            deltaDistY = 32767;
        } else if (absRayY < 256) {
            deltaDistY = recip_tbl[absRayY];
        } else {
            absRayY >>= 1;
            if (absRayY < 256) {
                deltaDistY = recip_tbl[absRayY] >> 1;
            } else {
                deltaDistY = 1;
            }
        }

        /* --- Step 3: step directions and initial sideDist --- */
        mapX = (u16)(posX >> 8);
        mapY = (u16)(posY >> 8);

        if (rayDirX < 0) {
            stepX = -1;
            fracX = (u16)(posX & 0xFF);        /* distance to left edge */
            sideDistX = (s16)frac_mul(fracX, deltaDistX);
        } else {
            stepX = 1;
            fracX = 256 - (u16)(posX & 0xFF);  /* distance to right edge */
            sideDistX = (s16)frac_mul(fracX, deltaDistX);
        }

        if (rayDirY < 0) {
            stepY = -1;
            fracY = (u16)(posY & 0xFF);
            sideDistY = (s16)frac_mul(fracY, deltaDistY);
        } else {
            stepY = 1;
            fracY = 256 - (u16)(posY & 0xFF);
            sideDistY = (s16)frac_mul(fracY, deltaDistY);
        }

        /* --- Step 4: DDA loop --- */
        side = 0;
        hit = 0;

        for (steps = 0; steps < MAX_STEPS; steps++) {
            /* Step to next grid line */
            if ((u16)sideDistX < (u16)sideDistY) {
                sideDistX += (s16)deltaDistX;
                mapX += stepX;
                side = 0;
            } else {
                sideDistY += (s16)deltaDistY;
                mapY += stepY;
                side = 1;
            }

            /* Bounds check */
            if (mapX >= MAP_W || mapY >= MAP_H) break;

            /* Map lookup: world_map[mapY][mapX] */
            idx = (mapY << 3) + (mapY << 1) + mapX;
            mapCell = ((u8*)world_map)[idx];
            if (mapCell != 0) {
                hit = 1;
                break;
            }
        }

        /* --- Step 5: perpendicular distance --- */
        if (hit) {
            if (side == 0) {
                perpDist = sideDistX - (s16)deltaDistX;
            } else {
                perpDist = sideDistY - (s16)deltaDistY;
            }
        } else {
            perpDist = 0x0400;  /* 4.0 in 8.8 (max distance) */
        }

        /* Clamp minimum distance to avoid spikes */
        if (perpDist < 64) perpDist = 64;

        /* --- Step 6: wall height from lookup table --- */
        if (perpDist < 256) {
            /* Very close: cap height */
            lineHeight = SCREEN_H - 4;
        } else {
            htIdx = (u16)perpDist >> 2;
            if (htIdx == 0) htIdx = 1;
            if (htIdx > 255) htIdx = 255;
            lineHeight = height_tbl[htIdx];
            if (lineHeight > SCREEN_H - 4) lineHeight = SCREEN_H - 4;
        }

        /* --- Compute drawStart / drawEnd --- */
        half = (s16)(lineHeight >> 1);
        drawStart = HALF_H - half;
        drawEnd = HALF_H + half - 1;

        /* Clamp to screen */
        if (drawStart < 0) drawStart = 0;
        if (drawEnd >= SCREEN_H) drawEnd = SCREEN_H - 1;
        if (drawEnd < drawStart) drawEnd = drawStart;

        /* --- Step 7: Store results --- */
        colDrawStart[col] = (u8)drawStart;
        colDrawEnd[col] = (u8)drawEnd;

        /* Wall color: bright (5) for X-side, dark (4) for Y-side */
        if (hit) {
            if (side == 0) {
                colWallColor[col] = WALL_BRIGHT;
            } else {
                colWallColor[col] = WALL_DARK;
            }
        } else {
            colWallColor[col] = 0;
        }
    }
}

/* ============================================
 * Main loop — 65816 CPU-only raycasting
 *
 * Flow:
 *   1. handleInput() — read joypad, update player
 *   2. castAllRays() — DDA raycaster fills column arrays
 *   3. renderColumns() — assembly fills framebuffer from columns
 *   4. dmaFramebuffer() — DMA framebuffer to VRAM
 *   5. Loop
 * ============================================ */
int main(void) {
    initMode7Display();
    disableNMI();
    initPlayer();

    renderAllWalls();

    while (1) {
        clearFramebuffer();
        renderColumns();
        dmaFramebuffer();
    }

    return 0;
}
