# Read a bundled example image

Read a bundled example image

## Usage

``` r
at_example_image(
  which = c("tissue", "multiplex", "cube"),
  call = rlang::caller_env()
)
```

## Arguments

- which:

  One of `"tissue"` (RGB raster), `"multiplex"` (4-channel pyramidal
  TIFF), or `"cube"` (40-band ENVI spectral cube).

- call:

  The calling environment, for error reporting.

## Value

An
[annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

## See also

Other example data:
[`at_example_path()`](https://cttir.github.io/annotatR/reference/at_example_path.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md)

Other images:
[`annotatR-classes`](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
[`at_bands()`](https://cttir.github.io/annotatR/reference/at_bands.md),
[`at_dims()`](https://cttir.github.io/annotatR/reference/at_dims.md),
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
img <- at_example_image("tissue")
at_dims(img)
#> [1] 512 512
```
