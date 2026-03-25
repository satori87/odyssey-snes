#!/usr/bin/env python3
"""Generate compiled wall scalers for SNES Mode 7 renderer.
Full 80 heights. Placed directly in bank 2 via .BANK/.ORG (no section)."""

MAX_H = 80
TEX_H = 32
DP_BUF = 0xB0

def main():
    lines = []
    lines.append(f"; Compiled wall scalers for heights 1-{MAX_H}")
    lines.append(f"; Placed directly in ROM bank 2")
    lines.append(f"; Texture column in DP ${DP_BUF:02X}-${DP_BUF+TEX_H-1:02X}")
    lines.append("")
    lines.append(".BANK 2")
    lines.append(".ORG $0000")
    lines.append("")

    # Trampoline
    lines.append("_call_scaler:")
    lines.append("    sep #$20")
    lines.append(".ACCU 8")
    lines.append("    lda.l scaler_ptrs,x")
    lines.append("    sta $1C")
    lines.append("    lda.l scaler_ptrs+1,x")
    lines.append("    sta $1D")
    lines.append("    jmp ($001C)")
    lines.append("")

    # Pointer table
    lines.append("scaler_ptrs:")
    lines.append("    .dw 0")
    for h in range(1, MAX_H + 1):
        lines.append(f"    .dw scaler_{h}")
    lines.append("")

    # Scaler routines
    total = 0
    for h in range(1, MAX_H + 1):
        lines.append(f"scaler_{h}:")
        for p in range(h):
            tr = min((p * TEX_H) // h, TEX_H - 1)
            lines.append(f"    lda ${DP_BUF + tr:02X}")
            lines.append(f"    sta.l $2180")
        lines.append("    rtl")
        lines.append("")
        total += h * 6 + 1

    with open("data/compiled_scalers.asm", "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Generated {MAX_H} scalers, ~{(total + (MAX_H+1)*2) // 1024}KB")

if __name__ == "__main__":
    main()
