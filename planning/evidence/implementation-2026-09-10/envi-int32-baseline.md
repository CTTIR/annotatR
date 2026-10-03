# ENVI signed 32-bit boundary probe

On the unchanged tracked baseline, both little- and big-endian ENVI files with literal int32 values `[-2147483648,-2147483647,0,2147483647]` return `[NA,-2147483647,0,2147483647]`. Python standard-library `struct.pack` wrote the independent 16-byte payloads; no package writer was used. Dimensions are width4, height1, one band, BSQ, ENVI type3.

R reserves the minimum signed integer for NA when read as an R integer. The image backend returns double arrays, which can represent this finite input exactly. T07 must preserve the full supported int32 range; the separate integer-mask NPY contract may reject this nonrepresentable R-integer sample. The diagnostic command completed with exit0 and is not a passing regression assertion. Raw values and payload hashes are in `envi-int32-baseline.json`; portable regression fixtures will be added by T07.
