# Export a Cubert measurement to a portable ENVI cube

The portable fallback for Cubert data: the CUVIS SDK itself writes an
ENVI export, which annotatR (and tools without the SDK) can then read
through the `envi` backend. Requires `cuvis.r` and a usable CUVIS SDK.

## Usage

``` r
at_cubert_export_envi(path, dir, measurement = 1L, call = rlang::caller_env())
```

## Arguments

- path:

  Path to a `.cu3s` session file.

- dir:

  Output directory for the SDK's ENVI export (created if needed).

- measurement:

  1-based measurement index within the session.

- call:

  The calling environment, for error reporting.

## Value

The files written into `dir` (character), invisibly.

## See also

Other backends:
[`at_backend_detect()`](https://cttir.github.io/annotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/annotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/annotatR/reference/at_backend_list.md),
[`at_backend_register()`](https://cttir.github.io/annotatR/reference/at_backend_register.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md),
[`at_tivita_profile()`](https://cttir.github.io/annotatR/reference/at_tivita_profile.md)

Other hsi:
[`at_band_operations()`](https://cttir.github.io/annotatR/reference/at_band_operations.md),
[`at_band_view()`](https://cttir.github.io/annotatR/reference/at_band_view.md),
[`at_convert_values()`](https://cttir.github.io/annotatR/reference/at_convert_values.md),
[`at_hsi_meta()`](https://cttir.github.io/annotatR/reference/at_hsi_meta.md),
[`at_read_stats()`](https://cttir.github.io/annotatR/reference/at_read_stats.md),
[`at_tivita_profile()`](https://cttir.github.io/annotatR/reference/at_tivita_profile.md)

## Examples

``` r
if (FALSE) { # \dontrun{
at_cubert_export_envi("measurement.cu3s", tempfile("envi-"))
} # }
```
