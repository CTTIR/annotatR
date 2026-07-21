# Band (channel) table

Band (channel) table

## Usage

``` r
at_bands(x, call = rlang::caller_env())
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per band and the columns:

- `index`:

  Band index, 1-based (integer).

- `name`:

  Band name (character); a default `"Band k"` when unnamed.

- `wavelength`:

  Centre wavelength (double); `NA` when not spectral.

- `unit`:

  Wavelength unit (character); `NA` when not spectral.

Always has `at_n_bands(x)` rows.

## See also

Other images:
[`annotatR-classes`](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
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
