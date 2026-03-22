#!/usr/bin/env python3
"""
wad2snes.py — Convert Doom WAD BSP data to SNES assembly (Doom SNES format)

Reads a WAD file (with BSP nodes from ZokumBSP) and outputs:
  - bsp_data.asm: vertices, segs, subsectors(areas), nodes, sectors

Data format follows Doom SNES conventions from rle.i:
  - BSP Node (rlb): 28 bytes — LineY,DeltaX,LineX,DeltaY,LeftBBox,LeftChild,RightBBox,RightChild
  - Area (rla): 4 bytes — NumSegs(1),SegOffset(2),Sector(1)
  - Seg (rlg): 11 bytes — V1(2),V2(2),Flags(1),WallColor(1),pad(1),Face(2),Line(2)
  - Vertex (rlx): 4 bytes — X(2),Y(2)
"""

import struct
import sys
import math

# Doom SNES structure sizes (from rle.i)
RLX_SIZE = 4    # vertex
RLG_SIZE = 11   # seg
RLA_SIZE = 4    # area (subsector)
RLB_SIZE = 28   # BSP node


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


# Texture name to palette color mapping
TEXTURE_COLORS = {
    'WALL00': 1,    # outer walls — brown (palette color 1)
    'WALL01': 3,    # pillar walls — different color (palette color 3)
}


def s16(val):
    """Ensure value is a signed 16-bit integer for assembly output."""
    val = int(val)
    if val < 0:
        return val
    if val > 32767:
        return val - 65536
    return val


def generate_asm(wad, output_file):
    """Generate assembly include file with BSP data in Doom SNES format."""
    verts = wad.read_vertices()
    lines = wad.read_linedefs()
    sides = wad.read_sidedefs()
    sectors = wad.read_sectors()
    segs = wad.read_segs()
    ssectors = wad.read_subsectors()
    nodes = wad.read_nodes()

    with open(output_file, 'w') as f:
        f.write("; bsp_data.asm — Doom SNES format BSP data (auto-generated)\n")
        f.write(f"; {len(verts)} vertices, {len(segs)} segs, {len(ssectors)} areas\n")
        f.write(f"; {len(nodes)} nodes, {len(sectors)} sectors\n")
        f.write(f"; Structure sizes: vertex={RLX_SIZE}, seg={RLG_SIZE}, "
                f"area={RLA_SIZE}, node={RLB_SIZE}\n\n")

        # Constants
        f.write(f".define NUM_VERTS {len(verts)}\n")
        f.write(f".define NUM_SEGS {len(segs)}\n")
        f.write(f".define NUM_AREAS {len(ssectors)}\n")
        f.write(f".define NUM_NODES {len(nodes)}\n")
        f.write(f".define NUM_SECTORS {len(sectors)}\n")
        f.write(f".define ROOT_NODE_OFFSET {(len(nodes) - 1) * RLB_SIZE}\n\n")

        # --- Vertices (4 bytes each: X, Y) ---
        f.write(f"; --- Vertices ({len(verts)}, {RLX_SIZE} bytes each) ---\n")
        f.write("bsp_vertices:\n")
        for i, v in enumerate(verts):
            f.write(f"    .dw {s16(v[0])}, {s16(v[1])}"
                    f"    ; v{i} @{i*RLX_SIZE}\n")
        f.write("\n")

        # --- BSP Nodes (28 bytes each, Doom field order) ---
        f.write(f"; --- BSP Nodes ({len(nodes)}, {RLB_SIZE} bytes each) ---\n")
        f.write("; Field order: LineY, DeltaX, LineX, DeltaY,\n")
        f.write(";   LeftBBox(YMax,YMin,XMin,XMax), LeftChild,\n")
        f.write(";   RightBBox(YMax,YMin,XMin,XMax), RightChild\n")
        f.write("bsp_nodes:\n")
        for i, n in enumerate(nodes):
            # Convert child pointers from WAD format to Doom SNES format
            # WAD: bit15 = subsector, lower bits = index
            # SNES: positive = node_index * RLB_SIZE, $8000 | area_index * RLA_SIZE
            rc = n['right_child']
            lc = n['left_child']
            if rc & 0x8000:
                rc_snes = 0x8000 | ((rc & 0x7FFF) * RLA_SIZE)
            else:
                rc_snes = rc * RLB_SIZE
            if lc & 0x8000:
                lc_snes = 0x8000 | ((lc & 0x7FFF) * RLA_SIZE)
            else:
                lc_snes = lc * RLB_SIZE

            rb = n['right_bbox']  # top(ymax), bottom(ymin), left(xmin), right(xmax)
            lb = n['left_bbox']

            f.write(f"    ; node {i} @{i*RLB_SIZE}: "
                    f"partition ({n['x']},{n['y']})+({n['dx']},{n['dy']})\n")
            # Doom order: LineY, DeltaX, LineX, DeltaY
            f.write(f"    .dw {s16(n['y'])}, {s16(n['dx'])}, "
                    f"{s16(n['x'])}, {s16(n['dy'])}\n")
            # Left bbox: YMax, YMin, XMin, XMax
            f.write(f"    .dw {s16(lb[0])}, {s16(lb[1])}, "
                    f"{s16(lb[2])}, {s16(lb[3])}    ; left bbox\n")
            # Left child
            f.write(f"    .dw ${lc_snes:04X}    ; left child\n")
            # Right bbox: YMax, YMin, XMin, XMax
            f.write(f"    .dw {s16(rb[0])}, {s16(rb[1])}, "
                    f"{s16(rb[2])}, {s16(rb[3])}    ; right bbox\n")
            # Right child
            f.write(f"    .dw ${rc_snes:04X}    ; right child\n")
        f.write("\n")

        # --- Areas / Subsectors (4 bytes each) ---
        f.write(f"; --- Areas ({len(ssectors)}, {RLA_SIZE} bytes each) ---\n")
        f.write("; Fields: NumSegs(1), SegOffset(2), Sector(1)\n")
        f.write("bsp_areas:\n")
        for i, ss in enumerate(ssectors):
            seg_offset = ss['first_seg'] * RLG_SIZE
            # Get sector from first seg's linedef/sidedef
            sector_idx = 0
            if ss['first_seg'] < len(segs):
                seg = segs[ss['first_seg']]
                if seg['linedef'] < len(lines):
                    linedef = lines[seg['linedef']]
                    side_idx = linedef['right_side'] if seg['side'] == 0 else linedef['left_side']
                    if 0 <= side_idx < len(sides):
                        sector_idx = sides[side_idx]['sector']
            f.write(f"    .db {ss['count']}"
                    f"         ; numSegs  (area {i})\n")
            f.write(f"    .dw {seg_offset}"
                    f"     ; segOffset\n")
            f.write(f"    .db {sector_idx}"
                    f"         ; sector\n")
        f.write("\n")

        # --- Segs (11 bytes each) ---
        f.write(f"; --- Segs ({len(segs)}, {RLG_SIZE} bytes each) ---\n")
        f.write("; Fields: V1offset(2), V2offset(2), Flags(1), WallColor(1),\n")
        f.write(";         pad(1), Face(2), Line(2)\n")
        f.write("bsp_segs:\n")
        for i, s in enumerate(segs):
            v1_offset = s['v1'] * RLX_SIZE
            v2_offset = s['v2'] * RLX_SIZE

            # Determine wall color from sidedef texture
            wall_color = 1  # default
            if s['linedef'] < len(lines):
                linedef = lines[s['linedef']]
                side_idx = linedef['right_side'] if s['side'] == 0 else linedef['left_side']
                if 0 <= side_idx < len(sides):
                    mid_tex = sides[side_idx]['mid']
                    wall_color = TEXTURE_COLORS.get(mid_tex, 1)

            flags = 0x01  # solid

            f.write(f"    ; seg {i}: v{s['v1']}->v{s['v2']}"
                    f" (line {s['linedef']}, color {wall_color})\n")
            f.write(f"    .dw {v1_offset}, {v2_offset}"
                    f"    ; vertex byte offsets\n")
            f.write(f"    .db ${flags:02X}"
                    f"              ; flags\n")
            f.write(f"    .db {wall_color}"
                    f"              ; wallColor\n")
            f.write(f"    .db 0"
                    f"              ; pad\n")
            f.write(f"    .dw 0, 0"
                    f"           ; face, line (unused)\n")
        f.write("\n")

        # --- Sectors ---
        f.write(f"; --- Sectors ({len(sectors)}) ---\n")
        f.write("bsp_sectors:\n")
        for i, s in enumerate(sectors):
            f.write(f"    .dw {s['floor_h']}, {s['ceil_h']}, {s['light']}"
                    f"    ; sector {i}\n")
        f.write("\n")

    print(f"Generated {output_file} (Doom SNES format)")
    print(f"  {len(verts)} vertices ({len(verts)*RLX_SIZE} bytes)")
    print(f"  {len(segs)} segs ({len(segs)*RLG_SIZE} bytes)")
    print(f"  {len(ssectors)} areas ({len(ssectors)*RLA_SIZE} bytes)")
    print(f"  {len(nodes)} nodes ({len(nodes)*RLB_SIZE} bytes)")
    print(f"  {len(sectors)} sectors")


