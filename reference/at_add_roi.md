# Add an ROI to a project layer

Add an ROI to a project layer

## Usage

``` r
at_add_roi(project, layer, roi, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- layer:

  Single string name of the target layer.

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with the ROI added to the layer. A colliding ROI identifier is re-minted
to keep identifiers unique across the project. The input is unchanged.

## See also

Other projects:
[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/annotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/annotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)
