# Compute a registered band view

Evaluate one of
[`at_band_operations()`](https://cttir.github.io/annotatR/reference/at_band_operations.md)
on a window of an image. The result is a display product: a `[y, x, k]`
array (`k = 3` for `"rgb"`, otherwise 1) with provenance attributes,
which annotatR never uses as analysis input.

## Usage

``` r
at_band_view(
  img,
  operation = "rgb",
  bands = NULL,
  params = list(),
  level = 0L,
  xrange = NULL,
  yrange = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- img:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- operation:

  A registered operation name.

- bands:

  Band indices (defaults depend on the operation).

- params:

  Named list of operation parameters.

- level, xrange, yrange:

  Passed to
  [`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md).

- call:

  The calling environment, for error reporting.

## Value

A numeric array with attributes `operation`, `bands`, `wavelengths`,
`params`, `parent_digest`, `transform_digest`, `level` and
`display_product = TRUE`.

## See also

Other hsi:
[`at_band_operations()`](https://cttir.github.io/annotatR/reference/at_band_operations.md),
[`at_convert_values()`](https://cttir.github.io/annotatR/reference/at_convert_values.md),
[`at_cubert_export_envi()`](https://cttir.github.io/annotatR/reference/at_cubert_export_envi.md),
[`at_hsi_meta()`](https://cttir.github.io/annotatR/reference/at_hsi_meta.md),
[`at_read_stats()`](https://cttir.github.io/annotatR/reference/at_read_stats.md),
[`at_tivita_profile()`](https://cttir.github.io/annotatR/reference/at_tivita_profile.md)

## Examples

``` r
cube <- at_example_image("cube")
v <- at_band_view(cube, "normalized_difference", bands = c(30, 10))
attr(v, "operation")
#> [1] "normalized_difference"
```
