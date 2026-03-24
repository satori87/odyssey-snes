#!/usr/bin/env python3
"""Generate BSP renderer lookup tables following Noah's Ark 3D formulas."""

import math

# Constants (from Noah's WOLFDEF.H / REFRESH.H)
SCREENWIDTH = 112
SCREENHEIGHT = 80
FRACBITS = 8
FRACUNIT = 1 << FRACBITS  # 256
MAXFRAC = 0x7FFF
FINEANGLES = 2048
FIELDOFVIEW = 364  # fine angles
SIDESLOPE = 0xA0  # 160
PROJECTIONSCALE = (SCREENWIDTH // 2) * 0x8000 // SIDESLOPE  # 11469
MAXZ = 32 * FRACUNIT  # 8192
CLOSESTZ = 62
PI = 3.141592657


SLOPERANGE = 512
ANGLETOFINESHIFT = 5  # 16-bit angle >> 5 = fine angle (2048)
ANG90 = 0x4000
ANG180 = 0x8000


def generate_tantoangle():
    """tantoangle[513]: arctan lookup for PointToAngle octant-based conversion."""
    table = []
    for i in range(SLOPERANGE + 1):
        f = math.atan(i / SLOPERANGE) / (PI * 2)
        t = int(0x10000 * f) & 0xFFFF
        table.append(t)
    return table


def generate_finesine():
    """finesine[1024]: 256*sin(angle), clamped [1,255]"""
    table = []
    for i in range(FINEANGLES // 2):
        a = i * PI * 2 / FINEANGLES
        t = int(256 * math.sin(a))
        t = max(1, min(255, t))
        table.append(t)
    return table


def generate_finetangent():
    """finetangent[1024]: 256*tan(angle - pi/4 + small), clamped [-32767,32767]"""
    table = []
    for i in range(FINEANGLES // 2):
        a = (i - FINEANGLES / 4 + 0.1) * PI * 2 / FINEANGLES
        fv = 256 * math.tan(a)
        if fv > 0x7FFF:
            t = 0x7FFF
        elif fv < -0x7FFF:
            t = -0x7FFF
        else:
            t = int(fv)
        table.append(t)
    return table


def ufixed_div(a, b):
    """UFixedDiv: (a << 8) / b, unsigned"""
    if b == 0:
        return MAXFRAC
    return min(MAXFRAC, (a << 8) // b)


def sfixed_mul(a, b):
    """SUFixedMul: (a * b) >> 8, signed*unsigned"""
    return (a * b) >> 8


def fixed_div(a, b):
    """FixedDiv: (a << 8) / b, signed"""
    if b == 0:
        return 0x7FFF if a >= 0 else -0x7FFF
    return (a << 8) // b


def generate_scaleatz():
    """scaleatz[8192]: PROJECTIONSCALE / z, clamped to MAXFRAC for small z"""
    minz = ufixed_div(PROJECTIONSCALE, MAXFRAC)
    table = []
    for i in range(MAXZ):
        if i <= minz:
            table.append(MAXFRAC)
        else:
            table.append(ufixed_div(PROJECTIONSCALE, i))
    return table


def generate_viewangletox(finetangent):
    """viewangletox[1024]: maps fine angles to screen X"""
    # focallength = FixedDiv(SCREENWIDTH/2, finetangent[FINEANGLES/4 + FIELDOFVIEW/2])
    idx = FINEANGLES // 4 + FIELDOFVIEW // 2
    focallength = fixed_div(SCREENWIDTH // 2, finetangent[idx])

    table = []
    for i in range(FINEANGLES // 2):
        t = sfixed_mul(finetangent[i], focallength)
        t = SCREENWIDTH // 2 - t
        if t < -1:
            t = -1
        elif t > SCREENWIDTH + 1:
            t = SCREENWIDTH + 1
        table.append(t)

    # Clamp boundaries
    for i in range(len(table)):
        if table[i] == -1:
            table[i] = 0
        elif table[i] == SCREENWIDTH + 1:
            table[i] = SCREENWIDTH

    return table


def generate_xtoviewangle(viewangletox):
    """xtoviewangle[113]: inverse of viewangletox"""
    table = []
    for x in range(SCREENWIDTH + 1):
        i = 0
        while i < len(viewangletox) and viewangletox[i] >= x:
            i += 1
        table.append(i - FINEANGLES // 4 - 1)
    return table


def write_s16_array(f, name, data, per_line=8):
    """Write signed 16-bit C array"""
    f.write(f"const s16 {name}[{len(data)}] = {{\n")
    for i in range(0, len(data), per_line):
        chunk = data[i:i+per_line]
        f.write("    " + ", ".join(f"{v}" for v in chunk))
        if i + per_line < len(data):
            f.write(",")
        f.write("\n")
    f.write("};\n\n")


def write_u16_array(f, name, data, per_line=8):
    """Write unsigned 16-bit C array"""
    f.write(f"const u16 {name}[{len(data)}] = {{\n")
    for i in range(0, len(data), per_line):
        chunk = data[i:i+per_line]
        f.write("    " + ", ".join(f"{v}" for v in chunk))
        if i + per_line < len(data):
            f.write(",")
        f.write("\n")
    f.write("};\n\n")


def main():
    print("Generating BSP lookup tables...")

    tantoangle = generate_tantoangle()
    finesine = generate_finesine()
    finetangent = generate_finetangent()
    scaleatz = generate_scaleatz()
    viewangletox = generate_viewangletox(finetangent)
    xtoviewangle = generate_xtoviewangle(viewangletox)

    # Compute clipshortangle: the angle that maps to SCREENWIDTH in viewangletox
    clipshortangle = 0
    for i in range(len(viewangletox)):
        if viewangletox[i] == 0:
            clipshortangle = (i - FINEANGLES // 4) << ANGLETOFINESHIFT
            break

    print(f"  tantoangle:   {len(tantoangle)} entries (16-bit angle, range {min(tantoangle)}-{max(tantoangle)})")
    print(f"  finesine:     {len(finesine)} entries (0.8 fixed, range {min(finesine)}-{max(finesine)})")
    print(f"  finetangent:  {len(finetangent)} entries (8.8 signed, range {min(finetangent)}-{max(finetangent)})")
    print(f"  scaleatz:     {len(scaleatz)} entries (8.8 unsigned, range {min(scaleatz)}-{max(scaleatz)})")
    print(f"  viewangletox: {len(viewangletox)} entries (range {min(viewangletox)}-{max(viewangletox)})")
    print(f"  xtoviewangle: {len(xtoviewangle)} entries (range {min(xtoviewangle)}-{max(xtoviewangle)})")
    print(f"  clipshortangle = {clipshortangle} (${clipshortangle & 0xFFFF:04X})")
    print(f"  PROJECTIONSCALE = {PROJECTIONSCALE} (${PROJECTIONSCALE:04X})")

    with open("data/bsp_tables.h", "w") as f:
        f.write("/* BSP renderer lookup tables - generated by generate_bsp_tables.py */\n")
        f.write("/* Noah's Ark 3D formulas, SCREENWIDTH=112, FINEANGLES=2048 */\n\n")
        f.write(f"#define FINEANGLES      {FINEANGLES}\n")
        f.write(f"#define FIELDOFVIEW     {FIELDOFVIEW}\n")
        f.write(f"#define PROJECTIONSCALE {PROJECTIONSCALE}\n")
        f.write(f"#define MAXZ            {MAXZ}\n")
        f.write(f"#define CLOSESTZ        {CLOSESTZ}\n")
        f.write(f"#define FRACBITS        {FRACBITS}\n")
        f.write(f"#define FRACUNIT        {FRACUNIT}\n")
        f.write(f"#define SLOPERANGE      {SLOPERANGE}\n")
        f.write(f"#define ANGLETOFINESHIFT {ANGLETOFINESHIFT}\n")
        f.write(f"#define ANG90           0x4000\n")
        f.write(f"#define ANG180          0x8000\n")
        f.write(f"#define ANG270          0xC000\n")
        f.write(f"#define CLIPSHORTANGLE  {clipshortangle & 0xFFFF}\n")
        f.write(f"#define FINEMASK        {FINEANGLES - 1}\n\n")

        write_u16_array(f, "tantoangle", tantoangle)
        write_s16_array(f, "finesine", finesine)
        write_s16_array(f, "finetangent", finetangent)
        write_u16_array(f, "scaleatz", scaleatz, per_line=16)
        write_s16_array(f, "viewangletox", viewangletox)
        write_s16_array(f, "xtoviewangle", xtoviewangle)

    print(f"  Written to data/bsp_tables.h")
    total_bytes = len(finesine)*2 + len(finetangent)*2 + len(scaleatz)*2 + len(viewangletox)*2 + len(xtoviewangle)*2
    print(f"  Total: {total_bytes} bytes ({total_bytes/1024:.1f} KB)")


if __name__ == "__main__":
    main()
