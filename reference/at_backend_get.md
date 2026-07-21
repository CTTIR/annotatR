# Get a registered backend

Get a registered backend

## Usage

``` r
at_backend_get(name, call = rlang::caller_env())
```

## Arguments

- name:

  Single string backend name.

- call:

  The calling environment, for error reporting.

## Value

The `annot_backend` object.

## See also

Other backends:
[`at_backend_detect()`](https://cttir.github.io/annotatR/reference/at_backend_detect.md),
[`at_backend_list()`](https://cttir.github.io/annotatR/reference/at_backend_list.md),
[`at_backend_register()`](https://cttir.github.io/annotatR/reference/at_backend_register.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)
