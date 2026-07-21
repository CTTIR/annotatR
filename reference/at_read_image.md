# Read an image

Read an image into a lightweight
[annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
handle, auto-detecting the backend from the file unless one is named.

## Usage

``` r
at_read_image(path, backend = NULL, ..., call = rlang::caller_env())
```

## Arguments

- path:

  Single string path to an image file.

- backend:

  Optional backend name; auto-detected when `NULL`.

- ...:

  Passed to the backend's reader.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

## See also

[`at_backend_list()`](https://cttir.github.io/annotatR/reference/at_backend_list.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)

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
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md),
[`at_wavelengths()`](https://cttir.github.io/annotatR/reference/at_wavelengths.md)

Other backends:
[`at_backend_detect()`](https://cttir.github.io/annotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/annotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/annotatR/reference/at_backend_list.md),
[`at_backend_register()`](https://cttir.github.io/annotatR/reference/at_backend_register.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)

## Examples

``` r
img <- at_read_image(at_example_path("tissue"))
at_dims(img)
#> [1] 512 512
```
