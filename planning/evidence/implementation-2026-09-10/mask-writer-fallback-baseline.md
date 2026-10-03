# Optional TIFF mask writer baseline (A29)

The existing writer helper was run with a cloned function environment that reports `tiff` unavailable. This selected its Magick fallback without changing package source, installed dependencies, or global bindings. The known matrix was:

```text
    0     1   255   256
 4096 32767 32768 65535
```

Although `bits = 16` was requested, independent tifffile decoding found `uint64`, 64 bits per sample, and incorrect values. The archived TIFF and JSON preserve this baseline. Large raw values are also recorded as decimal strings to preserve exact uint64 values in consumers with limited numeric precision; SHA256 identifies the TIFF bytes.

The R reproduction intentionally reaches a `tiff::readTIFF(as.is = TRUE)` error because that reader does not support the unexpected 64-bit direct-read output. That exit is observed baseline failure, not a passing qualification. The script references the reviewed pre-T05 snapshot and a task-owned temporary output path; it is historical diagnostic evidence, not the future portable test runner.

T08 must test exact output depth, orientation and integer codes for the supported optional writer paths, or return an explicit missing-capability error before publishing an invalid output. This controlled branch simulation does not substitute for an actual minimal-dependency installation check.
