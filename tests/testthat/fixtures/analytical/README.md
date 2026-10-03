# Independent analytical reference fixtures

This bundle is a deterministic synthetic oracle for numerical analysis. It was
written independently of annotatR and does not call an annotatR writer, reader,
ROI constructor, or rasterizer when calculating expected results. The committed
files are sufficient for mandatory tests; regeneration requires Python 3 and
NumPy 2.5.3. Run `python3 generate.py` here, or pass an output directory as the
first argument. `MD5SUMS` supports portable base-R integrity checks and
`SHA256SUMS` provides a stronger external manifest.

The 4 by 5 by 3 float32 BIP ENVI cube uses the zero-based formula
`100*(band+1) + 10*(y+1) + x+1` and wavelengths 450, 550, and 650 nm. It has
literal NaN, +Inf, -Inf, and NaN samples at y/x/band positions 0/0/0, 1/2/1,
2/3/2, and 3/4/2. Rectangle A is `[0,3) x [0,3)` and rectangle B is
`[2,5) x [1,4)`. Each selects nine cells; the bitfield uses A=1 and B=2,
yielding 16 unique foreground cells, two overlap cells with value 3, and four
background cells. Unique-union band 1 has 15 finite samples, one invalid sample,
sum 1937, and mean 1937/15. Pooling ROI memberships would count 18 samples and
is a different estimand. `cube.npy` is provenance/interchange data only; no
floating NPY mask-reader capability is claimed.

The categorical masks use background=0, A=1, B=2 and absent=3. The remapped
prediction uses background=0, A=2, B=1 and absent=3, and must be aligned by label.
Literal row-major pairing gives confusion rows/reference and columns/prediction
`[[3,1,0],[0,3,1],[1,0,3]]`, accuracy 3/4, kappa 5/8, and A/B Dice 3/4 and IoU
3/5. Zero-union absent-class Dice/IoU are undefined. Bitfields use membership
bits A=1, B=2, absent=4; A Dice/IoU are 1, B Dice is 3/5, B IoU is 3/7, and
exact membership-set agreement is 2/3. Categorical kappa is not defined for
bitfield sets. A background-only Cohen denominator is zero, so kappa is
undefined rather than 1. Python's `Fraction` calculates the exact ratios.

The non-unit calibration case has level-0 dimensions 10 by 8, level-1
dimensions 4 by 2, and level-0 pixel size 0.5 by 3 micrometres. Its stored
level-1 rectangle is 2 by 1: geometric area is 2 at level 1 and 20 at level 0;
physical area is 30 square micrometres. Calibration level is explicit, and this
oracle does not infer calibration from ambiguous legacy ROI attributes or equate
geometric area with raster-selected pixel count.

All files here are newly authored synthetic data under the repository's
`MIT + file LICENSE` terms. They contain no acquired, patient, vendor, or other
third-party image data. `optional-formats.json` inventories the already-reviewed
synthetic OME-TIFF and SpecCube samples, their qualification limits, and the
absence of vendor/acquired whole-slide qualification. Existing reader, mask,
and QuPath fixture trees remain the authoritative format-specific fixtures.
