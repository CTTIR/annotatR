# Remove a layer from a project

Remove a layer from a project

## Usage

``` r
at_remove_layer(project, name, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- name:

  Single string layer name.

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
without the named layer. The input is unchanged.

## See also

Other projects:
[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
[`at_remove_roi()`](https://cttir.github.io/annotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)
