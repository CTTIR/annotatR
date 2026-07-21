# Detect the backend for a file

Detect the backend for a file

## Usage

``` r
at_backend_detect(path, call = rlang::caller_env())
```

## Arguments

- path:

  Single string file path.

- call:

  The calling environment, for error reporting.

## Value

The name of the first available backend (in priority order) that can
read `path`. Errors informatively if none can.

## See also

Other backends:
[`at_backend_get()`](https://cttir.github.io/annotatR/reference/at_backend_get.md),
[`at_backend_list()`](https://cttir.github.io/annotatR/reference/at_backend_list.md),
[`at_backend_register()`](https://cttir.github.io/annotatR/reference/at_backend_register.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)