def generate_sin_cos_tables(output_file):
    """Generate 1.15 format sin/cos tables for GSU fmult+rol rotation."""
    with open(output_file, 'w') as f:
        f.write("; gsu_tables.asm -- Sin/Cos tables in 1.15 format for GSU fmult\n")
        f.write("; 256 entries each, 32767 = ~1.0\n")
        f.write("; Usage: fmult(value, sin_entry); rol -> value * sin(angle)\n\n")

        # Sin table
        f.write("sin_tbl:\n")
        for i in range(256):
            angle_rad = i * 2.0 * math.pi / 256.0
            val = round(math.sin(angle_rad) * 32767)
            val = max(-32768, min(32767, val))
            if i % 8 == 0:
                f.write("    .dw ")
            f.write(f"{val}")
            if i % 8 == 7:
                f.write(f"    ; {i-7}-{i}\n")
            else:
                f.write(", ")
        f.write("\n")

        # Cos table
        f.write("cos_tbl:\n")
        for i in range(256):
            angle_rad = i * 2.0 * math.pi / 256.0
            val = round(math.cos(angle_rad) * 32767)
            val = max(-32768, min(32767, val))
            if i % 8 == 0:
                f.write("    .dw ")
            f.write(f"{val}")
            if i % 8 == 7:
                f.write(f"    ; {i-7}-{i}\n")
            else:
                f.write(", ")
        f.write("\n")

    print(f"Generated {output_file}")
    print(f"  256 sin entries, 256 cos entries (1024 bytes total)")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} input.wad [output.asm]")
        print(f"       {sys.argv[0]} --tables output_tables.asm")
        sys.exit(1)

    if sys.argv[1] == '--tables':
        out_file = sys.argv[2] if len(sys.argv) > 2 else 'gsu_tables.asm'
        generate_sin_cos_tables(out_file)
    else:
        wad_file = sys.argv[1]
        out_file = sys.argv[2] if len(sys.argv) > 2 else 'bsp_data.asm'
        wad = WADReader(wad_file)
        generate_asm(wad, out_file)
