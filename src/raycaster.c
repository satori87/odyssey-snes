/* ============================================
 * Doom-SNES style raycaster
 * 65816: DDA raycasting + input handling
 * GSU: pixel plotting only (reads pre-computed column data)
 *
 * Architecture:
 *   1. 65816 handles d-pad input (rotation, movement with collision)
 *   2. 65816 runs DDA raycaster for 40 columns
 *   3. For each column, compute drawStart, drawEnd, wallColor
 *   4. Write column data to GSU RAM at $70:0000 (120 bytes)
 *   5. Start GSU, wait for completion
 *   6. DMA tile framebuffer from $70:0400 to VRAM
 * ============================================ */

#include <snes.h>
#include "../data/palettes.h"
#include "../data/tables.h"
#include "../data/map.h"

#define SCREEN_W  160
#define SCREEN_H  80
#define HALF_H    40
#define NUM_COLS  40
#define COL_W     4
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
extern void initMode3Display(void);
extern void initGSU(void);
extern void startGSU(void);
extern void disableNMI(void);
extern void waitVBlankSimple(void);
extern void restoreDisplayRegs(void);
extern u16  readJoypad(void);
extern void writeColumnData(void);
extern void dmaFramebuffer(void);

/* Column data: 40 columns x 3 bytes = 120 bytes
 * Written by C, copied to $70:0000 by writeColumnData() */
u8 columnData[120];

/* Player state (8.8 fixed point) */
s16 posX;           /* position X */
s16 posY;           /* position Y */
s16 dirX;           /* direction vector X */
s16 dirY;           /* direction vector Y */
s16 planeX;         /* camera plane X */
s16 planeY;         /* camera plane Y */
u8  playerAngle;    /* 0-255, indexes sin/cos tables */

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
 * Fixed-point 8.8 divide: (a << 8) / b
 * ============================================ */
s16 fp_div(s16 a, s16 b) {
    u8 neg;
    u16 ua, ub, qhi, rhi, qlo;
    neg = 0;
    if (a < 0) { a = -a; neg = 1; }
    if (b < 0) { b = -b; neg ^= 1; }
    ua = (u16)a; ub = (u16)b;
    if (ub == 0) return 0x7FFF;
    qhi = ua / ub;
    rhi = ua % ub;
    if (rhi > 255) qlo = ((rhi << 7) / ub) << 1;
    else qlo = (rhi << 8) / ub;
    ua = (qhi << 8) + qlo;
    if (neg) return -(s16)ua;
    return (s16)ua;
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
 * DDA Raycaster -- compute column data for 40 columns
 * Based on lodev.org raycasting tutorial
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
    u16 distInt;
    u16 idx;
    s16 fracX, fracY;

    for (col = 0; col < NUM_COLS; col++) {
        /* cameraX = (2 * col / NUM_COLS - 1) in 8.8
         * = col * 512 / 40 - 256
         * Simplified: col*13 - 256 (approximate)
         * More precise: col * 12 + col/2 + col/5 ... let's just do it */
        /* cameraX = ((col * 512) / NUM_COLS) - 256 */
        /* To avoid overflow: col * 512 = col << 9 */
        /* col ranges 0..39, col*512 = 0..19968 -- fits in u16 */
        cameraX = (s16)(((u16)col * 512) / NUM_COLS) - 256;

        /* rayDir = dir + plane * cameraX */
        rayDirX = dirX + fp_mul(planeX, cameraX);
        rayDirY = dirY + fp_mul(planeY, cameraX);

        /* Map position (integer part of player pos) */
        mapX = posX >> 8;
        mapY = posY >> 8;

        /* deltaDist = |1 / rayDir| in 8.8
         * = 256 / |rayDir| (since 1.0 = 256 in 8.8)
         * We use fp_div for precision */
        if (rayDirX == 0) {
            deltaDistX = 0x7FFF;
        } else {
            deltaDistX = fp_abs(fp_div(256, rayDirX));
        }
        if (rayDirY == 0) {
            deltaDistY = 0x7FFF;
        } else {
            deltaDistY = fp_abs(fp_div(256, rayDirY));
        }

        /* Step direction and initial sideDist */
        if (rayDirX < 0) {
            stepX = -1;
            /* sideDist = (pos - map) * deltaDist */
            fracX = posX - (mapX << 8);
            sideDistX = fp_mul(fracX, deltaDistX);
        } else {
            stepX = 1;
            /* sideDist = (map + 1 - pos) * deltaDist */
            fracX = ((mapX + 1) << 8) - posX;
            sideDistX = fp_mul(fracX, deltaDistX);
        }

        if (rayDirY < 0) {
            stepY = -1;
            fracY = posY - (mapY << 8);
            sideDistY = fp_mul(fracY, deltaDistY);
        } else {
            stepY = 1;
            fracY = ((mapY + 1) << 8) - posY;
            sideDistY = fp_mul(fracY, deltaDistY);
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

        /* Clamp perpDist to minimum of 1 */
        if (perpDist < 1) perpDist = 1;

        /* Compute wall height from perpDist
         * lineHeight = SCREEN_H / (perpDist / 256)
         * = SCREEN_H * 256 / perpDist
         * = 20480 / perpDist
         * For integer approximation: */
        distInt = (u16)perpDist >> 8;
        if (distInt > 0) {
            lineHeight = (s16)(SCREEN_H / distInt);
        } else {
            /* perpDist < 1.0 -- very close, full height */
            lineHeight = SCREEN_H;
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
 * Main loop
 * ============================================ */
int main(void) {
    initMode3Display();
    initGSU();
    disableNMI();
    initPlayer();

    while (1) {
        /* Read input and update player position/angle */
        handleInput();

        /* Run DDA raycaster, fill columnData[] */
        castRays();

        /* Copy columnData to $70:0000 */
        writeColumnData();

        /* Start GSU pixel plotter and wait for completion */
        startGSU();

        /* Wait for VBlank, then DMA tile framebuffer to VRAM */
        waitVBlankSimple();
        dmaFramebuffer();
        restoreDisplayRegs();
    }

    return 0;
}
