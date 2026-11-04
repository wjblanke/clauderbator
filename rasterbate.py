import struct, sys, math, zlib
bmp, out = sys.argv[1], sys.argv[2]
POSTER_W, POSTER_H = 15.16, 18.95          # inches
PAGE_W, PAGE_H, M = 8.5, 11.0, 0.25        # letter, 0.25" margins
args = sys.argv[3:]                         # any of: preview, jpeg, color
COLOR = "color" in args                     # dots take each cell's original colour instead of black
if "preview" in args:
    PAGE_W, PAGE_H, M = POSTER_W, POSTER_H + 0.5, 0.0
PW, PH = PAGE_W - 2*M, PAGE_H - 2*M        # printable 8 x 10.5

g = open(bmp).read().split('\n')
w, h = map(int, g[0].split())
rgb = [[tuple(map(float, v.split(','))) for v in g[1+r].split()] for r in range(h)]
lum = [[0.299*R + 0.587*G + 0.114*B for R, G, B in row] for row in rgb]

# stretch contrast to the 2nd-98th percentile so the dark photo uses the full dot range
flat = sorted(v for row in lum for v in row)
lo, hi = flat[int(len(flat)*0.12)], flat[int(len(flat)*0.995)]
lum = [[min(1, max(0, (v-lo)/(hi-lo))) ** 0.6 for v in row] for row in lum]   # gamma lifts mid-tones

def dot(r, c):
    """(radius as a fraction of half a cell, rgb 0-1 colour) for one dot, or None to leave it out."""
    if COLOR: return 1.0, rgb[r][c]         # full-size dots in the original colour
    dark = 1 - lum[r][c]
    return (math.sqrt(dark), (0, 0, 0)) if dark >= 0.02 else None

cell = POSTER_W / w                         # inches per dot cell
K = 0.5523
def circle(cx, cy, r):
    k = K*r
    return (f"{cx+r:.2f} {cy:.2f} m "
            f"{cx+r:.2f} {cy+k:.2f} {cx+k:.2f} {cy+r:.2f} {cx:.2f} {cy+r:.2f} c "
            f"{cx-k:.2f} {cy+r:.2f} {cx-r:.2f} {cy+k:.2f} {cx-r:.2f} {cy:.2f} c "
            f"{cx-r:.2f} {cy-k:.2f} {cx-k:.2f} {cy-r:.2f} {cx:.2f} {cy-r:.2f} c "
            f"{cx+k:.2f} {cy-r:.2f} {cx+r:.2f} {cy-k:.2f} {cx+r:.2f} {cy:.2f} c f\n")

if "jpeg" in args:
    # 4x6" photo tiles at 300 dpi instead of a PDF; `out` is a folder. Dots are drawn straight
    # into a pixel buffer, saved as PNG with zlib, then converted to JPEG by macOS's built-in sips.
    import os, subprocess
    DPI, OV = 300, 0.5
    def grid(tw, th): return (1 + max(0, math.ceil((POSTER_W - tw) / (tw - OV))),
                              1 + max(0, math.ceil((POSTER_H - th) / (th - OV))))
    # portrait or landscape photos, whichever needs fewer prints
    TW, TH = min([(4.0, 6.0), (6.0, 4.0)], key=lambda t: grid(*t)[0] * grid(*t)[1])
    cols, rows = grid(TW, TH)
    BW, BH = round(POSTER_W*DPI), round(POSTER_H*DPI)
    NC = 3 if COLOR else 1                                      # bytes per pixel: RGB or grey
    canvas = bytearray(b'\xff') * (BW*BH*NC)
    for r in range(h):
        for c in range(w):
            d = dot(r, c)
            if d is None: continue
            rad = (cell/2) * d[0] * DPI
            px = bytes(round(v*255) for v in d[1]) if COLOR else b'\x00'
            cx, cy = (c+0.5)*cell*DPI, (r+0.5)*cell*DPI
            for y in range(max(0, int(cy-rad)), min(BH, int(cy+rad)+1)):
                dy = y + 0.5 - cy
                if abs(dy) > rad: continue
                hw = math.sqrt(rad*rad - dy*dy)
                x0, x1 = max(0, round(cx-hw)), min(BW, round(cx+hw))
                if x1 > x0: canvas[(y*BW+x0)*NC:(y*BW+x1)*NC] = px * (x1-x0)
    def png(path, rows_, wpx):
        ch = lambda t, b: struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t+b))
        raw = b''.join(b'\x00' + bytes(r) for r in rows_)
        open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', wpx, len(rows_), 8, 2 if NC == 3 else 0, 0, 0, 0))
                               + ch(b'IDAT', zlib.compress(raw, 6)) + ch(b'IEND', b''))
    TPW, TPH, o, DASH = round(TW*DPI), round(TH*DPI), round(OV*DPI), 30
    os.makedirs(out, exist_ok=True)
    for pr in range(rows):
        for pc in range(cols):
            X0, Y0 = round(pc*(TW-OV)*DPI), round(pr*(TH-OV)*DPI)
            cw, chh = min(TPW, BW-X0), min(TPH, BH-Y0)          # artwork extent; rest is white
            tile = []
            for y in range(TPH):
                row = bytearray(canvas[((Y0+y)*BW+X0)*NC:((Y0+y)*BW+X0+cw)*NC]) if y < chh else bytearray()
                tile.append(row + b'\xff' * (TPW*NC - len(row)))
            # dashed grey lines mark the 0.5" overlap zones shared with neighbouring photos
            for x in ([o] if pc > 0 else []) + ([cw-o] if pc < cols-1 else []):
                for y in range(chh):
                    if (y // DASH) % 2 == 0: tile[y][(x-1)*NC:(x+2)*NC] = b'\x80' * 3*NC
            for y in ([o] if pr > 0 else []) + ([chh-o] if pr < rows-1 else []):
                for yy in (y-1, y, y+1):
                    for x in range(0, cw, 2*DASH): tile[yy][x*NC:min(cw, x+DASH)*NC] = b'\x80' * ((min(cw, x+DASH) - x)*NC)
            base = os.path.join(out, f"row{pr+1}_col{pc+1}")
            png(base + ".png", tile, TPW)
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "92", "-s", "dpiWidth", str(DPI),
                            "-s", "dpiHeight", str(DPI), base + ".png", "--out", base + ".jpg"], check=True, capture_output=True)
            os.remove(base + ".png")
    print(f"{w}x{h} dots, {rows} rows x {cols} cols = {rows*cols} photos of {TW:g}x{TH:g} in ({TPW}x{TPH} px @ {DPI} dpi) -> {out}")
    sys.exit()

