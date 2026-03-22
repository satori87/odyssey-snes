/* ============================================
 * BSP Renderer — 65816 side (Doom SNES style)
 *
 * 65816 responsibilities:
 *   - Joypad input
 *   - Player movement (world coordinates)
 *   - Write ViewX, ViewY, ViewAngle to $70:0000
 *   - Start GSU (which does BSP traversal + rendering)
 *   - DMA framebuffer
 *
 * ALL BSP traversal and rendering runs on the SuperFX GSU.
 * ============================================ */

typedef unsigned char u8;
typedef signed char s8;
typedef unsigned short u16;
typedef signed short s16;
typedef unsigned long long u32;
typedef signed long long s32;

#include "../data/palettes.h"
#include "../data/tables.h"

/* Movement speed in world units per frame */
#define MOVE_SPEED 16       /* world units per frame */
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
extern void setupIRQ(void);
extern void waitDMADone(void);
extern u16  readJoypad(void);
extern void writePlayerState(void);
extern void dmaFramebuffer(void);

/* Player state — world coordinates
 * These are written to $70:0000-0005 by writePlayerState() */
s16 posX;           /* world X (0-1024 for test map) */
s16 posY;           /* world Y (0-1024 for test map) */
u8  playerAngle;    /* 0-255, indexes sin/cos tables */

/* ============================================
 * Fixed-point 8.8 multiply (for movement only)
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
    /* Start at center of room (512, 512) facing east (angle=0) */
    posX = 200;
    posY = 200;
    playerAngle = 0;
}

/* ============================================
 * Handle d-pad input — direct world coordinate movement
 * ============================================ */
void handleInput(void) {
    u16 pad;
    s16 moveX, moveY;

    pad = readJoypad();

    /* Left/Right: rotate */
    if (pad & PAD_LEFT) {
        playerAngle -= ROT_SPEED;
    }
    if (pad & PAD_RIGHT) {
        playerAngle += ROT_SPEED;
    }

    /* Movement using sin/cos tables (8.8 format) */
    /* cos_table[angle] and sin_table[angle] are 8.8 values (-256..+256) */
    /* moveX = cos(angle) * MOVE_SPEED / 256 */

    /* Up: move forward */
    if (pad & PAD_UP) {
        moveX = (cos_table[playerAngle] * MOVE_SPEED) >> 8;
        moveY = (sin_table[playerAngle] * MOVE_SPEED) >> 8;
        posX += moveX;
        posY += moveY;
    }

    /* Down: move backward */
    if (pad & PAD_DOWN) {
        moveX = (cos_table[playerAngle] * MOVE_SPEED) >> 8;
        moveY = (sin_table[playerAngle] * MOVE_SPEED) >> 8;
        posX -= moveX;
        posY -= moveY;
    }

    /* B button: strafe left */
    if (pad & PAD_B) {
        moveX = (sin_table[playerAngle] * MOVE_SPEED) >> 8;
        moveY = (cos_table[playerAngle] * MOVE_SPEED) >> 8;
        posX += moveX;
        posY -= moveY;
    }

    /* A button: strafe right */
    if (pad & PAD_A) {
        moveX = (sin_table[playerAngle] * MOVE_SPEED) >> 8;
        moveY = (cos_table[playerAngle] * MOVE_SPEED) >> 8;
        posX -= moveX;
        posY += moveY;
    }

    /* Clamp to map bounds (simple, no collision for now) */
    if (posX < 16) posX = 16;
    if (posX > 1008) posX = 1008;
    if (posY < 16) posY = 16;
    if (posY > 1008) posY = 1008;
}

/* ============================================
 * Main loop — BSP + GSU rendering
 * ============================================ */
int main(void) {
    disableNMI();
    initMode3Display();
    initGSU();
    initPlayer();

    while (1) {
        handleInput();
        writePlayerState();
        startGSU();
        dmaFramebuffer();
    }

    return 0;
}
