"""Generate a small deterministic PNG (white frame, black interior, white 'text' bars) so the
vision probe has an input whose correct answer exists ONLY in the pixels."""
import struct
import zlib

W = H = 96


def px(x, y):
    if x < 6 or x >= W - 6 or y < 6 or y >= H - 6:
        return (255, 255, 255)          # white frame
    # four white horizontal bars on black = a shape only the image can describe
    if 30 <= y <= 36 and 20 <= x <= 70:
        return (255, 255, 255)
    if 46 <= y <= 52 and 20 <= x <= 55:
        return (255, 255, 255)
    if 62 <= y <= 68 and 20 <= x <= 40:
        return (255, 255, 255)
    return (0, 0, 0)


raw = b"".join(b"\x00" + b"".join(bytes(px(x, y)) for x in range(W)) for y in range(H))


def chunk(t, d):
    c = t + d
    return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)


png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 9))
       + chunk(b"IEND", b""))
open("reports/hd474-laptop-leg/raw/bars.png", "wb").write(png)
print("bars.png bytes", len(png), "| ground truth: 3 white bars on black, inside a white frame")
