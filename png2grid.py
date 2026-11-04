# Decode a PNG (stdlib only) and average it down to a COLSxROWS grid of luminance values, written as a 24-bit BMP-free text grid
import zlib, struct, sys
src, out, COLS, ROWS = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
d = open(src, 'rb').read(); assert d[:8] == b'\x89PNG\r\n\x1a\n'
i = 8; idat = b''
while i < len(d):
    n, t = struct.unpack_from('>I4s', d, i); body = d[i+8:i+8+n]; i += 12 + n
    if t == b'IHDR': w, h, bd, ct, _, _, il = struct.unpack('>IIBBBBB', body)
    elif t == b'IDAT': idat += body
assert bd == 8 and il == 0 and ct in (2, 6), (bd, ct, il)
bpp = 3 if ct == 2 else 4
raw = zlib.decompress(idat); st = w * bpp
rows = []; prev = bytearray(st); p = 0
for y in range(h):
    f = raw[p]; line = bytearray(raw[p+1:p+1+st]); p += 1 + st
    for x in range(st):
        a = line[x-bpp] if x >= bpp else 0; b = prev[x]; c = prev[x-bpp] if x >= bpp else 0
        if f == 1: line[x] = (line[x] + a) & 255
        elif f == 2: line[x] = (line[x] + b) & 255
        elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
        elif f == 4:
            pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2*c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    rows.append(line); prev = line
with open(out, 'w') as o:
    o.write(f"{COLS} {ROWS}\n")
    for r in range(ROWS):
        y0, y1 = r*h//ROWS, (r+1)*h//ROWS; vals = []
        for c in range(COLS):
            x0, x1 = c*w//COLS, (c+1)*w//COLS; sr = sg = sb = n = 0
            for y in range(y0, y1):
                L = rows[y]
                for x in range(x0, x1):
                    k = x*bpp; sr += L[k]; sg += L[k+1]; sb += L[k+2]; n += 1
            vals.append(f"{sr/n/255:.4f},{sg/n/255:.4f},{sb/n/255:.4f}")   # average r,g,b of the cell
        o.write(" ".join(vals) + "\n")
print(w, h, "->", COLS, ROWS)
