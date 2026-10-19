"""1.33: icon.ico из icon.png — малые размеры BMP (Проводник Windows показывает их надёжнее), крупные PNG."""
import io, struct, sys
from PIL import Image

def bmp_entry(im):
    w, h = im.size
    px = im.tobytes("raw", "BGRA")
    rows = [px[y * w * 4:(y + 1) * w * 4] for y in range(h)][::-1]
    xor = b"".join(rows)
    mask_row = ((w + 31) // 32) * 4
    andm = b"\x00" * (mask_row * h)
    hdr = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, len(xor) + len(andm), 0, 0, 0, 0)
    return hdr + xor + andm

def main(src, dst):
    im = Image.open(src).convert("RGBA")
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    blobs = []
    for s in sizes:
        r = im.resize((s, s), Image.LANCZOS)
        if s <= 48:
            blobs.append(bmp_entry(r))
        else:
            b = io.BytesIO(); r.save(b, "PNG", optimize=True); blobs.append(b.getvalue())
    out = struct.pack("<HHH", 0, 1, len(sizes))
    off = 6 + 16 * len(sizes)
    for s, b in zip(sizes, blobs):
        out += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(b), off)
        off += len(b)
    open(dst, "wb").write(out + b"".join(blobs))

main(sys.argv[1] if len(sys.argv) > 1 else "icon.png", sys.argv[2] if len(sys.argv) > 2 else "icon.ico")
