# Register an image backend

Backends are how annotatR reads image formats. Each supplies functions
to read an image's metadata, fetch tiles, detect whether it can read a
file, and report whether its optional dependencies are installed.

## Usage

``` r
at_backend_register(
  name,
  read_fn,
  tile_fn,
  detect_fn,
  available_fn,
  description = "",
  extensions = character(),
  call = rlang::caller_env()
)
```

## Arguments

- name:

  Single string backend name (unique).

- read_fn:

  `function(path, ...)` returning an
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- tile_fn:

  `function(img, level, xrange, yrange, bands)` returning a numeric
  array `[y, x, band]`.

- detect_fn:

  `function(path)` returning `TRUE` if the backend can read the file.

- available_fn:

  `function()` returning `TRUE` if the backend's dependencies are
  installed.

- description:

  Single string human-readable description.

- extensions:

  Character vector of file extensions the backend handles.

- call:

  The calling environment, for error reporting.

## Value

The registered `annot_backend`, invisibly.

## See also

[`at_backend_list()`](https://cttir.github.io/annotatR/reference/at_backend_list.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md)

Other backends:
[`at_backend_detect()`](https://cttir.github.io/annotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/annotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/annotatR/reference/at_backend_list.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)
