# Path to a bundled example file

Path to a bundled example file

## Usage

``` r
at_example_path(
  which = c("tissue", "multiplex", "cube"),
  call = rlang::caller_env()
)
```

## Arguments

- which:

  One of `"tissue"`, `"multiplex"`, or `"cube"`.

- call:

  The calling environment, for error reporting.

## Value

A single string file path to the example asset.

## See also

Other example data:
[`at_example_image()`](https://cttir.github.io/annotatR/reference/at_example_image.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md)

## Examples

``` r
at_example_path("tissue")
#> [1] "/home/runner/work/_temp/Library/annotatR/extdata/example_tissue.png"
```
