#!/usr/bin/env python3
"""
wad2snes.py — Convert Doom WAD BSP data to SNES assembly include files

Reads a WAD file (with BSP nodes from ZokumBSP) and outputs:
  - bsp_data.asm: vertices, segs, subsectors, nodes, sectors, linedefs, sidedefs

Data format follows Doom SNES conventions (from rle.i).
"""

import struct
import sys
import os

class WADReader:
    def __init__(self, filename):
        with open(filename, 'rb') as f:
            self.data = f.read()
        magic, self.numlumps, diroff = struct.unpack_from('<4sII', self.data, 0)
        self.lumps = {}
        for i in range(self.numlumps):
            off, size, name = struct.unpack_from('<II8s', self.data, diroff + i * 16)
            name = name.rstrip(b'\x00').decode()
            self.lumps[name] = self.data[off:off+size]

    def get_lump(self, name):
        return self.lumps.get(name, b'')

    def read_vertices(self):
        data = self.get_lump('VERTEXES')
        verts = []
        for i in range(0, len(data), 4):
            x, y = struct.unpack_from('<hh', data, i)
            verts.append((x, y))
        return verts

    def read_linedefs(self):
        data = self.get_lump('LINEDEFS')
        lines = []
        for i in range(0, len(data), 14):
            v1, v2, flags, special, tag, right, left = struct.unpack_from('<HHHHHHh', data, i)
            lines.append({
                'v1': v1, 'v2': v2, 'flags': flags,
                'special': special, 'tag': tag,
                'right_side': right, 'left_side': left
            })
        return lines

    def read_sidedefs(self):
        data = self.get_lump('SIDEDEFS')
        sides = []
        for i in range(0, len(data), 30):
            xoff, yoff = struct.unpack_from('<hh', data, i)
            upper = data[i+4:i+12].rstrip(b'\x00').decode()
            lower = data[i+12:i+20].rstrip(b'\x00').decode()
            mid = data[i+20:i+28].rstrip(b'\x00').decode()
            sector = struct.unpack_from('<H', data, i+28)[0]
            sides.append({
                'xoff': xoff, 'yoff': yoff,
                'upper': upper, 'lower': lower, 'mid': mid,
                'sector': sector
            })
        return sides

    def read_sectors(self):
        data = self.get_lump('SECTORS')
        sectors = []
        for i in range(0, len(data), 26):
            floor_h, ceil_h = struct.unpack_from('<hh', data, i)
            floor_tex = data[i+4:i+12].rstrip(b'\x00').decode()
            ceil_tex = data[i+12:i+20].rstrip(b'\x00').decode()
            light, special, tag = struct.unpack_from('<HHH', data, i+20)
            sectors.append({
                'floor_h': floor_h, 'ceil_h': ceil_h,
                'floor_tex': floor_tex, 'ceil_tex': ceil_tex,
                'light': light, 'special': special, 'tag': tag
            })
        return sectors

    def read_segs(self):
        data = self.get_lump('SEGS')
        segs = []
        for i in range(0, len(data), 12):
            v1, v2, angle, linedef, side, offset = struct.unpack_from('<HHhHHh', data, i)
            segs.append({
                'v1': v1, 'v2': v2, 'angle': angle,
                'linedef': linedef, 'side': side, 'offset': offset
            })
        return segs

    def read_subsectors(self):
        data = self.get_lump('SSECTORS')
        ssectors = []
        for i in range(0, len(data), 4):
            count, first_seg = struct.unpack_from('<HH', data, i)
            ssectors.append({'count': count, 'first_seg': first_seg})
        return ssectors

    def read_nodes(self):
        data = self.get_lump('NODES')
        nodes = []
        for i in range(0, len(data), 28):
            fields = struct.unpack_from('<hhhhhhhhhhhhHH', data, i)
            nodes.append({
                'x': fields[0], 'y': fields[1],
                'dx': fields[2], 'dy': fields[3],
                'right_bbox': fields[4:8],  # top, bottom, left, right
                'left_bbox': fields[8:12],
                'right_child': fields[12],
                'left_child': fields[13]
            })
        return nodes


