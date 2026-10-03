"""Bounded generator: one tile in memory, no full-image array, synthetic only."""
import sys
from pathlib import Path
import numpy as np
import tifffile
root = Path(sys.argv[1]); root.mkdir(parents=True, exist_ok=True)
for side in (512, 16384):
    tile = np.full((256,256),7,dtype='uint16')
    with tifffile.TiffWriter(root/f'constant-{side}.ome.tif',ome=True) as writer:
        writer.write((tile for _ in range((side//256)**2)),shape=(side,side),dtype='uint16',
            tile=(256,256),compression='deflate',photometric='minisblack',
            metadata={'axes':'YX','UUID':'urn:uuid:00000000-0000-0000-0000-000000000003'})
    print(side, (root/f'constant-{side}.ome.tif').stat().st_size)
