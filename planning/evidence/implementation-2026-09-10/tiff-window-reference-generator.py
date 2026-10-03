from pathlib import Path
import sys
import numpy as np
import tifffile

out = Path(sys.argv[1])
values = np.arange(12, dtype=np.uint16).reshape(3, 4)
metadata = '<GDALMetadata><Item name="SCALE" sample="0" role="scale">2</Item><Item name="OFFSET" sample="0" role="offset">10</Item></GDALMetadata>'
tifffile.imwrite(out, values, metadata=None, extratags=[(42112, 's', 0, metadata, False), (42113, 's', 0, '0', False)])
