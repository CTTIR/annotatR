# Declare a TIVITA SpecCube layout profile

A profile states everything needed to decode a bare `*_SpecCube.dat`
file; annotatR never infers these from a file name. The default
arguments describe the documented 640 x 480 x 100-band layout (500-995
nm), which is a profile like any other and can be replaced for a
different device.

## Usage

``` r
at_tivita_profile(
  name = .TIVITA_DEFAULT_PROFILE,
  width = 640L,
  height = 480L,
  bands = 100L,
  header_values = 3L,
  value_bytes = 4L,
  endian = c("big", "little"),
  axis_order = "x,y,band",
  wavelengths = seq(500, 995, by = 5),
  wavelength_unit = "nm",
  value_unit = "reflectance",
  call = rlang::caller_env()
)
```

## Arguments

- name:

  Profile identifier recorded in the image metadata.

- width, height, bands:

  Cube dimensions (columns x, rows y, bands).

- header_values:

  Number of leading values before the payload.

- value_bytes:

  Bytes per value (`4` for float32, `8` for float64).

- endian:

  `"big"` or `"little"`.

- axis_order:

  Storage order from slowest to fastest varying axis; only `"x,y,band"`
  (the numpy C-order TIVITA layout) is supported.

- wavelengths:

  Numeric band-centre wavelengths (length `bands`) or `NULL` when
  unknown.

- wavelength_unit:

  Wavelength unit, default `"nm"`.

- value_unit:

  What the values mean: one of `"raw"`, `"reflectance"`, `"radiance"`,
  `"intensity"`, `"absorbance"`, `"unknown"`.

- call:

  The calling environment, for error reporting.

## Value

A list of class `at_tivita_profile`.

## See also

[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md)

Other hsi:
[`at_band_operations()`](https://cttir.github.io/annotatR/reference/at_band_operations.md),
[`at_band_view()`](https://cttir.github.io/annotatR/reference/at_band_view.md),
[`at_convert_values()`](https://cttir.github.io/annotatR/reference/at_convert_values.md),
[`at_cubert_export_envi()`](https://cttir.github.io/annotatR/reference/at_cubert_export_envi.md),
[`at_hsi_meta()`](https://cttir.github.io/annotatR/reference/at_hsi_meta.md),
[`at_read_stats()`](https://cttir.github.io/annotatR/reference/at_read_stats.md)

Other backends:
[`at_backend_detect()`](https://cttir.github.io/annotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/annotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/annotatR/reference/at_backend_list.md),
[`at_backend_register()`](https://cttir.github.io/annotatR/reference/at_backend_register.md),
[`at_cubert_export_envi()`](https://cttir.github.io/annotatR/reference/at_cubert_export_envi.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)

## Examples

``` r
at_tivita_profile()$bands
#> [1] 100
small <- at_tivita_profile("bench_4x3x2", width = 4, height = 3, bands = 2,
                           wavelengths = c(600, 700))
```
