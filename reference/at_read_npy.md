# Read a NumPy `.npy` integer mask

Read a NumPy integer array (e.g. a ground-truth annotation mask) into a
lossless `annot_mask` – values are preserved exactly, including
composite bitfield codes. Use this (not
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
which polygonises) when the raw integer matrix is what you need, for
example to derive a training mask or compute agreement against another
mask.

## Usage

``` r
at_read_npy(
  path,
  level = 0L,
  transpose = FALSE,
  legend = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- path:

  Path to a `.npy` file.

- level:

  Integer pyramid level to record. Default `0`.

- transpose:

  Logical; transpose the array on read, for files stored in the native
  cube order `(width, height)` = `[x, y]` (e.g. TIVITA/HyperGui masks)
  so the result lands in annotatR's `[y, x]` convention. Default `FALSE`
  assumes the standard image convention `(height, width)`.

- legend:

  Optional legend tibble (`value`, `label`) overriding the sidecar /
  pixel-value labelling.

- call:

  The calling environment, for error reporting.

## Value

An `annot_mask`.

## See also

[`at_write_npy()`](https://cttir.github.io/annotatR/reference/at_write_npy.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md)

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/annotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/annotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/annotatR/reference/at_write_npy.md)

## Examples

``` r
m <- at_mask(at_example_project(), "labelled")
f <- tempfile(fileext = ".npy")
at_write_npy(m, f)
at_read_npy(f)
#> <annot_mask> labelled  |  512 x 512 px  |  level 0
#> values: 3
#> # A tibble: 3 × 6
#>   value label    layer   roi_id         n_px colour 
#>   <int> <chr>    <chr>   <chr>         <int> <chr>  
#> 1     1 tumour   regions roi_000000049 19600 #999999
#> 2     2 necrosis regions roi_000000050 72704 #E69F00
#> 3     3 stroma   regions roi_000000051 34200 #56B4E9
```