def generate_asm(wad, output_file):
    """Generate assembly include file with BSP data."""
    verts = wad.read_vertices()
    lines = wad.read_linedefs()
    sides = wad.read_sidedefs()
    sectors = wad.read_sectors()
    segs = wad.read_segs()
    ssectors = wad.read_subsectors()
    nodes = wad.read_nodes()

    with open(output_file, 'w') as f:
        f.write("; bsp_data.asm — Auto-generated BSP data from WAD\n")
        f.write(f"; {len(verts)} vertices, {len(segs)} segs, {len(ssectors)} subsectors\n")
        f.write(f"; {len(nodes)} nodes, {len(sectors)} sectors\n")
        f.write(f"; {len(lines)} linedefs, {len(sides)} sidedefs\n\n")

        # Vertices: x, y (s16 each = 4 bytes per vertex)
        f.write(f"; --- Vertices ({len(verts)}) ---\n")
        f.write(f".define NUM_VERTS {len(verts)}\n")
        f.write("bsp_vertices:\n")
        for i, v in enumerate(verts):
            f.write(f"    .dw {v[0]}, {v[1]}    ; vertex {i}\n")
        f.write("\n")

        # Segs: v1, v2, angle, linedef, side, offset (12 bytes each)
        f.write(f"; --- Segs ({len(segs)}) ---\n")
        f.write(f".define NUM_SEGS {len(segs)}\n")
        f.write("bsp_segs:\n")
        for i, s in enumerate(segs):
            f.write(f"    .dw {s['v1']}, {s['v2']}, {s['angle']}, {s['linedef']}, {s['side']}, {s['offset']}    ; seg {i}\n")
        f.write("\n")

        # Subsectors: count, first_seg (4 bytes each)
        f.write(f"; --- Subsectors ({len(ssectors)}) ---\n")
        f.write(f".define NUM_SSECTORS {len(ssectors)}\n")
        f.write("bsp_subsectors:\n")
        for i, ss in enumerate(ssectors):
            f.write(f"    .dw {ss['count']}, {ss['first_seg']}    ; ssector {i}\n")
        f.write("\n")

        # Nodes: x, y, dx, dy, right_bbox(4), left_bbox(4), right_child, left_child (28 bytes)
        f.write(f"; --- BSP Nodes ({len(nodes)}) ---\n")
        f.write(f".define NUM_NODES {len(nodes)}\n")
        f.write(f".define ROOT_NODE {len(nodes) - 1}\n")
        f.write("bsp_nodes:\n")
        for i, n in enumerate(nodes):
            rb = n['right_bbox']
            lb = n['left_bbox']
            f.write(f"    ; node {i}: partition ({n['x']},{n['y']})+({n['dx']},{n['dy']})\n")
            f.write(f"    .dw {n['x']}, {n['y']}, {n['dx']}, {n['dy']}\n")
            f.write(f"    .dw {rb[0]}, {rb[1]}, {rb[2]}, {rb[3]}    ; right bbox\n")
            f.write(f"    .dw {lb[0]}, {lb[1]}, {lb[2]}, {lb[3]}    ; left bbox\n")
            f.write(f"    .dw {n['right_child']}, {n['left_child']}    ; children\n")
        f.write("\n")

        # Sectors: floor_h, ceil_h, light (simplified — 6 bytes each)
        f.write(f"; --- Sectors ({len(sectors)}) ---\n")
        f.write(f".define NUM_SECTORS {len(sectors)}\n")
        f.write("bsp_sectors:\n")
        for i, s in enumerate(sectors):
            f.write(f"    .dw {s['floor_h']}, {s['ceil_h']}, {s['light']}    ; sector {i}\n")
        f.write("\n")

        # Linedefs: v1, v2, flags, right_side, left_side (10 bytes each)
        f.write(f"; --- Linedefs ({len(lines)}) ---\n")
        f.write(f".define NUM_LINEDEFS {len(lines)}\n")
        f.write("bsp_linedefs:\n")
        for i, l in enumerate(lines):
            left = l['left_side'] if l['left_side'] >= 0 else 0xFFFF
            f.write(f"    .dw {l['v1']}, {l['v2']}, {l['flags']}, {l['right_side']}, {left}    ; line {i}\n")
        f.write("\n")

        # Sidedefs: xoff, yoff, sector, texture_id (simplified — 8 bytes each)
        f.write(f"; --- Sidedefs ({len(sides)}) ---\n")
        f.write(f".define NUM_SIDEDEFS {len(sides)}\n")
        f.write("bsp_sidedefs:\n")
        for i, s in enumerate(sides):
            # Map texture names to indices
            tex_id = 0
            if s['mid'] and s['mid'] != '-':
                tex_id = hash(s['mid']) & 0xFF  # Simple hash for now
            f.write(f"    .dw {s['xoff']}, {s['yoff']}, {s['sector']}, {tex_id}    ; side {i} ({s['mid']})\n")
        f.write("\n")

    print(f"Generated {output_file}")
    print(f"  {len(verts)} vertices, {len(segs)} segs, {len(ssectors)} ssectors")
    print(f"  {len(nodes)} nodes, {len(sectors)} sectors")
    print(f"  {len(lines)} linedefs, {len(sides)} sidedefs")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} input.wad [output.asm]")
        sys.exit(1)

    wad_file = sys.argv[1]
    out_file = sys.argv[2] if len(sys.argv) > 2 else 'bsp_data.asm'

    wad = WADReader(wad_file)
    generate_asm(wad, out_file)
