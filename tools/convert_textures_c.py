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


def main():
    # Load images
    walls_img = Image.open(WALLS_PATH)
    floors_img = Image.open(FLOORS_PATH)

    print(f"Loaded walls.png:  {walls_img.size[0]}x{walls_img.size[1]} ({walls_img.mode})")
    print(f"Loaded floors.png: {floors_img.size[0]}x{floors_img.size[1]} ({floors_img.mode})")

    # Extract specific tiles
    wall_tile = extract_tile(walls_img, col=0, row=2)   # blue stone
    floor_tile = extract_tile(floors_img, col=5, row=6)  # stone floor

    print(f"Wall tile:  col=0, row=2 from walls.png  ({wall_tile.size[0]}x{wall_tile.size[1]})")
    print(f"Floor tile: col=5, row=6 from floors.png ({floor_tile.size[0]}x{floor_tile.size[1]})")

    # Get pixel data
    wall_pixels = get_pixels_rgba(wall_tile)
    floor_pixels = get_pixels_rgba(floor_tile)

    # Build shared palette
    palette = build_palette(wall_pixels, floor_pixels, max_colors=16)

    # Count unique opaque colors for reporting
    wall_freq = collect_opaque_colors(wall_pixels)
    floor_freq = collect_opaque_colors(floor_pixels)
    all_unique = set(wall_freq.keys()) | set(floor_freq.keys())
    print(f"Unique opaque colors: wall={len(wall_freq)}, floor={len(floor_freq)}, combined={len(all_unique)}")
    print(f"Palette slots used: {sum(1 for c in palette if c != (0, 0, 0) or palette.index(c) == 0)}")

    # Index pixels to palette (column-major)
    wall_indices = index_tile(wall_pixels, TILE_SIZE, TILE_SIZE, palette)
    floor_indices = index_tile(floor_pixels, TILE_SIZE, TILE_SIZE, palette)

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
    palette_text = pal_header + "\n" + format_palette_c(palette) + "\n\n#endif /* PALETTES_H */\n"

    with open(PALETTES_PATH, "w", newline="\n") as f:
        f.write(palette_text)

    # --- textures.h ---
    tex_header = (
        "/* ============================================\n"
        " * Texture data (column-major, 1 byte/pixel)\n"
        " * Auto-generated by tools/convert_textures_c.py\n"
        " * ============================================ */\n"
        "\n"
        "#ifndef TEXTURES_H\n"
        "#define TEXTURES_H\n"
    )
    wall_text = format_texture_c("wall_texture", wall_indices)
    floor_text = format_texture_c("floor_texture", floor_indices)
    textures_output = tex_header + "\n" + wall_text + "\n\n" + floor_text + "\n\n#endif /* TEXTURES_H */\n"

    with open(TEXTURES_PATH, "w", newline="\n") as f:
        f.write(textures_output)

    print()
    print(f"Generated: {os.path.normpath(PALETTES_PATH)}")
    print(f"  16 BGR555 palette entries")
    print(f"Generated: {os.path.normpath(TEXTURES_PATH)}")
    print(f"  wall_texture:  {len(wall_indices)} bytes (32x32 column-major)")
    print(f"  floor_texture: {len(floor_indices)} bytes (32x32 column-major)")


if __name__ == "__main__":
    main()
