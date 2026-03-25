#!/usr/bin/env python3
"""Generate compiled wall scalers for SNES Mode 7 renderer."""

MAX_H = 40
TEX_H = 32
DP_BUF = 0xB0

def main():
    lines = []
    lines.append(f"; Compiled wall scalers for heights 1-{MAX_H}")
    lines.append(f"; Texture column in DP ${DP_BUF:02X}-${DP_BUF+TEX_H-1:02X}")
    lines.append(f"; MUST be called in 8-bit A mode (sep #$20)")
    lines.append("")
    lines.append(f".define MAX_COMPILED_H {MAX_H}")
    lines.append("")

    # Trampoline
    lines.append(";; _call_scaler: trampoline called via JSL from renderColumns")
    lines.append(";; Input: X = height * 2 (word index into scaler_ptrs)")
    lines.append(";; Sets 8-bit A, looks up scaler, jumps to it. Returns via RTL.")
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

    # Scaler routines (all 8-bit A, entered from trampoline)
    for h in range(1, MAX_H + 1):
        lines.append(f"scaler_{h}:")
        for p in range(h):
            tr = min((p * TEX_H) // h, TEX_H - 1)
            lines.append(f"    lda ${DP_BUF + tr:02X}")
            lines.append(f"    sta.l $2180")
        lines.append("    rtl")
        lines.append("")

    with open("data/compiled_scalers.asm", "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Generated {MAX_H} scalers + trampoline with sep #$20")

if __name__ == "__main__":
    main()
