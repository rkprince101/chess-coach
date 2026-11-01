"""Traces the flat piece silhouettes from the reference image into polygons
normalised to a 100x100 box (baseline y=95, king 88 units tall)."""
import sys
from collections import deque

from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
W, H = im.size
px = im.load()
ROW = (40, 360)  # white pieces (top row)


def fg(x, y):
    r, g, b = px[x, y]
    return min(r, g, b) < 225


# Column bands: x ranges containing foreground in the white row.
colon = [any(fg(x, y) for y in range(ROW[0], ROW[1], 2)) for x in range(W)]
bands, start = [], None
for x, on in enumerate(colon + [False]):
    if on and start is None:
        start = x
    if not on and start is not None:
        if x - start > 20:
            bands.append((start, x))
        start = None
names = ['pawn', 'rook', 'knight', 'bishop', 'queen', 'king']
assert len(bands) == 6, bands

# Supersample the mask 1x (already high res); threshold on a soft edge.
def components(x0, x1):
    seen = set()
    comps = []
    for y in range(ROW[0], ROW[1]):
        for x in range(x0, x1):
            if (x, y) in seen or not fg(x, y):
                continue
            q = deque([(x, y)])
            seen.add((x, y))
            pts = []
            while q:
                cx, cy = q.popleft()
                pts.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if x0 <= nx < x1 and ROW[0] <= ny < ROW[1] and (nx, ny) not in seen and fg(nx, ny):
                        seen.add((nx, ny))
                        q.append((nx, ny))
            if len(pts) > 50:
                comps.append(set(pts))
    return comps


DIRS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]


def trace(comp):
    """Moore-neighbour boundary trace (pixel centres), clockwise."""
    sy = min(y for _, y in comp)
    sx = min(x for x, y in comp if y == sy)
    start = (sx, sy)
    boundary = [start]
    cur, back = start, 4  # came from the west
    for _ in range(200000):
        found = False
        for i in range(8):
            d = (back + 1 + i) % 8
            nx, ny = cur[0] + DIRS[d][0], cur[1] + DIRS[d][1]
            if (nx, ny) in comp:
                back = (d + 4) % 8
                cur = (nx, ny)
                found = True
                break
        if not found:
            break
        if cur == start:
            break
        boundary.append(cur)
    return boundary


def dp(points, eps):
    if len(points) < 3:
        return points
    (x1, y1), (x2, y2) = points[0], points[-1]
    dx, dy = x2 - x1, y2 - y1
    norm = (dx * dx + dy * dy) ** 0.5 or 1
    best, idx = 0, 0
    for i in range(1, len(points) - 1):
        x0, y0 = points[i]
        d = abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1) / norm
        if d > best:
            best, idx = d, i
    if best > eps:
        return dp(points[:idx + 1], eps)[:-1] + dp(points[idx:], eps)
    return [points[0], points[-1]]


def simplify_closed(pts, eps):
    # Split the ring at the farthest point from the start so DP sees two arcs.
    far = max(range(len(pts)), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
    a = dp(pts[:far + 1], eps)
    b = dp(pts[far:] + [pts[0]], eps)
    return a[:-1] + b[:-1]


pieces = {}
for name, (x0, x1) in zip(names, bands):
    comps = components(x0, x1)
    polys = [simplify_closed(trace(c), 1.1) for c in comps]
    allpts = [p for c in comps for p in c]
    pieces[name] = (polys, allpts)

# Normalise: king height -> 88 units; baseline (max y) -> 95; centre on base.
king_pts = pieces['king'][1]
king_h = max(y for _, y in king_pts) - min(y for _, y in king_pts)
k = 88 / king_h
out = {}
for name, (polys, allpts) in pieces.items():
    bottom = max(y for _, y in allpts)
    base_xs = [x for x, y in allpts if y >= bottom - 3]
    cx = (min(base_xs) + max(base_xs)) / 2
    out[name] = [[(round(50 + (x - cx) * k, 2), round(95 + (y - bottom) * k, 2)) for x, y in poly] for poly in polys]
    print(name, 'components', len(polys), 'points', [len(p) for p in polys], file=sys.stderr)

# Emit Dart.
lines = []
for name, polys in out.items():
    lines.append(f'  Role.{name}: [')
    for poly in polys:
        flat = ', '.join(f'{x}, {y}' for x, y in poly)
        lines.append(f'    [{flat}],')
    lines.append('  ],')
print('\n'.join(lines))
