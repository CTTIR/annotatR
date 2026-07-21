# Create an annotation project

Create an annotation project

## Usage

``` r
at_project(image, layers = list(), ..., call = rlang::caller_env())
```

## Arguments

- image:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  the annotations refer to.

- layers:

  An
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  a list of them, or an empty list (default).

- ...:

  Additional named project metadata (e.g. `name`, `description`).

- call:

  The calling environment, for error reporting.

## Value

An
[annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
bundling the image, layers, metadata, and provenance (creation time,
`annotatR` version, R version, author, and an edit log).

## See also

[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md),
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md)

Other projects:
[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
[`at_remove_layer()`](https://cttir.github.io/annotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/annotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)

## Examples

``` r
# An annot_image comes from at_read_image() or at_example_image():
# proj <- at_project(at_example_image("tissue"),
#                    at_layer("tissue", labels = "tissue"))
```
