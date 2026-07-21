# Flip an ROI's y-axis

Convert between image orientation (top-left origin, y down) and GIS
orientation (bottom-left origin, y up). Self-inverse.

## Usage

``` r
at_flip_y(roi, height, call = rlang::caller_env())
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- height:

  Numeric image height in pixels at the ROI's reference level.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with the y-axis flipped.

## See also

Other geometry:
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md),
[`at_clamp()`](https://cttir.github.io/annotatR/reference/at_clamp.md),
[`at_fix_geometry()`](https://cttir.github.io/annotatR/reference/at_fix_geometry.md),
[`at_roi_buffer()`](https://cttir.github.io/annotatR/reference/at_roi_buffer.md),
[`at_roi_contains()`](https://cttir.github.io/annotatR/reference/at_roi_contains.md),
[`at_roi_distance()`](https://cttir.github.io/annotatR/reference/at_roi_distance.md),
[`at_roi_overlaps()`](https://cttir.github.io/annotatR/reference/at_roi_overlaps.md),
[`at_roi_rescale()`](https://cttir.github.io/annotatR/reference/at_roi_rescale.md),
[`at_roi_setops`](https://cttir.github.io/annotatR/reference/at_roi_setops.md),
[`at_roi_simplify()`](https://cttir.github.io/annotatR/reference/at_roi_simplify.md),
[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)

## Examples

``` r
at_flip_y(at_roi_rect(0, 0, 10, 5, label = "a"), height = 100)
#> <annot_roi> a (POLYGON)
#> id: "roi_000000012"  |  level: 0  |  source: manual
#> bbox: [0, 95] - [10, 100]
```
