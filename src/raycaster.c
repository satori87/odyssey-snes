typedef unsigned char u8;
typedef signed char s8;
typedef unsigned short u16;
typedef signed short s16;

#include "../data/palettes.h"

extern void initMode7Display(void);
extern void disableNMI(void);

int main(void) {
    disableNMI();
    initMode7Display();
    while (1) {}
    return 0;
}
