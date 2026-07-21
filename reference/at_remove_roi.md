# Remove an ROI from a project

Remove an ROI from a project

## Usage

``` r
at_remove_roi(project, id, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- id:

  Single string ROI identifier.

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
without the identified ROI. Warns and returns the project unchanged if
the identifier is not found.

## See also

Other projects:
[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/annotatR/reference/at_remove_layer.md),
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)
