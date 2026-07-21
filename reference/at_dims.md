# Image dimensions at a pyramid level

Return the pixel dimensions `c(width, height)` of an
[annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
at a given pyramid level.

## Usage

``` r
at_dims(x, level = 0L, call = rlang::caller_env())
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- level:

  Integer pyramid level, `0` for full resolution. Must be in
  `0:(at_n_levels(x) - 1)`.

- call:

  The calling environment, for error reporting.

## Value

An integer vector of length 2, `c(width, height)`.

## See also

[`at_n_levels()`](https://cttir.github.io/annotatR/reference/at_n_levels.md),
[`at_is_pyramidal()`](https://cttir.github.io/annotatR/reference/at_is_pyramidal.md)

Other images:
[`annotatR-classes`](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
[`at_bands()`](https://cttir.github.io/annotatR/reference/at_bands.md),
[`at_example_image()`](https://cttir.github.io/annotatR/reference/at_example_image.md),
[`at_is_pyramidal()`](https://cttir.github.io/annotatR/reference/at_is_pyramidal.md),
[`at_is_spectral()`](https://cttir.github.io/annotatR/reference/at_is_spectral.md),
[`at_meta()`](https://cttir.github.io/annotatR/reference/at_meta.md),
[`at_n_bands()`](https://cttir.github.io/annotatR/reference/at_n_bands.md),
[`at_n_levels()`](https://cttir.github.io/annotatR/reference/at_n_levels.md),
[`at_pixel_size()`](https://cttir.github.io/annotatR/reference/at_pixel_size.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md),
[`at_wavelengths()`](https://cttir.github.io/annotatR/reference/at_wavelengths.md)

## Examples

``` r
# Image handles come from at_read_image(); see the images vignette.
```
