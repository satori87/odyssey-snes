/* ============================================
 * Doom-SNES style raycaster (GSU DDA version)
 *
 * 65816 responsibilities (MINIMAL):
 *   - Joypad input
 *   - Player angle / rotation
 *   - Direction + plane vector computation (sin/cos tables)
 *   - Movement with collision detection
 *   - Write player state to $70:0000 (6 words)
 *   - Start GSU (which does ALL raycasting)
 *   - Wait for DMA (IRQ system)
 *
 * ALL raycasting math runs on the SuperFX GSU.
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

#define SCREEN_W  160
#define SCREEN_H  80
#define HALF_H    40
#define NUM_COLS  20
#define COL_W     8

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
extern void writePlayerState(void);

/* Player state (8.8 fixed point)
 * These are written to $70:0000-000B by writePlayerState() */
s16 posX;           /* position X */
s16 posY;           /* position Y */
s16 dirX;           /* direction vector X */
s16 dirY;           /* direction vector Y */
s16 planeX;         /* camera plane X */
s16 planeY;         /* camera plane Y */
u8  playerAngle;    /* 0-255, indexes sin/cos tables */

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
 * Main loop -- GSU DDA + IRQ-driven DMA
 *
 * Flow:
 *   1. handleInput() -- read joypad, update player
 *   2. writePlayerState() -- copy 12 bytes to $70:0000
 *   3. startGSU() -- GSU runs complete DDA raycaster
 *   4. waitDMADone() -- spin until IRQ has DMA'd frame
 *   5. Loop
 * ============================================ */
int main(void) {
    initMode7Display();
    initGSU();
    disableNMI();
    initPlayer();

    while (1) {
        handleInput();
        writePlayerState();
        startGSU();
        /* Manual DMA (bypass IRQ for now to verify GSU output) */
        waitVBlankSimple();
        dmaFramebuffer();
    }

    return 0;
}
