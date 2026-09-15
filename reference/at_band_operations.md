# Registered band operations

List the display band operations the app and the control service accept.
Derived views are display products: they carry their parent digest, band
list, operation and parameters, and are never written back as analysis
input.

## Usage

``` r
at_band_operations()
```

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `operation`, `n_bands` (integer; `NA` means one or more),
`params` (comma-separated parameter names) and `description`.

## See also

Other hsi:
[`at_band_view()`](https://cttir.github.io/annotatR/reference/at_band_view.md),
[`at_convert_values()`](https://cttir.github.io/annotatR/reference/at_convert_values.md),
[`at_cubert_export_envi()`](https://cttir.github.io/annotatR/reference/at_cubert_export_envi.md),
[`at_hsi_meta()`](https://cttir.github.io/annotatR/reference/at_hsi_meta.md),
[`at_read_stats()`](https://cttir.github.io/annotatR/reference/at_read_stats.md),
[`at_tivita_profile()`](https://cttir.github.io/annotatR/reference/at_tivita_profile.md)

## Examples

``` r
at_band_operations()
#> # A tibble: 6 × 4
#>   operation              n_bands params                          description    
#>   <chr>                    <int> <chr>                           <chr>          
#> 1 single                       1 ""                              One band shown…
#> 2 rgb                          3 ""                              Three bands as…
#> 3 ratio                        2 ""                              Band ratio a /…
#> 4 normalized_difference        2 ""                              (a - b) / (a +…
#> 5 band_mean                   NA ""                              Mean over the …
#> 6 wavelength_window_mean      NA "wavelength_min,wavelength_max" Mean over band…
```
