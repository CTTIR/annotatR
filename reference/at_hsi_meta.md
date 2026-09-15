# Hyperspectral and acquisition metadata of an image

Return the backend-agnostic metadata record annotatR keeps for an image:
acquisition identity, storage layout, value semantics, geometry
convention, plane selection, and calibration/transform digests. Fields a
backend cannot establish are `NA` (never guessed), and
`wavelength_status` in
[`at_bands()`](https://cttir.github.io/annotatR/reference/at_bands.md)
flags missing or duplicated wavelengths instead of interpolating them.

## Usage

``` r
at_hsi_meta(x, call = rlang::caller_env())
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A named list with the elements `vendor`, `instrument`, `acquisition_id`,
`format`, `backend`, `image_kind` (`"spectral"`, `"multichannel"`,
`"rgb"` or `"grayscale"`), `width`, `height`, `n_bands`, `n_levels`,
`dtype`, `value_unit` (one of `"raw"`, `"reflectance"`, `"radiance"`,
`"intensity"`, `"absorbance"`, `"unknown"`), `scale_factor`, `offset`,
`nodata`, `valid_range`, `interleave`, `byte_order`, `header_bytes`,
`axis_order`, `pixel_size`, `pixel_unit`, `origin`, `y_direction`,
`series_id`, `plane` (list of zero-based `c`, `z`, `t`),
`wavelength_unit`, `calibration`, `calibration_digest`,
`transform_digest`, `profile`, `window_read` and `pan_sharpened`.

## See also

[`at_bands()`](https://cttir.github.io/annotatR/reference/at_bands.md),
[`at_read_stats()`](https://cttir.github.io/annotatR/reference/at_read_stats.md)

Other images:
[`annotatR-classes`](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
[`at_bands()`](https://cttir.github.io/annotatR/reference/at_bands.md),
[`at_dims()`](https://cttir.github.io/annotatR/reference/at_dims.md),
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

Other hsi:
[`at_band_operations()`](https://cttir.github.io/annotatR/reference/at_band_operations.md),
[`at_band_view()`](https://cttir.github.io/annotatR/reference/at_band_view.md),
[`at_convert_values()`](https://cttir.github.io/annotatR/reference/at_convert_values.md),
[`at_cubert_export_envi()`](https://cttir.github.io/annotatR/reference/at_cubert_export_envi.md),
[`at_read_stats()`](https://cttir.github.io/annotatR/reference/at_read_stats.md),
[`at_tivita_profile()`](https://cttir.github.io/annotatR/reference/at_tivita_profile.md)

## Examples

``` r
at_hsi_meta(at_example_image("cube"))[c("image_kind", "value_unit", "interleave")]
#> $image_kind
#> [1] "spectral"
#> 
#> $value_unit
#> [1] "unknown"
#> 
#> $interleave
#> [1] "bsq"
#> 
```
