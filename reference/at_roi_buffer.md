# Buffer an ROI

Buffer an ROI

## Usage

``` r
at_roi_buffer(roi, dist, call = rlang::caller_env())
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- dist:

  Numeric buffer distance in pixels (may be negative to erode).

- call:

  The calling environment, for error reporting.

## Value

An
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with the buffered geometry.

## See also

Other geometry:
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md),
[`at_clamp()`](https://cttir.github.io/annotatR/reference/at_clamp.md),
[`at_fix_geometry()`](https://cttir.github.io/annotatR/reference/at_fix_geometry.md),
[`at_flip_y()`](https://cttir.github.io/annotatR/reference/at_flip_y.md),
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
at_roi_buffer(at_roi_point(10, 10, label = "a"), dist = 5)
#> <annot_roi> a (POLYGON)
#> id: "roi_000000043"  |  level: 0  |  source: manual
#> bbox: [5, 5] - [15, 15]
```
