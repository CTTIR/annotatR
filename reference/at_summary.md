# Summarise a project

Summarise a project

## Usage

``` r
at_summary(project, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

An `annot_summary` object: a list with `n_layers`, `n_rois`, per-label
ROI counts, and total area per label.

## See also

Other projects:
[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/annotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/annotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)

## Examples

``` r
at_summary(at_example_project())
#> <annot_summary> example
#> layers: 1  |  ROIs: 3
#>   "necrosis": 1 ROI, area 72704 px
#>   "stroma": 1 ROI, area 34200 px
#>   "tumour": 1 ROI, area 19600 px
```
