"""Deterministic synthetic interoperability fixtures; no acquired image data."""
from pathlib import Path
import numpy as np
import tifffile

ROOT = Path(__file__).resolve().parent
META = {
    'axes': 'CYX',
    'UUID': 'urn:uuid:00000000-0000-0000-0000-000000000001',
    'PhysicalSizeX': 0.5, 'PhysicalSizeXUnit': 'µm',
    'PhysicalSizeY': 2.0, 'PhysicalSizeYUnit': 'µm',
    'Channel': {'Name': ['blue', 'green', 'red'],
                'EmissionWavelength': [450.0, 550.0, 650.0],
                'EmissionWavelengthUnit': ['nm', 'nm', 'nm']},
}
def cube(height, width):
    return np.fromfunction(lambda b, y, x: 100*(b+1) + 10*(y+1) + x+1,
                           (3, height, width), dtype=int).astype('uint16')
a = cube(4, 5)
tifffile.imwrite(ROOT/'reference.ome.tif', a, ome=True,
                 photometric='minisblack', metadata=META)
tifffile.imwrite(ROOT/'reference-rgb.tif', np.moveaxis(a, 0, -1), photometric='rgb')
a = cube(48, 64)
with tifffile.TiffWriter(ROOT/'reference-pyramid.ome.tif', ome=True) as t:
    t.write(a, subifds=2, photometric='minisblack', metadata=META)
    t.write(a[:, ::2, ::4], subfiletype=1, photometric='minisblack')
    t.write(a[:, ::4, ::8], subfiletype=1, photometric='minisblack')
mask = np.array([[0,1,1,0], [2,3,0,2], [0,0,3,3]], dtype='int32')
np.save(ROOT/'reference-c.npy', mask)
np.save(ROOT/'reference-f.npy', np.asfortranarray(mask))
for name, array in {
    'uint8': np.array([[0,1,127,255], [255,100,2,0]], dtype='uint8'),
    'uint16': np.array([[0,1,32767,65535], [65535,100,2,0]], dtype='uint16'),
    'int16': np.array([[-32768,-1,0,32767], [1,2,3,4]], dtype='int16'),
    'int32': np.array([[-2147483648, -1, 0, 2147483647]], dtype='int32'),
    'uint32': np.array([[0, 1, 2147483648, 4294967295]], dtype='uint32'),
    'float64': np.array([[-2, 0.5, np.nan, np.inf]], dtype='float64'),
    'float32': np.array([[-2,0.5,np.nan,np.inf], [3,4,5,6]], dtype='float32'),
}.items():
    tifffile.imwrite(ROOT/f'reference-{name}.tif', array, photometric='minisblack')
print(f'NumPy {np.__version__}; tifffile {tifffile.__version__}')

# Explicit unsupported-axis fixtures exercise selection guards.
for axes, shape in [('ZCYX', (2,3,4,5)), ('TCYX', (2,3,4,5))]:
    tifffile.imwrite(ROOT/f'reference-{axes}.ome.tif', np.zeros(shape,dtype='uint16'),
        ome=True, photometric='minisblack', metadata=dict(META, axes=axes))
import hashlib, json
(ROOT/'sha256.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sorted(ROOT.iterdir()) if p.suffix in {'.tif','.npy'}},indent=2)+'\n')
