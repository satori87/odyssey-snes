/* ============================================
 * Doom-SNES style raycaster (IRQ-driven DMA)
 * 65816: DDA raycasting + input handling
 * GSU: pixel plotting only (reads pre-computed column data)
 *
 * Architecture:
 *   1. 65816 handles d-pad input (rotation, movement with collision)
 *   2. 65816 runs DDA raycaster for 20 columns (8px wide each)
 *   3. For each column, compute drawStart, drawEnd, wallColor
 *   4. Write column data to GSU RAM at $70:0000 (60 bytes)
 *   5. Start GSU, wait for completion
 *   6. DMA happens automatically via Doom-style IRQ system:
 *      - Bottom IRQ (scanline 176): forced blank + DMA 12800 bytes
 *      - Top IRQ (scanline 47): re-enable display
 *      - Main loop syncs via waitDMADone() flag
 *
 * Optimizations vs previous version:
 *   - 20 rays instead of 40 (8px wide strips vs 4px)
 *   - Reciprocal lookup table eliminates fp_div in DDA
 *   - Precomputed cameraX values
 *   - Simplified sideDist using shift instead of full fp_mul
 * ============================================ */

#include <snes.h>
#include "../data/palettes.h"
#include "../data/tables.h"
#include "../data/map.h"

#define SCREEN_W  160
#define SCREEN_H  80
#define HALF_H    40
#define NUM_COLS  20
#define COL_W     8
#define NUM_TILES 200
#define MAX_STEPS 24

/* Movement speed in 8.8 fixed point */
#define MOVE_SPEED 20       /* ~0.078 per frame */
#define ROT_SPEED  4        /* angle increment per frame */

/* Joypad bit masks */
#define PAD_RIGHT  0x0100
#define PAD_LEFT   0x0200
#define PAD_DOWN   0x0400
#define PAD_UP     0x0800
#define PAD_B      0x8000
#define PAD_A      0x0080

/* External assembly functions (in data.asm) */
extern void initMode7Display(void);
extern void initGSU(void);
extern void startGSU(void);
extern void disableNMI(void);
extern void setupIRQ(void);
extern void waitDMADone(void);
extern u16  readJoypad(void);
extern void writeColumnData(void);

/* Column data: 20 columns x 3 bytes = 60 bytes
 * Written by C, copied to $70:0000 by writeColumnData() */
u8 columnData[60];

/* Player state (8.8 fixed point) */
s16 posX;           /* position X */
s16 posY;           /* position Y */
s16 dirX;           /* direction vector X */
s16 dirY;           /* direction vector Y */
s16 planeX;         /* camera plane X */
s16 planeY;         /* camera plane Y */
u8  playerAngle;    /* 0-255, indexes sin/cos tables */

/* ============================================
 * Reciprocal lookup table (eliminates fp_div)
 * recip_table[n] = 65536 / n (clamped to 0x7FFF)
 * Used as: deltaDist = recip_table[|rayDir|]
 * Since 1.0/rayDir in 8.8 = 256/rayDir = (65536/rayDir) >> 8,
 * but we want |256/rayDir| in 8.8 = 65536/|rayDir|.
 * ============================================ */
