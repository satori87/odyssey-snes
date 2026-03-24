#!/usr/bin/env python3
"""Generate BSP tree from a grid map, following Noah's Ark 3D format.

BSP node (5 bytes): plane(1), dir(1), children[2](2+2 = but packed as 2 bytes)
Actually Noah uses: plane(1), dir(1), children[0](2), children[1](2) = 6 bytes per node
BSP seg  (6 bytes): plane(1), dir(1), min(1), max(1), texture(1), area(1)

Both stored in same array. Segs have DIR_SEGFLAG (0x80) set.

For a grid map, we extract wall faces and build an axis-aligned BSP tree.
"""

import sys

# Map data (same as data/map.h)
MAP_W = 10
MAP_H = 10
world_map = [
    [1,1,1,1,1,1,1,1,1,1],
    [1,0,0,0,0,0,0,0,0,1],
    [1,0,0,0,0,0,0,0,0,1],
    [1,0,0,0,0,0,0,0,0,1],
    [1,0,0,0,2,2,0,0,0,1],
    [1,0,0,0,2,2,0,0,0,1],
    [1,0,0,0,0,0,0,0,0,1],
    [1,0,0,0,0,0,0,0,0,1],
    [1,0,0,0,0,0,0,0,0,1],
    [1,1,1,1,1,1,1,1,1,1],
]

# Noah's BSP format constants
DIR_SEGFLAG = 0x80
DIR_LASTSEGFLAG = 0x40

# Directions (di_north=0, di_east=1, di_south=2, di_west=3)
DI_NORTH = 0  # wall faces north (player south of wall)
DI_EAST = 1   # wall faces east
DI_SOUTH = 2  # wall faces south
DI_WEST = 3   # wall faces west


class WallSeg:
    """A wall segment (face of a solid tile)."""
    def __init__(self, plane, direction, seg_min, seg_max, texture):
        self.plane = plane      # coordinate in half-tiles
        self.direction = direction  # DI_NORTH/SOUTH/EAST/WEST
        self.seg_min = seg_min  # min extent in half-tiles
        self.seg_max = seg_max  # max extent in half-tiles
        self.texture = texture  # wall type


def extract_walls():
    """Extract wall faces from the grid map."""
    walls = []
    for y in range(MAP_H):
        for x in range(MAP_W):
            if world_map[y][x] == 0:
                continue
            tex = world_map[y][x]
            # Check each adjacent empty cell — that's where a wall face is visible
            # North face (y-1 is empty): wall at y*2, normal points NORTH
            if y > 0 and world_map[y-1][x] == 0:
                walls.append(WallSeg(y * 2, DI_NORTH, x * 2, (x + 1) * 2, tex))
            # South face (y+1 is empty): wall at (y+1)*2, normal points SOUTH
            if y < MAP_H - 1 and world_map[y+1][x] == 0:
                walls.append(WallSeg((y + 1) * 2, DI_SOUTH, x * 2, (x + 1) * 2, tex))
            # West face (x-1 is empty): wall at x*2, normal points WEST
            if x > 0 and world_map[y][x-1] == 0:
                walls.append(WallSeg(x * 2, DI_WEST, y * 2, (y + 1) * 2, tex))
            # East face (x+1 is empty): wall at (x+1)*2, normal points EAST
            if x < MAP_W - 1 and world_map[y][x+1] == 0:
                walls.append(WallSeg((x + 1) * 2, DI_EAST, y * 2, (y + 1) * 2, tex))
    return walls


def merge_colinear(walls):
    """Merge adjacent colinear wall segments on the same plane."""
    merged = []
    # Group by (plane, direction)
    groups = {}
    for w in walls:
        key = (w.plane, w.direction)
        if key not in groups:
            groups[key] = []
        groups[key].append(w)

    for key, segs in groups.items():
        # Sort by min extent
        segs.sort(key=lambda s: s.seg_min)
        # Merge adjacent segments with same texture
        current = segs[0]
        for s in segs[1:]:
            if s.seg_min == current.seg_max and s.texture == current.texture:
                current.seg_max = s.seg_max
            else:
                merged.append(current)
                current = s
        merged.append(current)

    return merged


def is_vertical(direction):
    """Is this a vertical (x-aligned) wall?"""
    return direction in (DI_EAST, DI_WEST)


class BSPNode:
    """Internal BSP node."""
    def __init__(self, plane, is_vertical, front, back):
        self.plane = plane        # split coordinate (half-tiles)
        self.is_vertical = is_vertical
        self.front = front        # front child (node or seg list)
        self.back = back          # back child


