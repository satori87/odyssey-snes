#!/usr/bin/env python3
"""Convert PNG textures to C header format for the raycasting engine.

Reads:
  assets/walls.png  (256x128, 8x4 grid of 32x32 tiles)
  assets/floors.png (256x256, irregular grid)

Outputs:
  data/palettes.h  - shared 16-color BGR555 palette as C array
  data/textures.h  - column-major pixel data as C arrays
"""

import math
import os
from collections import Counter

from PIL import Image

BASE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)
ASSETS_DIR = os.path.join(BASE_DIR, "assets")
DATA_DIR = os.path.join(BASE_DIR, "data")

WALLS_PATH = os.path.join(ASSETS_DIR, "walls.png")
FLOORS_PATH = os.path.join(ASSETS_DIR, "floors.png")
PALETTES_PATH = os.path.join(DATA_DIR, "palettes.h")
TEXTURES_PATH = os.path.join(DATA_DIR, "textures.h")

TILE_SIZE = 32
VALS_PER_LINE = 16


def extract_tile(img, col, row, tile_w=TILE_SIZE, tile_h=TILE_SIZE):
    """Extract a tile_w x tile_h tile from a grid image at (col, row)."""
    x0 = col * tile_w
    y0 = row * tile_h
    return img.crop((x0, y0, x0 + tile_w, y0 + tile_h))


def get_pixels_rgba(tile):
    """Return list of (r, g, b, a) tuples for every pixel in the tile."""
    tile_rgba = tile.convert("RGBA")
    return list(tile_rgba.getdata())


def collect_opaque_colors(pixels):
    """Collect all unique opaque RGB colors and their frequencies."""
    freq = Counter()
    for r, g, b, a in pixels:
        if a > 0:
            freq[(r, g, b)] += 1
    return freq


