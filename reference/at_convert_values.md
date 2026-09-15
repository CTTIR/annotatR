# Convert spectral values between declared units

The only supported ways to change value semantics. Raw counts become
reflectance through an explicit dark/white calibration, and reflectance
becomes (pseudo-)absorbance as `-log10(reflectance)`. Anything else, or
a conversion without the calibration it needs, is refused with a
classified error instead of being approximated.

## Usage

``` r
at_convert_values(
  x,
  from = NULL,
  to = c("reflectance", "absorbance"),
  calibration = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- x:

  A numeric vector, matrix or `[y, x, band]` array of values.

- from:

  The unit of `x`: one of `"raw"`, `"reflectance"`, `"radiance"`,
  `"intensity"`, `"absorbance"`. Taken from `attr(x, "value_unit")` when
  `NULL`.

- to:

  Target unit: `"reflectance"` or `"absorbance"`.

- calibration:

  For `raw -> reflectance`, a list with numeric `white` and `dark`
  references (scalars, or one value per band for arrays).

- call:

  The calling environment, for error reporting.

## Value

`x` converted, with attribute `value_unit` set to `to` and `conversion`
recording the operation. Reflectance values `<= 0` give `NA` absorbance;
a zero white-minus-dark denominator gives `NA`.

## See also

Other hsi:
[`at_band_operations()`](https://cttir.github.io/annotatR/reference/at_band_operations.md),
[`at_band_view()`](https://cttir.github.io/annotatR/reference/at_band_view.md),
[`at_cubert_export_envi()`](https://cttir.github.io/annotatR/reference/at_cubert_export_envi.md),
[`at_hsi_meta()`](https://cttir.github.io/annotatR/reference/at_hsi_meta.md),
[`at_read_stats()`](https://cttir.github.io/annotatR/reference/at_read_stats.md),
[`at_tivita_profile()`](https://cttir.github.io/annotatR/reference/at_tivita_profile.md)

## Examples

``` r
at_convert_values(c(0.5, 0.1), from = "reflectance", to = "absorbance")
#> [1] 0.30103 1.00000
#> attr(,"value_unit")
#> [1] "absorbance"
#> attr(,"conversion")
#> [1] "reflectance->absorbance"
at_convert_values(c(100, 550, 1000), from = "raw", to = "reflectance",
                  calibration = list(white = 1000, dark = 100))
#> [1] 0.0 0.5 1.0
#> attr(,"value_unit")
#> [1] "reflectance"
#> attr(,"conversion")
#> [1] "raw->reflectance"
```
