# Read a mask into editable ROIs

Polygonise an existing mask file (e.g. Cellpose, StarDist, or QuPath
output, or a prior annotatR export) into an editable
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md).
A sidecar `<path>.legend.json` is used to recover labels when present.

## Usage

``` r
at_read_mask(
  path,
  level = 0L,
  connectivity = c(8L, 4L),
  simplify = 0,
  min_area = 0,
  legend = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- path:

  Path to a mask file (TIFF, PNG, or RDS).

- level:

  Integer pyramid level to record on the ROIs. Default `0`.

- connectivity:

  `8` (default) or `4` pixel connectivity.

- simplify:

  Non-negative simplification tolerance for the polygons.

- min_area:

  Minimum polygon area in pixels to keep. Default `0`.

- legend:

  Optional legend tibble (`value`, `label`) overriding the sidecar /
  pixel-value labelling.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with one ROI per connected region.

## See also

[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md)

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/annotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/annotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_npy()`](https://cttir.github.io/annotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/annotatR/reference/at_write_npy.md)

## Examples

``` r
m <- at_mask(at_example_project(), "labelled")
f <- tempfile(fileext = ".tif")
at_write_mask(m, f)
at_read_mask(f)
#> <annot_layer> file25e42eb9b6c4
#> ROIs: 3  |  labels: "necrosis", "tumour", and "stroma"
#> visible: TRUE  |  locked: FALSE  |  z: 1
```
