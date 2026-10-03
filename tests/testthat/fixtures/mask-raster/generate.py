"""Deterministic synthetic PNG fixtures, Python standard library only."""
import hashlib, pathlib, struct, zlib
root = pathlib.Path(__file__).parent

def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))

def png(name, rows, depth, colour=0, gamma=None, transparent=None):
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    head = struct.pack('>IIBBBBB', len(rows[0]) // channels, len(rows), depth, colour, 0, 0, 0)
    raw = b''.join(b'\0' + (bytes(row) if depth <= 8 else struct.pack('>' + 'H'*len(row), *row)) for row in rows)
    extra = chunk(b'gAMA', struct.pack('>I', gamma)) if gamma else b''
    if transparent is not None:
        extra += chunk(b'tRNS', struct.pack('>H', transparent))
    if colour == 3:
        extra += chunk(b'PLTE', b'\0\0\0\xff\xff\xff')
    (root / name).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', head) + extra + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))

reference = [[0,1,255,256],[4096,32767,32768,65535]]
png('gray16.png', reference, 16)
png('gray8-trns.png', [[0,1,255]], 8, transparent=1)
png('gray16-trns.png', [[0,256,65535]], 16, transparent=256)
# Even an unused transparency key declares unsupported transparency semantics.
png('gray16-trns-unused.png', [[0,256,65535]], 16, transparent=1)
for gamma in (20000,100000,220000):
    png(f'gray16-gamma{gamma}.png', reference, 16, gamma=gamma)
png('gray8.png', [[0,1,9,10],[13,32,128,255]], 8)
# The first binary sample is whitespace-valued: the PGM parser must retain it.
png('whitespace8.png', [[10,13,32,9],[35,0,1,255]], 8)
for depth in (8,16):
    for name, rows in [('zero', [[0,0,0],[0,0,0]]), ('binary', [[0,1,0],[1,0,1]]), ('extrema', [[0,2**depth-1,0],[2**depth-1,0,2**depth-1]])]:
        png(f'{name}{depth}.png', rows, depth)
png('rgb8.png', [[0,1,255,1,2,3]], 8, 2)
png('rgba8.png', [[0,1,255,255,1,2,3,0]], 8, 6)
png('grayalpha8.png', [[0,255,1,255]], 8, 4)
png('palette8.png', [[0,1]], 8, 3)
# One 1-bit pixel stored in the high bit of its scanline byte.
png('gray1.png', [[128]], 1)
(root / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in sorted(root.glob('*.png'))))