const u16 recip_table[256] = {
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

/* Precomputed cameraX values for 20 columns
 * cameraX = (col * 512 / 20) - 256, in 8.8 fixed point */
const s16 cameraX_table[20] = {
    -256, -231, -205, -180, -154, -128, -103, -77, -52, -26,
    0, 25, 51, 76, 102, 128, 153, 179, 204, 230
};

/* ============================================
 * Fixed-point 8.8 multiply: (a * b) >> 8
 * Decomposed into 8-bit partial products
 * (avoids 32-bit multiply which 65816 can't do natively)
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
 * Fast reciprocal lookup for deltaDist calculation
 * Returns |256 / val| in 8.8 fixed point
 * Uses recip_table for values 1..255, handles
 * larger values by decomposition.
 * ============================================ */
s16 fast_recip(s16 val) {
    u16 uv;
    u16 result;

    if (val < 0) val = -val;
    uv = (u16)val;

    if (uv == 0) return 0x7FFF;

    /* For small values (1-255), direct table lookup */
    if (uv < 256) {
        return (s16)recip_table[uv];
    }

    /* For larger values (256+), the result is < 256 (< 1.0 in 8.8).
     * recip = 65536 / uv. Since uv >= 256, result <= 256.
     * Use integer division directly. */
    result = (u16)(65535u / uv);
    return (s16)result;
}

/* ============================================
 * Fast sideDist calculation using shift approximation
 * sideDist = (frac * deltaDist) >> 8
 * frac is 0-255 (fractional part of player position)
 * deltaDist is in 8.8 fixed point
 * This avoids the full fp_mul decomposition.
 * ============================================ */
s16 fast_frac_mul(u16 frac, s16 deltaDist) {
    u8 frac8;
    u8 dhi, dlo;
    u16 ud, result;

    /* frac is 0..255 (always positive) */
    /* deltaDist is always positive (absolute value from recip) */
    ud = (u16)deltaDist;
    dhi = (u8)(ud >> 8);
    dlo = (u8)(ud & 0xFF);
    frac8 = (u8)(frac & 0xFF);

    /* (frac * deltaDist) >> 8
     * = (frac * (dhi*256 + dlo)) >> 8
     * = frac * dhi + (frac * dlo) >> 8 */
    result = (u16)frac8 * (u16)dhi;
    result += ((u16)frac8 * (u16)dlo) >> 8;
    return (s16)result;
}

/* ============================================
 * Absolute value for s16
 * ============================================ */
s16 fp_abs(s16 x) {
    if (x < 0) return -x;
    return x;
}

/* ============================================
 * Initialize player state
 * ============================================ */
void initPlayer(void) {
    /* Start at position (2.5, 2.5) facing east (angle=0) */
    posX = (2 << 8) | 128;     /* 2.5 in 8.8 */
    posY = (2 << 8) | 128;     /* 2.5 in 8.8 */
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
u8 isWall(s16 x, s16 y) {
    u8 mx, my;
    mx = (u8)(x >> 8);
    my = (u8)(y >> 8);
    if (mx >= MAP_W || my >= MAP_H) return 1;
    return world_map[my][mx] != 0 ? 1 : 0;
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
        if (!isWall(newX, posY)) {
            posX = newX;
        }
        if (!isWall(posX, newY)) {
            posY = newY;
        }
    }

    /* Down: move backward */
    if (pad & PAD_DOWN) {
        moveX = fp_mul(dirX, MOVE_SPEED);
        moveY = fp_mul(dirY, MOVE_SPEED);
        newX = posX - moveX;
        newY = posY - moveY;
        if (!isWall(newX, posY)) {
            posX = newX;
        }
        if (!isWall(posX, newY)) {
            posY = newY;
        }
    }

    /* B button: strafe left */
    if (pad & PAD_B) {
        moveX = fp_mul(planeX, MOVE_SPEED);
        moveY = fp_mul(planeY, MOVE_SPEED);
        newX = posX - moveX;
        newY = posY - moveY;
        if (!isWall(newX, posY)) {
            posX = newX;
        }
        if (!isWall(posX, newY)) {
            posY = newY;
        }
    }

    /* A button: strafe right */
    if (pad & PAD_A) {
        moveX = fp_mul(planeX, MOVE_SPEED);
        moveY = fp_mul(planeY, MOVE_SPEED);
        newX = posX + moveX;
        newY = posY + moveY;
        if (!isWall(newX, posY)) {
            posX = newX;
        }
        if (!isWall(posX, newY)) {
            posY = newY;
        }
    }
}

/* ============================================
 * DDA Raycaster -- compute column data for 20 columns
 * Optimized: reciprocal LUT replaces fp_div,
 * fast_frac_mul replaces fp_mul for sideDist,
 * precomputed cameraX values.
 * ============================================ */
void castRays(void) {
    u8 col;
    s16 cameraX;
    s16 rayDirX, rayDirY;
    s16 deltaDistX, deltaDistY;
    s16 sideDistX, sideDistY;
    s16 stepX, stepY;
    s16 mapX, mapY;
    s16 perpDist;
    u8 side;
    u8 hit;
    u8 steps;
    s16 lineHeight;
    s16 half;
    s16 drawStart, drawEnd;
    u8 wallColor;
    u16 idx;
    u16 fracX, fracY;

    for (col = 0; col < NUM_COLS; col++) {
        /* Precomputed cameraX from table */
        cameraX = cameraX_table[col];

        /* rayDir = dir + plane * cameraX */
        rayDirX = dirX + fp_mul(planeX, cameraX);
        rayDirY = dirY + fp_mul(planeY, cameraX);

        /* Map position (integer part of player pos) */
        mapX = posX >> 8;
        mapY = posY >> 8;

        /* deltaDist = |256 / rayDir| using reciprocal table
         * This replaces the expensive fp_div calls */
        deltaDistX = fast_recip(rayDirX);
        deltaDistY = fast_recip(rayDirY);

        /* Step direction and initial sideDist
         * Using fast_frac_mul instead of fp_mul */
        if (rayDirX < 0) {
            stepX = -1;
            /* frac = posX - mapX*256 (fractional part, 0..255) */
            fracX = (u16)(posX - (mapX << 8));
            sideDistX = fast_frac_mul(fracX, deltaDistX);
        } else {
            stepX = 1;
            /* frac = (mapX+1)*256 - posX */
            fracX = (u16)(((mapX + 1) << 8) - posX);
            sideDistX = fast_frac_mul(fracX, deltaDistX);
        }

        if (rayDirY < 0) {
            stepY = -1;
            fracY = (u16)(posY - (mapY << 8));
            sideDistY = fast_frac_mul(fracY, deltaDistY);
        } else {
            stepY = 1;
            fracY = (u16)(((mapY + 1) << 8) - posY);
            sideDistY = fast_frac_mul(fracY, deltaDistY);
        }

        /* DDA loop */
        hit = 0;
        side = 0;
        for (steps = 0; steps < MAX_STEPS; steps++) {
            /* Jump to next map square */
            if (sideDistX < sideDistY) {
                sideDistX += deltaDistX;
                mapX += stepX;
                side = 0;
            } else {
                sideDistY += deltaDistY;
                mapY += stepY;
                side = 1;
            }

            /* Check bounds */
            if (mapX < 0 || mapX >= MAP_W || mapY < 0 || mapY >= MAP_H) {
                break;
            }

            /* Check for wall hit */
            if (world_map[(u8)mapY][(u8)mapX] != 0) {
                hit = 1;
                break;
            }
        }

        /* Compute perpendicular distance */
        if (hit) {
            if (side == 0) {
                perpDist = sideDistX - deltaDistX;
            } else {
                perpDist = sideDistY - deltaDistY;
            }
        } else {
            perpDist = 0x0400;  /* 4.0 in 8.8 (far away) */
        }

        /* Clamp perpDist to minimum */
        if (perpDist < 1) perpDist = 1;

        /* Compute wall height from perpDist
         * lineHeight = SCREEN_H * 256 / perpDist = 20480 / perpDist
         * Use recip_table for perpDist < 256, direct division otherwise */
        if ((u16)perpDist < 256) {
            /* perpDist < 1.0 in 8.8 -- very close
             * lineHeight = 80 * recip_table[perpDist] >> 8
             * But recip_table values can be huge, so just clamp to SCREEN_H */
            lineHeight = SCREEN_H;
        } else {
            /* perpDist >= 256 (>= 1.0): safe integer division */
            lineHeight = (s16)(20480u / (u16)perpDist);
        }

        /* Clamp lineHeight to screen height */
        if (lineHeight > SCREEN_H) lineHeight = SCREEN_H;
        if (lineHeight < 0) lineHeight = 0;

        /* Compute drawStart and drawEnd */
        half = lineHeight >> 1;
        drawStart = HALF_H - half;
        drawEnd = HALF_H + half - 1;

        if (drawStart < 0) drawStart = 0;
        if (drawEnd >= SCREEN_H) drawEnd = SCREEN_H - 1;
        if (drawEnd < drawStart) drawEnd = drawStart;

        /* Wall color: side 0 = bright (5), side 1 = dark (4) */
        wallColor = (side == 0) ? 5 : 4;

        /* Store in column data array */
        idx = (u16)col * 3;
        columnData[idx]     = (u8)drawStart;
        columnData[idx + 1] = (u8)drawEnd;
        columnData[idx + 2] = wallColor;
    }
}

/* ============================================
 * Main loop -- Doom-style IRQ-driven DMA
 *
 * Flow:
 *   1. handleInput() -- read joypad, update player
 *   2. castRays() -- DDA raycaster computes column data
 *   3. writeColumnData() -- copy 60 bytes to $70:0000
 *   4. startGSU() -- GSU renders pixels into $70:0400
 *   5. waitDMADone() -- spin until bottom IRQ has DMA'd frame
 *   6. Loop back (IRQ system handles DMA automatically)
 * ============================================ */
int main(void) {
    initMode7Display();
    initGSU();
    disableNMI();
    initPlayer();

    /* First frame: render initial data before enabling IRQs */
    castRays();
    writeColumnData();
    startGSU();

    /* Enable Doom-style IRQ system */
    setupIRQ();

    while (1) {
        /* Wait for previous frame's DMA to complete */
        waitDMADone();

        /* Process input and render next frame */
        handleInput();
        castRays();
        writeColumnData();
        startGSU();
        /* DMA will happen automatically when bottom IRQ fires */
    }

    return 0;
}
