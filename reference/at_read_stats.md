# Read accounting for an image

Report how many tiles were requested from an image's backend, how many
payload bytes were read from its file by windowed readers, and how many
bytes were returned as decoded arrays. Cache hits are not counted as
reads.

## Usage

``` r
at_read_stats(img, reset = FALSE, call = rlang::caller_env())
```

## Arguments

- img:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- reset:

  Logical; reset the counters for this image after reporting.

- call:

  The calling environment, for error reporting.

## Value

A list with `tiles` (integer), `file_bytes`, `decoded_bytes` and
`max_tile_bytes` (doubles), plus `window_read` (logical) and the current
`max_tile_bytes_limit` from option `annotatR.max_tile_bytes`.

## See also

Other hsi:
[`at_band_operations()`](https://cttir.github.io/annotatR/reference/at_band_operations.md),
[`at_band_view()`](https://cttir.github.io/annotatR/reference/at_band_view.md),
[`at_convert_values()`](https://cttir.github.io/annotatR/reference/at_convert_values.md),
[`at_cubert_export_envi()`](https://cttir.github.io/annotatR/reference/at_cubert_export_envi.md),
[`at_hsi_meta()`](https://cttir.github.io/annotatR/reference/at_hsi_meta.md),
[`at_tivita_profile()`](https://cttir.github.io/annotatR/reference/at_tivita_profile.md)

## Examples

``` r
cube <- at_example_image("cube")
invisible(at_tile(cube, xrange = c(1, 4), yrange = c(1, 4), bands = 1:2))
at_read_stats(cube)$tiles
#> [1] 3
```
