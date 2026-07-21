# Layer summary table

Layer summary table

## Usage

``` r
at_layers(project, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per layer and the columns `name` (character), `n_rois`
(integer), `labels` (list of character), `visible` (logical), `locked`
(logical), and `z` (integer). A 0-row tibble with these columns when the
project has no layers.

## See also

Other projects:
[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/annotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/annotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)
