from pathlib import Path
import hashlib
import json
import numpy as np

out = Path(__file__).parent
cube = np.fromfunction(lambda y, x, b: 100 * (b + 1) + 10 * (y + 1) + x + 1, (4, 5, 3), dtype=int)
manifest = {}
for interleave, permutation in [('bsq', (2, 0, 1)), ('bil', (0, 2, 1)), ('bip', (0, 1, 2))]:
    for endian, dtype in [(0, '<u2'), (1, '>u2')]:
        stem = f'{interleave}-{endian}'
        payload = cube.transpose(permutation).astype(dtype).tobytes(order='C')
        prefix = b'HEADER_SENTINEL!'
        (out / f'{stem}.bin').write_bytes(prefix + payload + b'TRAILING_METADATA')
        (out / f'{stem}.hdr').write_text('ENVI\n' + f'samples = 5\nlines = 4\nbands = 3\nheader offset = {len(prefix)}\ndata type = 12\ninterleave = {interleave}\nbyte order = {endian}\ndata file = {stem}.bin\n')
with (out/'reference_SpecCube.dat').open('wb') as handle:
    handle.write(np.asarray([5,4,3],dtype='>f4').tobytes())
    handle.write(cube.transpose(1,0,2).astype('>f4').tobytes(order='C'))
for name, values, dtype in [
    ('int64-safe', [[-2, 0], [1, 2147483647]], '<i8'),
    ('int64-too-large', [[0, 2147483648]], '<i8'),
    ('uint64-too-large', [[0, 4294967296]], '<u8'),
    ('big-endian-int16', [[0, 1, 256], [-2, 3, 4]], '>i2')
]:
    np.save(out / name, np.asarray(values, dtype=dtype), allow_pickle=False)
for order in ['<', '>']:
    label = 'little' if order == '<' else 'big'
    for kind in ['i4', 'i8', 'u4', 'u8']:
        for name, value in [('max', 2147483647), ('overflow', 2147483648)]:
            if kind == 'i4' and name == 'overflow': continue
            np.save(out/f'{kind}-{label}-{name}.npy', np.array([[value]], dtype=order+kind))
        if kind.startswith('i'):
            for name, value in [('min', -2147483647), ('reserved', -2147483648), ('underflow', -2147483649)]:
                if kind == 'i4' and name == 'underflow': continue
                np.save(out/f'{kind}-{label}-{name}.npy', np.array([[value]], dtype=order+kind))
    stem = f'int32-{label}'
    (out/f'{stem}.bin').write_bytes(np.array([-2147483648, -2147483647, 0, 2147483647], dtype=order+'i4').tobytes())
    (out/f'{stem}.hdr').write_text(f'ENVI\nsamples = 4\nlines = 1\nbands = 1\ndata type = 3\ninterleave = bsq\nbyte order = {int(order == ">")}\n')
for path in sorted(out.iterdir()):
    if path.suffix in {'.bin', '.hdr', '.npy', '.dat'}:
        manifest[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
(out / 'sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'cube_yxb': cube.tolist(), 'files': len(manifest)}, indent=2))
