# Plain TIFF automatic fallback baseline (A26)

The reviewed runtime before T06 was loaded in a fresh R process. Only that process's tiff backend availability function was replaced with `function() FALSE`; no installed dependency or source file changed. Public `at_read_image()` then automatically read the independent uint16 RGB TIFF through the generic raster backend.

The expected first-band row is `111,112,113,114,115`. Actual output is `0,1,1,0,0`, with backend `raster` and dtype `uint8`. The archived JSON records those observations. The source fixture's logical dimensions are preserved, so checking dimensions alone would miss the quantitative loss.

This is a controlled availability simulation, not an actual minimal-library qualification. T07 must test an available lossless TIFF path or a clear missing raw-reader capability; explicit raster display conversion remains separately documented.