def build_bsp(walls, depth=0):
    """Build BSP tree from wall segments using axis-aligned splits."""
    if not walls:
        return None

    # If all walls are on the same plane, return as segment chain
    planes = set((w.plane, is_vertical(w.direction)) for w in walls)
    if len(planes) == 1:
        return walls  # Terminal: list of segs

    # Choose split plane: alternate between vertical and horizontal
    # Use median of available planes
    v_planes = sorted(set(w.plane for w in walls if is_vertical(w.direction)))
    h_planes = sorted(set(w.plane for w in walls if not is_vertical(w.direction)))

    # Pick the split that best divides the walls
    best_split = None
    best_score = len(walls) + 1

    for plane in v_planes:
        front = [w for w in walls if not is_vertical(w.direction) or w.plane >= plane]
        back = [w for w in walls if not is_vertical(w.direction) or w.plane <= plane]
        # Don't count walls ON the plane in both
        on_plane = [w for w in walls if is_vertical(w.direction) and w.plane == plane]
        score = abs(len(front) - len(back))
        if score < best_score and len(front) < len(walls) and len(back) < len(walls):
            best_split = (plane, True)
            best_score = score

    for plane in h_planes:
        front = [w for w in walls if is_vertical(w.direction) or w.plane >= plane]
        back = [w for w in walls if is_vertical(w.direction) or w.plane <= plane]
        score = abs(len(front) - len(back))
        if score < best_score and len(front) < len(walls) and len(back) < len(walls):
            best_split = (plane, False)
            best_score = score

    if best_split is None:
        # Can't split further, return as seg list
        return walls

    split_plane, split_vert = best_split

    # Partition walls
    front_walls = []
    back_walls = []
    for w in walls:
        w_vert = is_vertical(w.direction)
        if split_vert:
            if w_vert and w.plane == split_plane:
                # On the split plane — put in both
                front_walls.append(w)
                back_walls.append(w)
            elif w_vert:
                if w.plane > split_plane:
                    front_walls.append(w)
                else:
                    back_walls.append(w)
            else:
                # Horizontal walls go in both
                front_walls.append(w)
                back_walls.append(w)
        else:
            if not w_vert and w.plane == split_plane:
                front_walls.append(w)
                back_walls.append(w)
            elif not w_vert:
                if w.plane > split_plane:
                    front_walls.append(w)
                else:
                    back_walls.append(w)
            else:
                front_walls.append(w)
                back_walls.append(w)

    front = build_bsp(front_walls, depth + 1)
    back = build_bsp(back_walls, depth + 1)

    return BSPNode(split_plane, split_vert, front, back)


def flatten_bsp(node, data=None, index=None):
    """Flatten BSP tree into linear array of nodes/segs.
    Returns index of this node in the array."""
    if data is None:
        data = []
        index = [0]

    if node is None:
        return 0xFFFF  # null

    if isinstance(node, list):
        # Segment chain (terminal node)
        first_idx = index[0]
        for i, seg in enumerate(node):
            is_last = (i == len(node) - 1)
            entry = {
                'type': 'seg',
                'plane': seg.plane,
                'dir': DIR_SEGFLAG | (DIR_LASTSEGFLAG if is_last else 0) | seg.direction,
                'min': seg.seg_min,
                'max': seg.seg_max,
                'texture': seg.texture,
                'area': 0,
            }
            data.append(entry)
            index[0] += 1
        return first_idx

    if isinstance(node, BSPNode):
        # Reserve slot for this node
        my_idx = index[0]
        data.append(None)  # placeholder
        index[0] += 1

        # Flatten children
        front_idx = flatten_bsp(node.front, data, index)
        back_idx = flatten_bsp(node.back, data, index)

        # Fill in node data
        dir_byte = 1 if node.is_vertical else 0  # or_vertical=1, or_horizontal=0
        data[my_idx] = {
            'type': 'node',
            'plane': node.plane,
            'dir': dir_byte,
            'children': [front_idx, back_idx],
        }
        return my_idx

    return 0xFFFF


def write_bsp_header(filename, data, walls):
    """Write BSP data as C header file."""
    with open(filename, 'w') as f:
        f.write("/* BSP tree data for 10x10 test map */\n")
        f.write("/* Generated by generate_bsp.py */\n\n")
        f.write(f"#define BSP_NUM_ENTRIES {len(data)}\n\n")

        # Write as flat byte array (nodes=6 bytes, segs=6 bytes)
        f.write("/* BSP data: nodes and segments interleaved */\n")
        f.write("/* Node: plane(1), dir(1), child0_lo(1), child0_hi(1), child1_lo(1), child1_hi(1) */\n")
        f.write("/* Seg:  plane(1), dir(1), min(1), max(1), texture(1), area(1) */\n")
        f.write(f"const u8 bsp_data[{len(data) * 6}] = {{\n")

        for i, entry in enumerate(data):
            if entry['type'] == 'node':
                c0 = entry['children'][0]
                c1 = entry['children'][1]
                f.write(f"    /* [{i}] node: plane={entry['plane']}, "
                        f"{'vert' if entry['dir']==1 else 'horiz'}, "
                        f"children=[{c0},{c1}] */\n")
                f.write(f"    {entry['plane']}, {entry['dir']}, "
                        f"{c0 & 0xFF}, {(c0 >> 8) & 0xFF}, "
                        f"{c1 & 0xFF}, {(c1 >> 8) & 0xFF},\n")
            else:
                f.write(f"    /* [{i}] seg: plane={entry['plane']}, "
                        f"dir=${entry['dir']:02X}, "
                        f"span={entry['min']}-{entry['max']}, "
                        f"tex={entry['texture']} */\n")
                f.write(f"    {entry['plane']}, {entry['dir']}, "
                        f"{entry['min']}, {entry['max']}, "
                        f"{entry['texture']}, {entry['area']},\n")

        f.write("};\n")


def main():
    print("Extracting walls from 10x10 map...")
    walls = extract_walls()
    print(f"  {len(walls)} raw wall faces")

    walls = merge_colinear(walls)
    print(f"  {len(walls)} merged segments")
    for w in walls:
        dirs = ['N', 'E', 'S', 'W']
        print(f"    plane={w.plane} dir={dirs[w.direction]} "
              f"span={w.seg_min}-{w.seg_max} tex={w.texture}")

    print("\nBuilding BSP tree...")
    tree = build_bsp(walls)

    print("Flattening to linear array...")
    data = []
    flatten_bsp(tree, data, [0])
    print(f"  {len(data)} entries ({len(data)*6} bytes)")

    write_bsp_header("data/bsp_map.h", data, walls)
    print("  Written to data/bsp_map.h")


if __name__ == "__main__":
    main()
