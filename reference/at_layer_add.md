# Add an ROI to a layer

Add an ROI to a layer

## Usage

``` r
at_layer_add(layer, roi, call = rlang::caller_env())
```

## Arguments

- layer:

  An
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with the ROI appended. The label vocabulary and colour mapping are
extended if the ROI introduces a new label. A colliding ROI identifier
is re-minted to preserve uniqueness. The input is unchanged.

## See also

Other layers:
[`at_layer()`](https://cttir.github.io/annotatR/reference/at_layer.md),
[`at_layer_n()`](https://cttir.github.io/annotatR/reference/at_layer_n.md),
[`at_layer_remove()`](https://cttir.github.io/annotatR/reference/at_layer_remove.md),
[`at_layer_rois()`](https://cttir.github.io/annotatR/reference/at_layer_rois.md),
[`at_style()`](https://cttir.github.io/annotatR/reference/at_style.md)

## Examples

``` r
lyr <- at_layer("tumour", labels = "tumour")
lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 10, 10, label = "tumour"))
at_layer_n(lyr)
#> [1] 1
```
