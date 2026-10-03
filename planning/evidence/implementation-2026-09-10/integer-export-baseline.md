# Signed integer export baseline

A NumPy-generated int32 mask `[[−2, −40000]]` was read through public `at_read_npy()` and exported through public `at_write_npy()`. Independent NumPy decoding found silent wraparound: uint8 output `[[254,192]]`, int16 output `[[−2,25536]]`. Values outside the selected dtype's range must be rejected before writing; valid signed values remain supported.

The probe used the reviewed source snapshot before T05, with the original integer writer unchanged. Input and outputs are in `/tmp/annotatr-roadmap-integer-export-probe`; the archived JSON records the exact observations. T07 includes the correction under its integer-range validation work.

Input generation:

```python
import numpy as np
np.save('input.npy', np.array([[-2, -40000]], dtype='<i4'))
```

Public R path:

```r
m <- at_read_npy('input.npy')
at_write_npy(m, 'uint8.npy', dtype = 'uint8', legend = FALSE)
at_write_npy(m, 'int16.npy', dtype = 'int16', legend = FALSE)
```

Independent output check: `np.load('uint8.npy')` and `np.load('int16.npy')`.
