"""Independent synthetic OME scalar windows, NumPy/tifffile; fixed OME UUID."""
from pathlib import Path
import hashlib, json
import numpy as np
import tifffile
root = Path(__file__).resolve().parent
cases = {
    'uint8': [0,1,127,255,255,100,2,0],
    'uint16': [0,1,32767,65535,65535,100,2,0],
    'int16': [-32768,-1,0,32767,1,2,3,4],
    'int32': [-2147483648,-1,0,2147483647,1,2,3,4],
    'uint32': [0,1,2147483648,4294967295,1,2,3,4],
    'float32': [-2,0.5,np.nan,np.inf,-np.inf,4,5,6],
    'float64': [-2,0.5,np.nan,np.inf,-np.inf,4,5,6],
}
for dtype, values in cases.items():
    a = np.array(values,dtype=dtype).reshape(2,4)
    tifffile.imwrite(root/f'{dtype}.ome.tif',a,ome=True,photometric='minisblack',
        metadata={'axes':'YX','UUID':'urn:uuid:00000000-0000-0000-0000-000000000002'})
(root/'sha256.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sorted(root.glob('*.tif'))},indent=2)+'\n')
print(f'NumPy {np.__version__}; tifffile {tifffile.__version__}')