OV = 0.0 if PW >= POSTER_W else 0.5        # 0.5" overlap shared by neighbouring pages
SX, SY = PW - OV, PH - OV                   # step between tile origins
cols = 1 + max(0, math.ceil((POSTER_W - PW) / SX)); rows = 1 + max(0, math.ceil((POSTER_H - PH) / SY))
pages = []
for pr in range(rows):
    for pc in range(cols):
        x0, y0 = pc*SX, pr*SY                       # poster-inch origin of this tile (top-left)
        tw, th = min(PW, POSTER_W-x0), min(PH, POSTER_H-y0)
        s = ["0 g\n"]
        # clip to tile area
        s.append(f"q {M*72:.2f} {(PAGE_H-M-th)*72:.2f} {tw*72:.2f} {th*72:.2f} re W n\n")
        for r in range(h):
            cy = (r+0.5)*cell
            if cy < y0-cell or cy > y0+th+cell: continue
            for c in range(w):
                cx = (c+0.5)*cell
                if cx < x0-cell or cx > x0+tw+cell: continue
                d = dot(r, c)
                if d is None: continue
                rad = (cell/2) * d[0]
                px = (M + cx - x0)*72
                py = (PAGE_H - M - (cy - y0))*72
                if COLOR: s.append("%.3f %.3f %.3f rg " % d[1])
                s.append(circle(px, py, rad*72))
        s.append("Q\n")
        # thin grey trim guide + label
        s.append(f"0.6 G 0.3 w {M*72:.2f} {(PAGE_H-M-th)*72:.2f} {tw*72:.2f} {th*72:.2f} re S\n")
        # dashed lines mark the overlap zones shared with neighbouring pages
        L, T = M*72, (PAGE_H-M)*72; B = T - th*72; R = L + tw*72; o = OV*72
        s.append("0.45 G 0.4 w [3 3] 0 d\n")
        if pc > 0:      s.append(f"{L+o:.2f} {B:.2f} m {L+o:.2f} {T:.2f} l S\n")
        if pc < cols-1: s.append(f"{R-o:.2f} {B:.2f} m {R-o:.2f} {T:.2f} l S\n")
        if pr > 0:      s.append(f"{L:.2f} {T-o:.2f} m {R:.2f} {T-o:.2f} l S\n")
        if pr < rows-1: s.append(f"{L:.2f} {B+o:.2f} m {R:.2f} {B+o:.2f} l S\n")
        s.append("[] 0 d\n")
        lab = f"Row {pr+1} Col {pc+1}  (page {pr*cols+pc+1} of {rows*cols})  - poster {POSTER_W} x {POSTER_H} in - dashed lines = {OV} in overlap"
        s.append(f"0.5 g BT /F1 7 Tf {M*72:.2f} {(M*72)/2-2:.2f} Td ({lab}) Tj ET\n")
        pages.append("".join(s).encode())

objs = []
def add(b): objs.append(b); return len(objs)
font = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
pages_id = len(objs) + 1 + 2*len(pages)  # placeholder computed below
kids = []
content_ids = []
for p in pages:
    z = zlib.compress(p)
    content_ids.append(add(b"<< /Length %d /Filter /FlateDecode >>\nstream\n" % len(z) + z + b"\nendstream"))
page_ids = []
pages_id = len(objs) + len(pages) + 1
for cid in content_ids:
    page_ids.append(add(b"<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %d %d] /Contents %d 0 R /Resources << /Font << /F1 %d 0 R >> >> >>"
                        % (pages_id, PAGE_W*72, PAGE_H*72, cid, font)))
assert add(b"<< /Type /Pages /Count %d /Kids [%s] >>" % (len(page_ids), " ".join(f"{i} 0 R" for i in page_ids).encode())) == pages_id
cat = add(b"<< /Type /Catalog /Pages %d 0 R >>" % pages_id)
outb = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"); xref = []
for i, o in enumerate(objs, 1):
    xref.append(len(outb)); outb += b"%d 0 obj\n" % i + o + b"\nendobj\n"
xs = len(outb)
outb += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs)+1) + b"".join(b"%010d 00000 n \n" % x for x in xref)
outb += b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs)+1, cat, xs)
open(out, 'wb').write(outb)
print(f"{w}x{h} dots, cell {cell:.3f} in, {rows}x{cols} = {len(pages)} letter pages -> {out}")