def rgb_to_bgr555(r, g, b):
    """Convert 8-bit RGB to SNES 15-bit BGR555."""
    return ((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3)


def color_distance_sq(c1, c2):
    """Squared Euclidean distance between two RGB tuples."""
    return (c1[0] - c2[0]) ** 2 + (c1[1] - c2[1]) ** 2 + (c1[2] - c2[2]) ** 2


def nearest_palette_index(rgb, palette):
    """Find the index of the nearest color in the palette."""
    best_idx = 0
    best_dist = float("inf")
    for idx, pal_color in enumerate(palette):
        d = color_distance_sq(rgb, pal_color)
        if d < best_dist:
            best_dist = d
            best_idx = idx
    return best_idx


def build_palette(wall_pixels, floor_pixels, max_colors=16):
    """Build a shared palette from two sets of RGBA pixels.

    Color 0 is always black (0, 0, 0).
    Remaining slots use the most frequent colors across both tiles.
    """
    freq = Counter()
    for pixels in (wall_pixels, floor_pixels):
        for r, g, b, a in pixels:
            if a > 0:
                freq[(r, g, b)] += 1

    # Remove black if present -- it gets slot 0 regardless
    freq.pop((0, 0, 0), None)

    remaining_slots = max_colors - 1  # slot 0 = black

    unique_colors = list(freq.keys())
    if len(unique_colors) <= remaining_slots:
        # All fit -- sort by frequency for determinism
        selected = sorted(unique_colors, key=lambda c: -freq[c])
    else:
        # Take the most frequent colors
        selected = [c for c, _ in freq.most_common(remaining_slots)]

    palette = [(0, 0, 0)] + selected

    # Pad to exactly max_colors with black if needed
    while len(palette) < max_colors:
        palette.append((0, 0, 0))

    return palette


def index_tile(pixels, width, height, palette):
    """Convert RGBA pixel list to column-major indexed bytes.

    Returns a list of (width * height) palette indices in column-major order:
      for col in 0..width-1:
        for row in 0..height-1:
          output.append(index)
    """
    # Build a row-major 2D grid first
    grid = []
    for row in range(height):
        row_data = []
        for col in range(width):
            r, g, b, a = pixels[row * width + col]
            if a == 0:
                row_data.append(0)  # transparent -> color 0 (black)
            else:
                row_data.append(nearest_palette_index((r, g, b), palette))
        grid.append(row_data)

    # Convert to column-major
    result = []
    for col in range(width):
        for row in range(height):
            result.append(grid[row][col])
    return result


def format_palette_c(palette):
    """Format palette as C const u16 array with BGR555 values."""
    bgr_values = [rgb_to_bgr555(r, g, b) for r, g, b in palette]
    lines = [f"const u16 shared_palette[{len(bgr_values)}] = {{"]
    hex_vals = ", ".join(f"0x{v:04X}" for v in bgr_values)
    lines.append(f"    {hex_vals}")
    lines.append("};")
    return "\n".join(lines)


def format_texture_c(name, indices, width=TILE_SIZE, height=TILE_SIZE):
    """Format column-major texture data as C const u8 array."""
    lines = [f"/* {width}x{height}, column-major, 1 byte per pixel (palette index 0-15) */"]
    lines.append(f"const u8 {name}[{len(indices)}] = {{")
    for i in range(0, len(indices), VALS_PER_LINE):
        chunk = indices[i:i + VALS_PER_LINE]
        vals = ", ".join(f"{v:d}" for v in chunk)
        if i + VALS_PER_LINE < len(indices):
            vals += ","
        lines.append(f"    {vals}")
    lines.append("};")
    return "\n".join(lines)


def format_texture_asm(label, indices, width=TILE_SIZE, height=TILE_SIZE):
    """Format column-major texture data as WLA-DX .db assembly."""
    lines = [f"; {width}x{height}, column-major, 1 byte per pixel (palette index 0-15)"]
    lines.append(f"{label}:")
    for i in range(0, len(indices), 16):
        chunk = indices[i:i + 16]
        vals = ", ".join(f"{v:d}" for v in chunk)
        lines.append(f"    .db {vals}")
    return "\n".join(lines)


def darken_indices(indices, palette, darken_offset=32):
    """Remap palette indices to darkened versions (index + darken_offset).
    Index 0 (black) stays as 0."""
    return [0 if v == 0 else v + darken_offset for v in indices]


def darken_palette(palette, factor=0.5):
    """Create darkened version of palette by scaling RGB values."""
    darkened = []
    for r, g, b in palette:
        darkened.append((int(r * factor), int(g * factor), int(b * factor)))
    return darkened


def main():
    # Load images
    walls_img = Image.open(WALLS_PATH)
    floors_img = Image.open(FLOORS_PATH)

    print(f"Loaded walls.png:  {walls_img.size[0]}x{walls_img.size[1]} ({walls_img.mode})")
    print(f"Loaded floors.png: {floors_img.size[0]}x{floors_img.size[1]} ({floors_img.mode})")

    # Extract tiles (1-based numbering, 8 tiles per row):
    # Outer wall: tile 1 = (col=0, row=0)
    # Inner wall: tile 23 = (col=6, row=2)
    # Floor: floors.png tile (0,7)
    outer_wall_tile = extract_tile(walls_img, col=0, row=0)
    inner_wall_tile = extract_tile(walls_img, col=6, row=2)
    floor_tile = extract_tile(floors_img, col=1, row=7)

    print(f"Outer wall: tile 1, col=0, row=0 from walls.png")
    print(f"Inner wall: tile 23, col=6, row=2 from walls.png")
    print(f"Floor tile: col=0, row=7 from floors.png")

    # Get pixel data
    outer_pixels = get_pixels_rgba(outer_wall_tile)
    inner_pixels = get_pixels_rgba(inner_wall_tile)
    floor_pixels = get_pixels_rgba(floor_tile)

    # Build shared palette from all 3 textures
    all_pixel_sets = [outer_pixels, inner_pixels, floor_pixels]
    freq = Counter()
    for pixels in all_pixel_sets:
        for r, g, b, a in pixels:
            if a > 0:
                freq[(r, g, b)] += 1
    freq.pop((0, 0, 0), None)
    remaining_slots = 15  # slot 0 = black
    unique_colors = list(freq.keys())
    if len(unique_colors) <= remaining_slots:
        selected = sorted(unique_colors, key=lambda c: -freq[c])
    else:
        selected = [c for c, _ in freq.most_common(remaining_slots)]
    palette = [(0, 0, 0)] + selected
    while len(palette) < 16:
        palette.append((0, 0, 0))

    print(f"Unique colors across all textures: {len(unique_colors)}")
    print(f"Palette slots used: {min(len(unique_colors) + 1, 16)}")

    # Index pixels to palette (column-major)
    outer_indices = index_tile(outer_pixels, TILE_SIZE, TILE_SIZE, palette)
    inner_indices = index_tile(inner_pixels, TILE_SIZE, TILE_SIZE, palette)
    floor_indices = index_tile(floor_pixels, TILE_SIZE, TILE_SIZE, palette)

    # Ceiling = darkened floor (indices + 32, using darkened palette at slots 32-47)
    ceil_indices = darken_indices(floor_indices, palette)
    dark_palette = darken_palette(palette)

    # Generate output files
    os.makedirs(DATA_DIR, exist_ok=True)

    # --- palettes.h ---
    pal_header = (
        "/* ============================================\n"
        " * Shared 16-color BGR555 palette\n"
        " * Auto-generated by tools/convert_textures_c.py\n"
        " * ============================================ */\n"
        "\n"
        "#ifndef PALETTES_H\n"
        "#define PALETTES_H\n"
    )
    pal_c = format_palette_c(palette)
    # Also generate darkened palette for ceiling
    dark_bgr = [rgb_to_bgr555(r, g, b) for r, g, b in dark_palette]
    dark_c = f"/* Colors 32-47: darkened texture palette (for ceiling) */\n"
    dark_c += f"const u16 dark_palette[{len(dark_bgr)}] = {{\n"
    dark_c += "    " + ", ".join(f"0x{v:04X}" for v in dark_bgr) + "\n};"

    palette_text = (pal_header + "\n/* Colors 0-15: texture palette */\n" + pal_c +
                    "\n/* Colors 16-17: ceiling and floor solid */\n"
                    "const u16 extra_palette[2] = {\n"
                    "    0x1084,  /* 16: dark gray ceiling (#222222) */\n"
                    "    0x1CE7   /* 17: medium gray floor (#383838) */\n"
                    "};\n\n" + dark_c + "\n\n#endif /* PALETTES_H */\n")

    with open(PALETTES_PATH, "w", newline="\n") as f:
        f.write(palette_text)

    # --- textures.h (C format, for reference) ---
    tex_header = (
        "/* ============================================\n"
        " * Texture data (column-major, 1 byte/pixel)\n"
        " * Auto-generated by tools/convert_textures_c.py\n"
        " * ============================================ */\n"
        "\n"
        "#ifndef TEXTURES_H\n"
        "#define TEXTURES_H\n"
    )
    textures_output = tex_header + "\n"
    textures_output += format_texture_c("outer_wall_texture", outer_indices) + "\n\n"
    textures_output += format_texture_c("inner_wall_texture", inner_indices) + "\n\n"
    textures_output += format_texture_c("floor_texture", floor_indices) + "\n\n"
    textures_output += format_texture_c("ceil_texture", ceil_indices) + "\n\n"
    textures_output += "#endif /* TEXTURES_H */\n"

    with open(TEXTURES_PATH, "w", newline="\n") as f:
        f.write(textures_output)

    # --- GSU assembly texture data ---
    GSU_TEX_PATH = os.path.join(DATA_DIR, "gsu_textures.asm")
    asm_output = "; Auto-generated texture data for GSU (column-major, 32x32)\n"
    asm_output += "; Generated by tools/convert_textures_c.py\n\n"
    # Dark wall textures: palette indices +32 (for Y-face darkening)
    outer_dark = darken_indices(outer_indices, palette)
    inner_dark = darken_indices(inner_indices, palette)

    asm_output += format_texture_asm("outer_wall_tex", outer_indices) + "\n\n"
    asm_output += format_texture_asm("outer_wall_dark_tex", outer_dark) + "\n\n"
    asm_output += format_texture_asm("inner_wall_tex", inner_indices) + "\n\n"
    asm_output += format_texture_asm("inner_wall_dark_tex", inner_dark) + "\n\n"
    asm_output += format_texture_asm("floor_tex", floor_indices) + "\n\n"
    asm_output += format_texture_asm("ceil_tex", ceil_indices) + "\n\n"

    with open(GSU_TEX_PATH, "w", newline="\n") as f:
        f.write(asm_output)

    print()
    print(f"Generated: {os.path.normpath(PALETTES_PATH)}")
    print(f"  16 BGR555 palette entries + 16 darkened entries")
    print(f"Generated: {os.path.normpath(TEXTURES_PATH)}")
    print(f"  outer_wall_texture: {len(outer_indices)} bytes")
    print(f"  inner_wall_texture: {len(inner_indices)} bytes")
    print(f"  floor_texture:      {len(floor_indices)} bytes")
    print(f"  ceil_texture:       {len(ceil_indices)} bytes")
    print(f"Generated: {os.path.normpath(GSU_TEX_PATH)}")
    print(f"  GSU assembly texture data (4 textures, {4*1024} bytes total)")


if __name__ == "__main__":
    main()
